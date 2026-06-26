--%%name:HueRateLimitProbe
--%%type:com.fibaro.binarySwitch
-- testhue.lua — Hue Bridge rate-limit probe
-- ============================================================================
-- Diagnoses the Hue bridge's actual rate-limit characteristics by
-- sending controlled bursts of GET requests to a known light resource.
--
-- Usage:  plua test/testhue.lua
--
-- Auto-discovers a light on the bridge; no manual ID needed.
-- Expected runtime: ~2-5 minutes depending on cooldown behaviour.
--
-- Tests (run sequentially):
--   1. DISCOVER  — list lights, pick one for subsequent tests
--   2. PING      — single request, baseline latency
--   3. BURST     — N unpaced requests; find 429 threshold
--   4. RATE      — paced send at 5/10/15/20/30/50 req/s; find sustainable max
--   5. COOLDOWN  — trigger 429, probe at intervals; short-circuits at first 200
--   6. SSE       — re-run 50 req/s while SSE eventstream is open; compare 429%
--   7. REFRESH   — GET /clip/v2/resource (all resources); time it, check for 429
--   8. PUT       — toggle light on/off in burst; find PUT rate limit (restores state)
--   9. SUMMARY   — observed Retry-After headers
-- ============================================================================

-- ============================================================================
-- CONFIGURATION — edit these before running
-- ============================================================================
local BRIDGE_IP = "192.168.50.56"        -- your bridge IP
local APP_KEY  = "AqlHjZVly4IRgcDmzr5YfJhDWs-lig0zitdckmn9"  -- your app key

-- ============================================================================
-- TEST PARAMETERS
-- ============================================================================
local BURST_COUNT        = 40     -- requests to fire in burst test
local RATE_SECONDS       = 5      -- seconds to sustain each rate level
local RATE_LEVELS        = { 5, 10, 15, 20, 30, 50 }   -- req/s
local COOLDOWN_WAITS     = { 1, 2, 3, 5, 10, 15, 30, 60 }  -- probe after N sec
local MAX_CONSECUTIVE_429 = 10   -- abort rate level after this many

-- Optional tests (set to false to skip)
local WITH_SSE        = true   -- Test 6: test while SSE eventstream is open
local DO_FULL_REFRESH = true   -- Test 7: test GET /clip/v2/resource overhead
local WITH_PUTS       = true   -- Test 8: toggle light on/off (restores state)

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================
local BASE_URL     = "https://" .. BRIDGE_IP
local g_lightUrl   = nil       -- set after discovery
local g_seq        = 0
local retryAfterSamples = {}
local g_pending    = 0

-- ============================================================================
-- HELPERS
-- ============================================================================
local function log(fmt_, ...)
    print(string.format("[%s] " .. fmt_, os.date("%H:%M:%S"), ...))
end

local function hrTime()
    local ok, res = pcall(os.clock)
    if ok and type(res) == "number" then return res end
    return os.time()
end

local function schedule(ms, fn)
    g_pending = g_pending + 1
    setTimeout(function()
        g_pending = g_pending - 1
        fn()
    end, ms)
end

