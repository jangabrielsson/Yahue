-- hue-transport.lua — Hue v2 API transport layer
-- SSE event polling, HTTP GET/PUT, rate-limit governor, bucketed command queueing.
-- Extracted from engine.lua. Called by engine.lua's main() with a shared context table.

fibaro.hueTransport = fibaro.hueTransport or {}

function fibaro.hueTransport.define(ctx)
  local DEBUG, WARNING, ERROR = ctx.DEBUG, ctx.WARNING, ctx.ERROR
  local debugFlags = ctx.debugFlags
  local fmt = ctx.fmt
  local post = ctx.post
  local HUE = ctx.HUE

  -- Constants — tuned against real bridge behaviour (see test/testhue.lua probe).
  -- Most Hue bridges recover from 429 in ≤ 1 s and sustain 100+ GET/s.
  -- PUT throughput is typically lower but 50/s per bucket is safe.
  local COOLDOWN_BASE = 2            -- baseline; probe shows ≤ 1 s recovery
  local COOLDOWN_MAX = 60            -- cap on escalation
  local HEALTH_RESET_S = 120         -- 2 min of health resets escalation
  local ESCALATE_WINDOW_S = 60       -- look-back window for clustered 429s
  local ESCALATE_THRESHOLD = 3       -- ≥ N 429s in window to escalate

  -- Mutable governor state (aliased from ctx; written back at end)
  local bridgeHealthy = ctx.bridgeHealthy
  local bridgeCoolUntil = ctx.bridgeCoolUntil
  local bridgeNoticeAt = ctx.bridgeNoticeAt
  local bridgeLastHealthy = ctx.bridgeLastHealthy
  local cooldownDefault = ctx.cooldownDefault
  local recent429 = ctx.recent429

  ---------------------------------------------------------------------------
  -- SSE EVENT POLLING
  ---------------------------------------------------------------------------
  local fetchEvents
  local function handle_events(data)
    for _,e1 in ipairs(data) do
      if e1.type=='update' then
        for _,r in ipairs(e1.data) do
          -- SSE liveness probe: detect echo of our no-op PUT before normal
          -- dispatch. We accept ANY update event referencing the probe id
          -- (the bridge may emit a service-level event with a different
          -- type than the resource we PUT to).
          if ctx._sseProbe and (r.id == ctx._sseProbe.id or r.owner and r.owner.rid == ctx._sseProbe.id) then
            local probe = ctx._sseProbe
            ctx._sseProbe = nil
            if probe.timer then clearTimeout(probe.timer) end
            local rtt = os.time() - probe.t0
            WARNING("SSE ping: echo received in ~%ds (id=%s type=%s)", rtt, r.id, r.type or "?")
            if probe.cb then pcall(probe.cb, true, rtt) end
          end
          local d = ctx.resources.get(r.id)
          if d and d.event then
            DEBUG('all_event',"Event id:%s type:%s",d.id,d.type)
            d:annotateEvent(r)
            d:event(r)
          else
            local _ = 0
            if debugFlags and debugFlags.unknownType then WARNING("Unknow resource type: %s",json.encode(e1)) end
          end
        end
      elseif e1.type == 'delete' then
        for _,r in ipairs(e1.data) do
          ctx.resources.changeHook()
          ctx.resources.delete(r.id)
        end
      elseif e1.type == 'add' then
        for _,r in ipairs(e1.data) do
          ctx.resources.changeHook()
          ctx.resources.add(r.id,r)
        end
      else
        DEBUG('v2api',"New v2 event type: %s",e1.type)
        DEBUG('v2api',"%s",json.encode(e1))
      end
    end
  end

  local function fetchEvents_emu()
    local getw
    local eurl = ctx.url.."/eventstream/clip/v2"
    local backoff = 0
    local args = { options = { 
      method='GET', 
      checkCertificate=false, 
      headers={ 
        ['hue-application-key'] = ctx.app_key,
        ['Accept'] = "application/json",
      }}
    }
    local function bumpBackoff()
      if backoff == 0 then backoff = 1000
      else backoff = math.min(backoff * 2, 30000) end
      return backoff
    end
    function args.success(res)
      if res and res.status and res.status >= 300 then
        if res.status == 429 then
          local ra = parseRetryAfter(res)
          enterCooldown(ra, "SSE")
          local d = math.max(bridgeWaitMs(), bumpBackoff())
          WARNING("/eventstream: HTTP 429 (retry in %dms)", d)
          setTimeout(getw, d)
        else
          local d = math.max(bridgeWaitMs(), bumpBackoff())
          WARNING("/eventstream: HTTP %d (retry in %dms)", res.status, d)
          setTimeout(getw, d)
        end
        return
      end
      backoff = 0
      local ok,err = pcall(function()
        local data = json.decode(res.data)
        handle_events(data)
      end)
      if not ok then WARNING("/eventstream parse: %s", tostring(err)) end
      getw()
    end
    function args.error(err)
      local transient = err and (err:match("timed out") or err == "wantread")
      if not transient then
        local d = bumpBackoff()
        WARNING("/eventstream: %s (retry in %dms)", err, d)
        setTimeout(getw, d)
      else
        getw()
      end
    end
    function getw() net.HTTPClient():request(eurl,args) end
    setTimeout(getw,0)
  end

  local function fetchEvents_hc3()
    local getw
    local eurl = ctx.url.."/eventstream/clip/v2"
    local backoff = 0
    local lastSeen = 0
    local epoch = 0
    local function bumpBackoff()
      if backoff == 0 then backoff = 1000
      else backoff = math.min(backoff * 2, 300000) end
      return backoff
    end
    function getw()
      epoch = epoch + 1
      local myEpoch = epoch
      lastSeen = os.time()
      HUE._lastSseSeen = lastSeen
      local args = {
        options = {
          method='GET',
          checkCertificate=false,
          headers={
            ["hue-application-key"] = ctx.app_key,
            ['Accept'] = "text/event-stream"
          },
          timeout = 60000
        }
      }
      function args.success(res)
        if myEpoch ~= epoch then return end
        if res and res.status and res.status >= 300 then
          if res.status == 429 then
            local ra = parseRetryAfter(res)
            enterCooldown(ra, "SSE")
            backoff = 0
            local d = bridgeWaitMs()
            WARNING("/eventstream: HTTP 429 (retry in %dms)", d)
            setTimeout(getw, d)
          else
            local d = math.max(bridgeWaitMs(), bumpBackoff())
            WARNING("/eventstream: HTTP %d (retry in %dms)", res.status, d)
            setTimeout(getw, d)
          end
          return
        end
        lastSeen = os.time()
        HUE._lastSseSeen = lastSeen
        local parsed = false
        local stat,err = pcall(function()
          local body = res and res.data
          if type(body) ~= 'string' or body == '' then return end
          if body:match("^: hi") then return end
          local arr = body:match("(%b[])")
          if not arr then return end
          local data = json.decode(arr)
          if data then
            handle_events(data)
            parsed = true
          end
        end)
        if not stat then
          if myEpoch ~= epoch then return end
          local d = bumpBackoff()
          WARNING("/eventstream parse: %s (retry in %dms)", tostring(err), d)
          setTimeout(getw, d)
        elseif parsed then
          backoff = 0
        end
      end
      function args.error(err)
        if myEpoch ~= epoch then return end
        local errStr = tostring(err or "")
        if errStr:find("429", 1, true) then
          enterCooldown(nil, "SSE")
          backoff = 0
          local d = bridgeWaitMs()
          WARNING("/eventstream: HTTP 429 (retry in %dms)", d)
          setTimeout(getw, d)
          return
        end
        local transient = err == "timeout" or err == "wantread"
                       or err == "Operation canceled"
        if not transient then
          local d = math.max(bridgeWaitMs(), bumpBackoff())
          local short = errStr:gsub("%s+", " "):sub(1, 120)
          WARNING("/eventstream: %s (retry in %dms)", short, d)
          if backoff > 1000 then
            HUE._resyncOnRefresh = true
            post({type='REFRESH_RESOURCES'})
          end
          setTimeout(getw, d)
        else
          DEBUG('info', "/eventstream transient: %s, reconnecting in 1s", tostring(err))
          setTimeout(getw, 1000)
        end
      end
      net.HTTPClient():request(eurl,args)
    end
    setTimeout(getw,0)
  end

  if fibaro.plua then fetchEvents = fetchEvents_emu
  else fetchEvents = fetchEvents_hc3 end
  fetchEvents = fetchEvents_hc3
  ---------------------------------------------------------------------------
  -- HTTP TRANSPORT
  ---------------------------------------------------------------------------
  function hueGET(api,event)
    local u = ctx.url..api
    net.HTTPClient():request(u,{
      options = { 
        method='GET',
        checkCertificate=false, 
        headers={ 
          ['hue-application-key'] = ctx.app_key,
          ["Accept"] = "application/json",
        }
      },
      success = function(res) 
        if res.status < 300 then
          post({type=event,result=json.decode(res.data)}) 
        else
          post({type=event,error={status=res.status, retryAfter=parseRetryAfter(res)}})
        end
      end,
      error = function(err) post({type=event,error=err})  end,
    })
  end

  ---------------------------------------------------------------------------
  -- BRIDGE RATE-LIMIT GOVERNOR
  ---------------------------------------------------------------------------

  function parseRetryAfter(resp)
    local h = resp and resp.headers
    if type(h) == 'table' then
      local v = h['Retry-After'] or h['retry-after'] or h['RETRY-AFTER']
      if v then
        local n = tonumber(tostring(v):match("(%d+)"))
        if n and n > 0 then return n end
      end
    end
    return nil
  end

  function enterCooldown(seconds, source)
    local now = os.time()
    local kept = {}
    for _, t in ipairs(recent429) do
      if now - t <= ESCALATE_WINDOW_S then kept[#kept+1] = t end
    end
    kept[#kept+1] = now
    recent429 = kept
    if not seconds and #recent429 >= ESCALATE_THRESHOLD then
      cooldownDefault = math.min(cooldownDefault * 2, COOLDOWN_MAX)
    end
    local secs = seconds or cooldownDefault
    local until_ = now + secs
    if until_ > bridgeCoolUntil then bridgeCoolUntil = until_ end
    bridgeHealthy = false
    if now - bridgeNoticeAt >= 10 then
      bridgeNoticeAt = now
      WARNING("Hue bridge 429 from %s, pausing all traffic for %ds (recent 429s: %d)",
        source or 'PUT', secs, #recent429)
    end
  end

  function bridgeWaitMs()
    if bridgeHealthy then return 0 end
    local now = os.time()
    if bridgeCoolUntil <= now then
      if not bridgeHealthy and now - bridgeLastHealthy >= HEALTH_RESET_S then
        cooldownDefault = COOLDOWN_BASE
      end
      bridgeHealthy = true
      bridgeLastHealthy = now
      return 0
    end
    return math.max(0, (bridgeCoolUntil - now) * 1000)
  end

  function bridgeReady()
    return bridgeHealthy and bridgeCoolUntil <= os.time()
  end

  ---------------------------------------------------------------------------
  -- BUCKETED PUT QUEUEING
  ---------------------------------------------------------------------------
  local QUEUE_CAP = 20
  local QUEUE_TTL_S = 5
  local MAX_RETRIES = 2
  local RETRY_DELAY_MS = 500
  -- Bucket refill rates (ms between sends).  Tuned against probe data:
  -- the bridge can sustain 50+ PUT/s per resource family safely.
  local BUCKETS = {
    light   = { name="light",   refillMs=20,   queue={}, inFlight=false },
    grouped = { name="grouped", refillMs=20,   queue={}, inFlight=false },
    scene   = { name="scene",   refillMs=50,   queue={}, inFlight=false },
    other   = { name="other",   refillMs=100,  queue={}, inFlight=false },
  }

  local function bucketFor(path)
    local fam = path:match("/light/([^/]+)") or
                path:match("/grouped_light") or
                path:match("/scene") or "other"
    if fam == "grouped_light" then return BUCKETS.grouped end
    return BUCKETS[fam] or BUCKETS.other
  end

  local function clearAllQueues(reason)
    for fam, b in pairs(BUCKETS) do
      if #b.queue > 0 then
        DEBUG('call', "Hue queue purge (%s): %d items from %s", reason, #b.queue, fam)
        b.queue = {}
      end
    end
  end

  local tickBucket, sendOne

  sendOne = function(b, item, retryCount)
    DEBUG('call', "%s %s", item.path, json.encode(item.data))
    net.HTTPClient():request(ctx.url..item.path, {
      options = {
        method = item.op or 'PUT',
        data = item.data and json.encode(item.data) or nil,
        checkCertificate = false,
        ['content-type'] = "application/json",
        headers = { ['hue-application-key'] = ctx.app_key }
      },
      success = function(resp)
        if resp.status == 429 then
          if retryCount >= MAX_RETRIES then
            WARNING("hue PUT 429 give-up after %d retries: %s", MAX_RETRIES, item.path)
            enterCooldown(parseRetryAfter(resp), "PUT")
            -- Only flush this bucket — other buckets may still be valid
            -- after the cooldown window (TTL will drop stale items).
            if #b.queue > 0 then
              DEBUG('call', "Hue queue purge (429): %d items from %s", #b.queue, b.name)
              b.queue = {}
            end
            b.inFlight = false
            return
          end
          setTimeout(function() sendOne(b, item, retryCount + 1) end, RETRY_DELAY_MS)
          return
        end
        local body = resp.data and json.decode(resp.data)
        if body and body.errors and #body.errors > 0 then
          WARNING("hue PUT error, %s - %s", item.path, json.encode(body.errors))
        end
        b.inFlight = false
        setTimeout(function() tickBucket(b) end, b.refillMs)
      end,
      error = function(err)
        WARNING("hue call, %s %s - %s", item.path, json.encode(item.data), err)
        b.inFlight = false
        setTimeout(function() tickBucket(b) end, b.refillMs)
      end,
    })
  end

  tickBucket = function(b)
    if b.inFlight then return end
    if not bridgeReady() then
      if #b.queue > 0 then
        DEBUG('call', "Hue queue dropped (bridge cooldown): %d items from %s", #b.queue, b.name)
        b.queue = {}
      end
      return
    end
    while b.queue[1] and (os.time() - b.queue[1].enqueuedAt) > QUEUE_TTL_S do
      local stale = table.remove(b.queue, 1)
      DEBUG('call', "Hue queue TTL drop: %s", stale.path)
    end
    local item = table.remove(b.queue, 1)
    if not item then return end
    b.inFlight = true
    sendOne(b, item, 0)
  end

  function huePUT(path, data, op, slot)
    if not bridgeReady() then
      DEBUG('call', "huePUT dropped (bridge cooldown %ds left): %s",
        bridgeCoolUntil - os.time(), path)
      return false
    end
    local b = bucketFor(path)
    local dedupKey = slot or op or 'PUT'
    for _, entry in ipairs(b.queue) do
      if entry.path == path and entry.slot == dedupKey then
        entry.data = data
        entry.enqueuedAt = os.time()
        tickBucket(b)
        return true
      end
    end
    if #b.queue >= QUEUE_CAP then
      local dropped = table.remove(b.queue, 1)
      DEBUG('call', "Hue queue cap reached, dropped oldest: %s", dropped.path)
    end
    b.queue[#b.queue + 1] = {
      path = path, data = data, op = op, slot = dedupKey,
      enqueuedAt = os.time(),
    }
    tickBucket(b)
    return true
  end

  -- Write back to context
  ctx.hueGET = hueGET
  ctx.huePUT = huePUT
  ctx.fetchEvents = fetchEvents
  ctx.handle_events = handle_events
  ctx.enterCooldown = enterCooldown
  ctx.parseRetryAfter = parseRetryAfter
  ctx.bridgeWaitMs = bridgeWaitMs
  ctx.bridgeReady = bridgeReady
  ctx.bridgeHealthy = bridgeHealthy
  ctx.bridgeCoolUntil = bridgeCoolUntil
  ctx.bridgeNoticeAt = bridgeNoticeAt
  ctx.bridgeLastHealthy = bridgeLastHealthy
  ctx.cooldownDefault = cooldownDefault
  ctx.recent429 = recent429
end
