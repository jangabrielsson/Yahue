-- hue-startup.lua — Hue v2 engine startup and public API
-- State machine, health checks, public API, dump utilities, _initEngine.
-- Extracted from engine.lua. Called by engine.lua's main() with a shared context table.

fibaro.hueStartup = fibaro.hueStartup or {}

function fibaro.hueStartup.define(ctx)
  local DEBUG, WARNING, ERROR = ctx.DEBUG, ctx.WARNING, ctx.ERROR
  local fmt = ctx.fmt
  local post = ctx.post

  -- Silent variable reader — does NOT log a warning when the variable
  -- is missing (unlike quickApp:getVariable).
  local function getVar(name, default)
    local qvars = quickApp and quickApp.properties and quickApp.properties.quickAppVariables
    if qvars then
      for _, v in ipairs(qvars) do
        if v.name == name then return v.value end
      end
    end
    return default
  end
  local resources = ctx.resources
  local hueGET = ctx.hueGET
  local huePUT = ctx.huePUT
  local callBack = ctx.callBack
  local v2 = ctx.v2
  local err_retry = ctx.err_retry
  local enterCooldown = ctx.enterCooldown
  local parseRetryAfter = ctx.parseRetryAfter
  local bridgeWaitMs = ctx.bridgeWaitMs
  local resolve = ctx.resolve
  local merge = ctx.merge
  local strip = ctx.strip
  local HUE = ctx.HUE
  local fetchEvents = ctx.fetchEvents
  local createResourceTable = ctx.createResourceTable
  local findPingTarget = ctx.findPingTarget
  local doSSEPing = ctx.doSSEPing
  local _version_e = ctx._version_e

  -- State machine locals
  local refreshInFlight = ctx.refreshInFlight
  local refreshBlockedUntil = ctx.refreshBlockedUntil
  local refreshBackoff = err_retry

  ---------------------------------------------------------------------------
  -- STARTUP STATE MACHINE
  ---------------------------------------------------------------------------
  fibaro.event({type='STARTUP'},function(_) hueGET("/api/config",'HUB_VERSION') end)
  
  fibaro.event({type='HUB_VERSION'},function(ev)
    if ev.error then
      ERROR("%s",ev.error)
    else
      ctx.resources = createResourceTable()
      resources = ctx.resources
      local res = ev.result
      if res.swversion >= v2 then
        DEBUG('info',"V2 api available (%s)",res.swversion)
        post({type='REFRESH_RESOURCES'})
      else
        WARNING("V2 api not available (%s)",res.swversion)
      end
    end
  end)
  
  fibaro.event({type='REFRESH_RESOURCES'},function(_)
    if refreshInFlight then return end
    if os.time() < refreshBlockedUntil then return end
    refreshInFlight = true
    hueGET("/clip/v2/resource",'REFRESHED_RESOURCES')
  end)

  fibaro.event({type='REFRESHED_RESOURCES'},function(ev)
    refreshInFlight = false
    if ev.error then
      local status, retryAfter
      if type(ev.error) == 'table' then
        status, retryAfter = ev.error.status, ev.error.retryAfter
      else
        status = ev.error
      end
      local is429 = tonumber(status) == 429
      if is429 then enterCooldown(retryAfter, "GET refresh") end
      local waitMs
      if is429 then
        waitMs = bridgeWaitMs()
        refreshBackoff = err_retry
      else
        local cool = retryAfter or refreshBackoff
        waitMs = math.max(1000 * cool, bridgeWaitMs())
        refreshBackoff = math.min(refreshBackoff * 2, 300)
      end
      local effectiveS = math.max(1, math.floor(waitMs / 1000))
      WARNING("/clip/v2/resource HTTP error: %s", tostring(status))
      WARNING("Retry in %ss", effectiveS)
      refreshBlockedUntil = os.time() + effectiveS
      post({type='REFRESH_RESOURCES'}, waitMs)
      return
    end
    refreshBackoff = err_retry
    refreshBlockedUntil = 0
    for _,r in pairs(resources.id2resource) do
      r._dirty = true
    end
    for _,r in ipairs(ev.result.data or {}) do
      resources.add(r.id,r)
      local existing = resources.id2resource[r.id]
      if existing then existing._dirty = nil end
    end
    for _,r in pairs(resources.id2resource) do
      if r._dirty then
        resources.delete(r.id)
      end
    end
    if HUE._resyncOnRefresh then
      HUE._resyncOnRefresh = nil
      DEBUG('v2api',"Re-publishing resource state after reconnect")
      for _,r in pairs(resources.id2resource) do
        local typ = r.rsrc and r.rsrc.type
        -- Skip input-only types: re-publishing their last event
        -- would trigger false button presses / rotary events on restart.
        if typ ~= "button" and typ ~= "relative_rotary" and typ ~= "motion" then
          pcall(function() r:publishAll() end)
        end
      end
    end
    local cb
    if callBack then cb,callBack=callBack,nil setTimeout(cb,0) end
  end)
  
  ---------------------------------------------------------------------------
  -- HUE PUBLIC API
  ---------------------------------------------------------------------------
  function HUE:getResources() return resources.resources end
  function HUE:getResourceIds() return resources.id2resource end
  function HUE:getResource(id) return resources.id2resource[id] end
  function HUE:getResourceType(typ) return resources.resources[typ] or {} end
  function HUE:_resolve(id) return resolve(id) end
  function HUE:pingSSE(timeoutSec, cb)
    timeoutSec = tonumber(timeoutSec) or 10
    if ctx._sseProbe then
      if cb then pcall(cb, false, "probe already in flight") end
      return false
    end
    local target
    for _,typ in ipairs({"zone","room","light"}) do
      local pool = resources.resources[typ]
      if pool then
        for _,r in pairs(pool) do
          if r.rsrc and r.rsrc.metadata and r.rsrc.metadata.name then
            target = r ; break
          end
        end
      end
      if target then break end
    end
    if not target then
      if cb then pcall(cb, false, "no suitable resource for ping") end
      return false
    end
    local origName = target.rsrc.metadata.name
    local MARK = "\u{00B7}"
    local newName
    if origName:sub(-#MARK) == MARK then newName = origName:sub(1, -#MARK-1)
    else newName = origName .. MARK end
    ctx._sseProbe = { id = target.id, t0 = os.time(), cb = cb }
    ctx._sseProbe.timer = setTimeout(function()
      if ctx._sseProbe then
        local p = ctx._sseProbe ; ctx._sseProbe = nil
        WARNING("SSE ping: NO echo within %ds (id=%s)", timeoutSec, p.id)
        if p.cb then pcall(p.cb, false, "timeout") end
      end
    end, timeoutSec * 1000)
    DEBUG('call',"SSE ping: PUT %s metadata.name=%q (was %q)", target.path, newName, origName)
    huePUT(target.path, { metadata = { name = newName } })
    return true
  end
  function HUE:getSceneByName(name,roomzone)
    local scenes = self:getResourceType('scene')
    for id,scene in pairs(scenes) do
      if scene.name == name then
        if not roomzone then return scene end
        local g = scene.rsrc.group and resolve(scene.rsrc.group) or {}
        if g.name == roomzone then return scene end
      end
    end
  end
  local filter1 = { device=1, scene=10, room=2, zone=3 }
  
  local filter2 = { device=1, light=4, button=5, relative_rotary=5.5, scene=10, room=2, zone=3, temperature=6, light_level=7, motion=8, tamper=7.5, contact=7.6, grouped_light=9, zigbee_connectivity=10, device_power=11 }
  
  local function printBuffer(init) 
    local b = {init}
    function b:add(s) b[#b+1]=s end
    function b:printf(fmt,...) b:add(fmt:format(...)) end
    function b:tostring() return table.concat(b) end
    return b
  end
  fibaro.printBuffer = printBuffer
  
  function HUE:dumpDeviceTable(filter,selector,orgDevMap)
    filter =filter and filter2 or filter1
    orgDevMap = orgDevMap or {}
    selector = selector or function() return true end
    local  pb = printBuffer("\n")
    pb:add("\nlocal HueDeviceTable = {\n")
    local rs = {}
    for _,r in pairs(HUE:getResourceIds()) do
      if filter[r.type] then
        rs[#rs+1]={order=filter[r.type],str=tostring(r),r=r}
      end
    end
    local parentMap = {room={},zone={}}
    for _,r0 in ipairs(rs) do
      local r = r0.r
      if r.type=='room' or r.type=='zone' then
        for _,c in ipairs(r.children) do
          parentMap[r.type][c.rid]=r.name
        end
      end
    end
    table.sort(rs,function(a,b) return a.order < b.order or a.order==b.order and a.str < b.str end)
    for _,r0 in ipairs(rs) do
      local r = r0.r
      local room = parentMap.room[r.id]
      local zone = parentMap.zone[r.id]
      local ref = (orgDevMap[r.id] or {}).ref
      room=room and (",room='"..room.."'") or ""
      zone=zone and (",zone='"..zone.."'") or ""
      ref=ref and (",ref='"..ref.."'") or ""
      if r.type=='scene' then
        room = (",room='"..resolve(r.rsrc.group).name.."'")
      end
      pb:printf("%s['%s']={type='%s',name='%s',model='%s'%s%s%s},\n",selector(r.id) and "  " or "--",r.id,r.type,r.name,r.resourceType,room,zone,ref)
    end
    pb:add("}\n")
    print(pb:tostring())
  end
  
  function HUE:createDeviceTable(filter)
    filter =filter and filter2 or filter1
    local rs,rs2,res = HUE:getResourceIds(),{},{}
    
    local parentMap = {room={},zone={}}
    for uid,r in pairs(rs) do
      if filter[r.type] then
        rs2[uid]=r
        if r.type=='room' or r.type=='zone' then
          for _,c in ipairs(r.children) do
            parentMap[r.type][c.rid]=r.name
          end
        end
      end
    end
    for uid,r in pairs(rs2) do
      local m = {}
      res[uid]=m
      m.room = parentMap.room[r.id]
      m.zone = parentMap.zone[r.id]
      if r.type=='scene' then
        m.room = resolve(r.rsrc.group).name
      end
      m.type=r.type
      m.name=r.name
      m.model=r.resourceType
      m.props=strip(r:getProps())
      local btns=0
      if r.services then
        for _,s in ipairs(r.services) do
          btns = btns + (s.rtype=='button' and 1 or 0)
        end
      end
      m.buttons=btns
    end
    return res
  end
  
  local function sortResources(list,f)
    local rs = {}
    for _,r in pairs(list) do
      r = f and f(r) or r
      if filter2[r.type] then
        rs[#rs+1]={order=filter2[r.type],resource=r}
      end
    end
    table.sort(rs,function(a,b) return a.order < b.order or a.order==b.order and a.resource.id < b.resource.id end)
    local r0 = {}
    for _,r in ipairs(rs) do r0[#r0+1]=r.resource end
    return r0
  end
  
  local function printResource(r,pb,ind)
    pb:add(string.rep(' ',ind)..tostring(r).."\n")
    if r.owner then pb:add(string.rep(' ',ind+2).."Parent:"..r.owner.rid.."\n") end
    local rs = r.children and sortResources(r.children,function(r) return resolve(r) end) or {}
    if rs[1] then
      pb:add(string.rep(' ',ind+2).."Children:\n")
      for _,c in ipairs(rs) do
        printResource(c,pb,ind+4)
      end
    end
    rs = r.services and sortResources(r.services,function(r) return resolve(r) end) or {}
    if rs[1] then
      pb:add(string.rep(' ',ind+2).."Services:\n")
      for _,c in ipairs(rs) do
        printResource(c,pb,ind+4)
      end
    end
    if r.rsrc.actions then
      local w = resolve(r.rsrc.group)
      pb:add(string.rep(' ',ind+2).."Group:"..tostring(w).."\n")
      pb:add(string.rep(' ',ind+2).."Targets:\n")
      for _,a in ipairs(r.rsrc.actions or {}) do
        local f = resolve(a.target)
        pb:add(string.rep(' ',ind+4)..tostring(f).."\n")
      end
    end
  end
  
  function HUE:listAllDevicesGrouped(groups)
    local  pb = printBuffer("\n")
    pb:add("------------------------\n")
    local rs = sortResources(HUE:getResourceIds())
    for _,r in ipairs(rs) do if not r.owner then printResource(r,pb,0) end end
    pb:add("------------------------\n")
    print(pb:tostring():gsub("\n","</br>"):gsub("%s","&nbsp;"))
  end
  
  function _initEngine(ip,key,cb)
    ctx.app_key = key
    ctx.url = fmt("https://%s",ip)
    DEBUG('info',"HUEv2Engine v%s",_version_e)
    DEBUG('info',"Hub url: %s",ctx.url)
    callBack = function()
      fetchEvents()
      setInterval(function()
        DEBUG('info',"Health-check: refreshing Hue resources")
        HUE._resyncOnRefresh = true
        post({type='REFRESH_RESOURCES'})
      end, 30*60*1000)

      -- SSE watchdog: monitors SSE liveness and restarts QA if stream is dead.
      -- Controlled by quickAppVariables "watchdog" and "watchtime".
      --   watchdog = "time"  → reconnect SSE after quiet period
      --   watchdog = "poll"  → ping bridge resource, restart if no echo
      local function startSSEWatchdog()
        local wdMode = getVar("watchdog", "time")
        local wdTime = tonumber(getVar("watchtime", ""))
        if not wdTime or wdTime <= 0 then
          wdTime = (wdMode == "poll") and 60 or 1800
        end
        local wdMs = wdTime * 1000
        DEBUG('info',"SSE watchdog: mode=%s interval=%ds", wdMode, wdTime)

        local g_pingTarget = nil

        local function doPollPing()
          doSSEPing(g_pingTarget, 10, function(ok, info)
            if not ok then
              ERROR("SSE watchdog: ping FAILED (%s). SSE stream appears dead. Restarting QA.", tostring(info))
              setTimeout(function() plugin.restart() end, 1000)
            else
              DEBUG('info',"SSE watchdog: ping OK (rtt ~%ss)", tostring(info))
              tick()
            end
          end)
        end

        local function tick()
          setTimeout(function()
            local quiet = os.time() - (HUE._lastSseSeen or 0)
            if quiet < wdTime then
              tick() ; return
            end
            if bridgeWaitMs() > 0 then
              tick() ; return
            end
            if wdMode == "poll" then
              if not g_pingTarget then
                findPingTarget(function(t)
                  if not t then
                    ERROR("SSE watchdog: poll mode needs a ping target, none found. Falling back to time mode.")
                    wdMode = "time"
                    tick() ; return
                  end
                  g_pingTarget = t
                  doPollPing()
                end)
              else
                doPollPing()
              end
            else
              -- "time" mode: SSE has been quiet — stream is dead, restart QA
              ERROR("SSE watchdog: no event for %ds, SSE stream appears dead. Restarting QA.", wdTime)
              setTimeout(function() plugin.restart() end, 1000)
            end
          end, wdMs)
        end
        tick()
      end

      startSSEWatchdog()
      if cb then cb() end
    end
    post({type='STARTUP'})
  end

  -- Write back to context
  ctx._initEngine = _initEngine
  ctx.refreshInFlight = refreshInFlight
  ctx.refreshBlockedUntil = refreshBlockedUntil
  ctx.callBack = callBack
  ctx.resources = resources
end