-- ============================================================================
-- HTTP helpers (url is passed explicitly so we can use different endpoints)
-- ============================================================================
local function httpGet(url, cb)
    local t0 = hrTime()
    g_seq = g_seq + 1
    local seq = g_seq
    net.HTTPClient():request(url, {
        options = {
            method = "GET",
            checkCertificate = false,
            headers = { ["hue-application-key"] = APP_KEY },
        },
        success = function(resp)
            local elapsed = hrTime() - t0
            local body = nil
            if type(resp) == "table" and resp.data then
                local ok, decoded = pcall(json.decode, resp.data)
                if ok then body = decoded end
            end
            local ra = nil
            if type(resp) == "table" and type(resp.headers) == "table" then
                ra = resp.headers["Retry-After"] or resp.headers["retry-after"] or resp.headers["RETRY-AFTER"]
                ra = tonumber(ra)
            end
            if ra and ra > 0 then
                retryAfterSamples[#retryAfterSamples + 1] = ra
            end
            cb({
                seq      = seq,
                status   = type(resp) == "table" and resp.status or 0,
                elapsed  = elapsed,
                retryAfter = ra,
                body     = body,
                ok       = type(resp) == "table" and resp.status and resp.status < 300,
                limited  = type(resp) == "table" and resp.status == 429,
            })
        end,
        error = function(err)
            local elapsed = hrTime() - t0
            local limited = false
            local status = 0
            local errStr = tostring(err or "")
            local scode = errStr:match("HTTP (%d+)")
            if scode then
                status = tonumber(scode)
                limited = (status == 429)
            end
            cb({
                seq      = seq,
                status   = status,
                elapsed  = elapsed,
                ok       = false,
                limited  = limited,
                error    = errStr:sub(1, 80),
            })
        end,
    })
end

-- Convenience: probe the selected light
local function probe(cb)
    httpGet(g_lightUrl, cb)
end

-- PUT request — changes light state.  payload is a Lua table, JSON-encoded.
local function httpPut(url, payload, cb)
    local t0 = hrTime()
    g_seq = g_seq + 1
    local seq = g_seq
    net.HTTPClient():request(url, {
        options = {
            method = "PUT",
            checkCertificate = false,
            data = json.encode(payload),
            ["content-type"] = "application/json",
            headers = { ["hue-application-key"] = APP_KEY },
        },
        success = function(resp)
            local elapsed = hrTime() - t0
            local body = nil
            if type(resp) == "table" and resp.data then
                local ok, decoded = pcall(json.decode, resp.data)
                if ok then body = decoded end
            end
            local ra = nil
            if type(resp) == "table" and type(resp.headers) == "table" then
                ra = resp.headers["Retry-After"] or resp.headers["retry-after"] or resp.headers["RETRY-AFTER"]
                ra = tonumber(ra)
            end
            if ra and ra > 0 then
                retryAfterSamples[#retryAfterSamples + 1] = ra
            end
            cb({
                seq      = seq,
                status   = type(resp) == "table" and resp.status or 0,
                elapsed  = elapsed,
                retryAfter = ra,
                body     = body,
                ok       = type(resp) == "table" and resp.status and resp.status < 300,
                limited  = type(resp) == "table" and resp.status == 429,
            })
        end,
        error = function(err)
            local elapsed = hrTime() - t0
            local limited = false
            local status = 0
            local errStr = tostring(err or "")
            local scode = errStr:match("HTTP (%d+)")
            if scode then
                status = tonumber(scode)
                limited = (status == 429)
            end
            cb({
                seq      = seq,
                status   = status,
                elapsed  = elapsed,
                ok       = false,
                limited  = limited,
                error    = errStr:sub(1, 80),
            })
        end,
    })
end

-- Convenience: PUT to the selected light, toggling on/off each call
local g_putState = false
local function putProbe(cb)
    g_putState = not g_putState
    httpPut(g_lightUrl, { on = { on = g_putState } }, cb)
end

-- ============================================================================
-- TEST 0 — DISCOVER A LIGHT
-- ============================================================================
local TARGET_NAME = "Köksö1"   -- light name to search for (case-insensitive)

local function runDiscover(nextTest)
    log("=== TEST 0: DISCOVER LIGHT '%s' ===", TARGET_NAME)
    local listUrl = BASE_URL .. "/clip/v2/resource/light"
    httpGet(listUrl, function(r)
        if not r.ok or not r.body then
            log("  FAIL: cannot list lights (status=%s)", r.status or "?")
            log("  Check BRIDGE_IP and APP_KEY.")
            log("  Aborting.")
            return
        end
        local lights = r.body.data or {}
        if #lights == 0 then
            log("  No lights found on bridge. Aborting.")
            return
        end
        -- Search for the named light (case-insensitive)
        local chosen = nil
        local target = TARGET_NAME:lower()
        for _, l in ipairs(lights) do
            local name = l.metadata and l.metadata.name or ""
            if name:lower():find(target, 1, true) then
                chosen = l
                break
            end
        end
        if not chosen then
            chosen = lights[1]
            local fallback = chosen.metadata and chosen.metadata.name or "(unnamed)"
            log("  WARNING: '%s' not found — using first light: %s", TARGET_NAME, fallback)
        end
        local lid = chosen.id
        local lname = chosen.metadata and chosen.metadata.name or "(unnamed)"
        log("  Using: %s  (%s)", lname, lid)
        g_lightUrl = BASE_URL .. "/clip/v2/resource/light/" .. lid
        log("  URL: %s", g_lightUrl)
        log("")
        schedule(500, nextTest)
    end)
end

-- ============================================================================
-- TEST 1 — PING
-- ============================================================================
local function runPing(nextTest)
    log("=== TEST 1: PING ===")
    probe(function(r)
        if r.ok then
            log("  OK  status=%d  latency=%.3fs", r.status, r.elapsed)
        elseif r.status > 0 then
            log("  FAIL  status=%d  latency=%.3fs", r.status, r.elapsed)
        else
            log("  FAIL  error=%s", r.error or "unknown")
        end
        log("")
        schedule(500, nextTest)
    end)
end

-- ============================================================================
-- TEST 2 — BURST
-- ============================================================================
local function runBurst(nextTest)
    log("=== TEST 2: BURST  (%d requests, unpaced) ===", BURST_COUNT)
    local okCount, limitCount, errCount = 0, 0, 0
    local first429at = nil
    local minLat, maxLat, sumLat = math.huge, 0, 0
    local done = 0
    local tStart = hrTime()

    for i = 1, BURST_COUNT do
        probe(function(r)
            done = done + 1
            if r.ok then
                okCount = okCount + 1
            elseif r.limited then
                limitCount = limitCount + 1
                if not first429at then first429at = done end
            else
                errCount = errCount + 1
            end
            if r.elapsed then
                minLat = math.min(minLat, r.elapsed)
                maxLat = math.max(maxLat, r.elapsed)
                sumLat = sumLat + r.elapsed
            end
            if done == BURST_COUNT then
                local wall = hrTime() - tStart
                log("  Completed: %d ok / %d limited / %d errors  (wall %.1fs)",
                    okCount, limitCount, errCount, wall)
                if limitCount > 0 then
                    log("  First 429 at request #%d", first429at)
                end
                if okCount > 0 then
                    log("  Latency: min=%.3fs  max=%.3fs  avg=%.3fs",
                        minLat, maxLat, sumLat / okCount)
                end
                local effRate = wall > 0 and (done / wall) or 0
                log("  Effective rate: %.1f req/s", effRate)
                log("")
                schedule(1000, nextTest)
            end
        end)
    end
end

-- ============================================================================
-- TEST 3 — PACED RATE
-- ============================================================================
local function runRateTest(nextTest)
    log("=== TEST 3: PACED RATE ===")
    local rateIdx = 1

    local function runOneLevel()
        if rateIdx > #RATE_LEVELS then
            log("")
            schedule(500, nextTest)
            return
        end
        local rate = RATE_LEVELS[rateIdx]
        local totalRequests = rate * RATE_SECONDS
        local intervalMs = math.floor(1000 / rate)
        log("--- Rate: %d req/s  (%d requests over %ds, interval=%dms) ---",
            rate, totalRequests, RATE_SECONDS, intervalMs)

        local sent, done = 0, 0
        local okCount, limitCount, errCount = 0, 0, 0
        local consecutive429 = 0
        local aborted = false
        local reported = false
        local tStart = hrTime()

        local function tryReport()
            -- Report only when all planned requests have been dispatched
            -- AND all responses have arrived.
            if sent >= totalRequests and done >= sent and not reported then
                reported = true
                local wall = hrTime() - tStart
                local total = done
                local pct429 = total > 0 and (limitCount / total * 100) or 0
                log("  Result: %d/%d/%d (ok/429/err) — %.0f%% 429  (wall %.1fs, %.1f eff req/s)",
                    okCount, limitCount, errCount, pct429, wall,
                    wall > 0 and (total / wall) or 0)
                rateIdx = rateIdx + 1
                schedule(2000, runOneLevel)
            end
        end

        local function sendOne()
            if sent >= totalRequests then return end
            if aborted then
                -- Stop sending new requests.  Bump sent to totalRequests
                -- so tryReport can fire once in-flight responses drain.
                sent = totalRequests
                tryReport()
                return
            end
            sent = sent + 1
            probe(function(r)
                if r.ok then
                    okCount = okCount + 1
                    consecutive429 = 0
                elseif r.limited then
                    limitCount = limitCount + 1
                    consecutive429 = consecutive429 + 1
                else
                    errCount = errCount + 1
                end
                if consecutive429 >= MAX_CONSECUTIVE_429 and not aborted then
                    aborted = true
                    log("  ABORTED: %d consecutive 429s", consecutive429)
                end
                done = done + 1
                tryReport()
            end)
            if sent < totalRequests and not aborted then
                schedule(intervalMs, sendOne)
            end
        end

        sendOne()
    end

    schedule(500, runOneLevel)
end

-- ============================================================================
-- TEST 4 — COOLDOWN
-- ============================================================================
local function runCooldown(nextTest)
    log("=== TEST 4: COOLDOWN ===")
    log("  Triggering 429 with a fast burst (%d requests) ...", BURST_COUNT)

    local preDone = 0
    local got429 = false
    local reported = false

    for i = 1, BURST_COUNT do
        probe(function(r)
            preDone = preDone + 1
            if r.limited then got429 = true end
            if preDone == BURST_COUNT and not reported then
                reported = true
                if not got429 then
                    -- No 429 triggered — bridge wasn't throttled. One quick
                    -- probe confirms it's healthy, then skip the interval walk.
                    log("  No 429 triggered — bridge is healthy.")
                    probe(function(r2)
                        local tag = r2.ok and "OK" or ("ERR:" .. (r2.status or "?"))
                        log("  Probe: %s  (status=%s)", tag, r2.status or "?")
                        log("  Cooldown ≤ 0s (bridge never throttled).")
                        log("")
                        schedule(500, nextTest)
                    end)
                    return
                end
                -- 429 confirmed — probe at increasing intervals, stop at first 200.
                log("  429 confirmed. Probing recovery (short-circuits at first 200) ...")
                local ci = 1
                local function probeAtInterval()
                    if ci > #COOLDOWN_WAITS then
                        log("  Still throttled after %ds — bridge may need longer.",
                            COOLDOWN_WAITS[#COOLDOWN_WAITS])
                        log("")
                        schedule(500, nextTest)
                        return
                    end
                    local wait = COOLDOWN_WAITS[ci]
                    schedule(wait * 1000, function()
                        probe(function(r)
                            local tag
                            if r.ok then tag = "OK"
                            elseif r.limited then tag = "429"
                            else tag = "ERR:" .. (r.status or "?")
                            end
                            log("  After %2ds: %s  (status=%s)", wait, tag, r.status or "?")
                            if r.ok then
                                log("  Cooldown ≤ %ds (first 200 at this interval).", wait)
                                log("")
                                schedule(500, nextTest)
                            else
                                ci = ci + 1
                                schedule(200, probeAtInterval)
                            end
                        end)
                    end)
                end
                schedule(500, probeAtInterval)
            end
        end)
    end
end

-- ============================================================================
-- TEST 5 — SSE OVERHEAD
-- ============================================================================
-- Opens a long-lived SSE connection, then re-runs the 50 req/s rate level
-- to see whether the open eventstream makes the bridge more 429-prone.

local function runSseOverhead(nextTest)
    if not WITH_SSE then
        log("=== TEST 5: SSE OVERHEAD (skipped — WITH_SSE=false) ===")
        log("")
        schedule(500, nextTest)
        return
    end
    log("=== TEST 5: SSE OVERHEAD ===")
    log("  Opening SSE connection to /eventstream/clip/v2 ...")

    local sseUrl = BASE_URL .. "/eventstream/clip/v2"
    local sseOpen = false
    local sseEvents = 0

    -- Open SSE (same pattern as hue-transport fetchEvents_hc3)
    net.HTTPClient():request(sseUrl, {
        options = {
            method = "GET",
            checkCertificate = false,
            headers = {
                ["hue-application-key"] = APP_KEY,
                ["Accept"] = "text/event-stream",
            },
            timeout = 60000,
        },
        success = function(resp)
            if not sseOpen then
                sseOpen = true
                log("  SSE connected (status=%s).", resp.status or "?")
            end
            sseEvents = sseEvents + 1
        end,
        error = function(err)
            local errStr = tostring(err or "")
            if not sseOpen then
                log("  SSE error (will keep waiting): %s", errStr:sub(1, 80))
            end
        end,
    })

    -- Wait up to 5 s for SSE to stabilise, then run a short rate burst
    schedule(5000, function()
        if not sseOpen then
            log("  SSE did not connect — skipping overhead test.")
            log("")
            schedule(500, nextTest)
            return
        end
        log("  SSE active (%d events received). Running 50 req/s burst ...", sseEvents)

        local rate = 50
        local totalRequests = rate * 3   -- 3 seconds at 50/s
        local intervalMs = math.floor(1000 / rate)
        local sent, done = 0, 0
        local okCount, limitCount, errCount = 0, 0, 0
        local reported = false
        local tStart = hrTime()

        local function tryReport()
            if sent >= totalRequests and done >= sent and not reported then
                reported = true
                local wall = hrTime() - tStart
                local total = done
                local pct429 = total > 0 and (limitCount / total * 100) or 0
                log("  SSE+50/s: %d/%d/%d (ok/429/err) — %.0f%% 429  (wall %.1fs, %.1f eff req/s, %d SSE events)",
                    okCount, limitCount, errCount, pct429, wall,
                    wall > 0 and (total / wall) or 0, sseEvents)
                log("  Compare with Test 3 50 req/s result to see SSE impact.")
                log("")
                schedule(500, nextTest)
            end
        end

        local function sendOne()
            if sent >= totalRequests then return end
            sent = sent + 1
            probe(function(r)
                done = done + 1
                if r.ok then okCount = okCount + 1
                elseif r.limited then limitCount = limitCount + 1
                else errCount = errCount + 1
                end
                tryReport()
            end)
            if sent < totalRequests then
                schedule(intervalMs, sendOne)
            end
        end

        sendOne()
    end)
end

-- ============================================================================
-- TEST 6 — FULL REFRESH
-- ============================================================================
-- Times a GET /clip/v2/resource (all resources) to measure heavy-request
-- latency and whether the full refresh itself triggers 429s.

local function runFullRefresh(nextTest)
    if not DO_FULL_REFRESH then
        log("=== TEST 6: FULL REFRESH (skipped) ===")
        log("")
        schedule(500, nextTest)
        return
    end
    log("=== TEST 6: FULL REFRESH ===")
    local refreshUrl = BASE_URL .. "/clip/v2/resource"
    local t0 = hrTime()

    httpGet(refreshUrl, function(r)
        local wall = hrTime() - t0
        if r.ok and r.body then
            local n = 0
            if type(r.body.data) == "table" then n = #r.body.data end
            log("  OK  status=%d  %d resources  latency=%.2fs", r.status, n, wall)
        elseif r.limited then
            log("  429! Full refresh was rate-limited (latency=%.2fs)", wall)
        else
            log("  FAIL  status=%s  latency=%.2fs", r.status or "?", wall)
        end
        log("")
        schedule(500, nextTest)
    end)
end

-- ============================================================================
-- TEST 7 — PUT RATE-LIMIT
-- ============================================================================
-- Toggles the light on/off as fast as possible to find the PUT rate limit.
-- Saves and restores the light state so the room isn't left blinking.

local function runPutTest(nextTest)
    if not WITH_PUTS then
        log("=== TEST 7: PUT RATE-LIMIT (skipped — WITH_PUTS=false) ===")
        log("")
        schedule(500, nextTest)
        return
    end
    log("=== TEST 7: PUT RATE-LIMIT (toggling light on/off) ===")

    -- Save current light state so we can restore it
    local savedOn = nil
    httpGet(g_lightUrl, function(r)
        if r.ok and r.body and r.body.data then
            local d = r.body.data[1] or r.body.data
            if d.on then savedOn = d.on.on end
        end
        local initial = savedOn
        log("  Light initial state: %s", savedOn and "on" or savedOn == false and "off" or "unknown")

        -- Step A: slow, visible toggle so you can see the light respond
        local newState = not (initial == true)
        log("  Visible demo: turning %s for 1.5s ...", newState and "on" or "off")
        httpPut(g_lightUrl, { on = { on = newState } }, function(r1)
            local tag1 = r1.ok and "OK" or ("ERR:" .. (r1.status or "?"))
            log("  Demo PUT: %s  (you should see the light change)", tag1)

            schedule(1500, function()
                log("  Turning back ...")
                httpPut(g_lightUrl, { on = { on = initial == true } }, function(r2)
                    local tag2 = r2.ok and "OK" or ("ERR:" .. (r2.status or "?"))
                    log("  Restore: %s", tag2)

                    schedule(500, function()
                        -- Step B: fast burst to find PUT rate limit
                        local PUT_BURST = 30
                        local putDone = 0
                        local putOk, putLimit, putErr = 0, 0, 0
                        local putFirst429 = nil
                        local putStart = hrTime()

                        log("  PUT burst (%d toggles, unpaced) ...", PUT_BURST)
                        for i = 1, PUT_BURST do
                            putProbe(function(r)
                                putDone = putDone + 1
                                if r.ok then putOk = putOk + 1
                                elseif r.limited then
                                    putLimit = putLimit + 1
                                    if not putFirst429 then putFirst429 = putDone end
                                else putErr = putErr + 1
                                end
                                if putDone == PUT_BURST then
                                    local wall = hrTime() - putStart
                                    log("  PUT burst: %d/%d/%d (ok/429/err) — wall %.1fs, %.0f eff PUT/s",
                                        putOk, putLimit, putErr, wall,
                                        wall > 0 and (putDone / wall) or 0)
                                    if putFirst429 then
                                        log("  First PUT 429 at request #%d", putFirst429)
                                    end

                                    -- Final restore
                                    log("  Restoring light to %s ...", initial and "on" or "off")
                                    httpPut(g_lightUrl, { on = { on = initial == true } }, function(rr)
                                        local tag = rr.ok and "OK" or ("ERR:" .. (rr.status or "?"))
                                        log("  Restore: %s", tag)
                                        log("")
                                        schedule(500, nextTest)
                                    end)
                                end
                            end)
                        end
                    end)
                end)
            end)
        end)
    end)
end

-- ============================================================================
-- TEST 8 — SUMMARY
-- ============================================================================
local function runSummary()
    log("=== SUMMARY ===")
    if #retryAfterSamples > 0 then
        local sum, mn, mx = 0, math.huge, 0
        for _, v in ipairs(retryAfterSamples) do
            sum = sum + v
            mn = math.min(mn, v)
            mx = math.max(mx, v)
        end
        log("Retry-After header samples: %d", #retryAfterSamples)
        log("  min=%ds  max=%ds  avg=%.1fs", mn, mx, sum / #retryAfterSamples)
    else
        log("No Retry-After headers captured.")
    end
    log("")
    log("Tune hue-transport.lua constants based on findings:")
    log("  COOLDOWN_BASE      — set to min observed cooldown (from Test 4)")
    log("  COOLDOWN_MAX       — cap on escalation")
    log("  ESCALATE_THRESHOLD — 429s before escalation")
    log("  Bucket refillMs    — 1000 / sustainable_rate")
    log("")
    log("Pending callbacks: %d (should be 0)", g_pending)
end

-- ============================================================================
-- MAIN
-- ============================================================================
log("========================================")
log("  Yahue Hue Bridge Rate-Limit Probe")
log("========================================")
log("Bridge:  %s", BRIDGE_IP)
log("")
log("WARNING: This sends many GET requests to your bridge.")
log("A short burst of 429s is expected and harmless.")
log("")

-- Global safety timeout
schedule(300000, function()
    log("SAFETY TIMEOUT after 5 min — aborting.")
end)

-- Chained test runner
schedule(500, function()
    runDiscover(function()
        -- Only proceed if we found a light
        if not g_lightUrl then
            log("No light available. Aborting.")
            return
        end
        runPing(function()
            runBurst(function()
                runRateTest(function()
                    runCooldown(function()
                        runSseOverhead(function()
                            runFullRefresh(function()
                                runPutTest(function()
                                    runSummary()
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
