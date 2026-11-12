---
name: quickapp-patterns
description: Common QuickApp implementation patterns: timer polling loops, cancellable timers, retry on failure, async HTTP requests (net.HTTPClient), refreshStates event polling (listening for HC3 device changes), RefreshStateSubscriber class, child device patterns, global variable access, state persistence (QA variables, internalStorage), UI update patterns, calling other devices, time-based schedulers, sending notifications. USE FOR: implementing recurring tasks, reacting to HC3 events, making HTTP calls, managing child devices, keeping state across restarts.
---

# QuickApp Common Patterns

Practical patterns for timers, event polling, HTTP, networking, child devices, and common QuickApp tasks.

---

## Startup Patterns

### Disabled check (the `enabled` flag)

Unchecking a device in the HC3 web UI does NOT stop its QA — the HC3
starts the QA anyway, and the QA must check the flag itself. Do it first
in `onInit` and bail before any timers or work are set up:

```lua
function QuickApp:onInit()
    self:debug(self.name, self.id)
    if not api.get("/devices/" .. self.id).enabled then
        self:debug(self.name, self.id, "Device is disabled")
        return  -- no timers, no work: the QA stays idle
    end
    -- ...start timers and init here...
end
```

Re-enabling in the UI restarts the QA (an `enabled` change restarts it,
like every other device PUT — see hc3-write-safety), so `onInit` runs
again and the check passes. flua behaves the same: the sim starts a
disabled QA and `PUT /devices/{id} {enabled = false}` restarts it, so the
pattern is testable offline exactly as it runs on the HC3.

## Device Lookup — filter on the server

Fetching `/devices` and iterating client-side to find a device by name is a
common (and wasteful) pattern — on a big HC3 that pulls hundreds of devices
into the QA. The REST API filters server-side; use them:

```lua
local qa = api.get("/devices?name=My Helper")[1]          -- by name (case-insensitive exact)
local qas = api.get("/devices?interface=quickApp")         -- all QuickApps
local switches = api.get("/devices?type=com.fibaro.binarySwitch")
local byUuid = api.get("/devices?property=[quickAppUuid," .. HELPER_UUID .. "]")
local roomLights = api.get("/devices?roomID=1&type=com.fibaro.binarySwitch")
```

- `?name=` — case-insensitive **exact** match (verified against a live HC3;
  no substring). **Quirk**: names containing `&` can NOT be matched on the
  HC3 at all (encoded or raw — both return 0; the controller re-splits on
  the decoded `&`). Workaround: narrow server-side by `type`/`interface`/
  `roomID`, then match the name client-side. flua's sim matches the encoded
  `&` form correctly (and logs a warning) — a deliberate difference.
- `?property=[name,value]` — the property value is **stringified** and
  compared to the filter value as a string (Lua-style: booleans are
  `true`/`false`).
- Filters combine (`&`), return a **list** (empty, not nil, when nothing
  matches) — index `[1]` and nil-check before use.
- Names with spaces need no encoding (verified on a live HC3: raw
  `?name=Wake on LAN` works). `urlencode(name)` is still worth it for names
  containing reserved query characters (`&`, `=`, `%`, `#`) — those would
  corrupt the query unencoded.
- flua's sim implements the same filter semantics, so the pattern is
  testable offline. More endpoints and shapes: the hc3-rest-api skill,
  `assets/devices.md`.

### Resolving names and rooms to device ids

When the user asks for "the light in the bedroom", resolve it — don't
guess:

1. Dev time: `flua --tool house` (or the MCP `flua_tool` with name
   `house`) returns every device as `{id, name, type, room}` — match the
   user's words case-insensitively against name/room/type. If **several
   devices match, list them and ask which one** — never pick silently.
2. In the QA code: prefer a runtime lookup over a baked id — the
   server-side filters above. Ids change when devices are re-included;
   the homeTable pattern next is the stable-names idiom.

## The homeTable — names in code, ids behind them

Devices change ids when they are removed and re-included on the HC3;
every QA that hardcodes a numeric id stops working silently. The idiom is
a **home table**: stable names as keys, ids as values, nested by room —
`HT.kitchen.light` — kept in ONE place instead of scattered literals.

```lua
-- stored JSON-encoded in a fibaro global variable (must exist first; the
-- value is a string — global variables always are):
local encoded = fibaro.getGlobalVariable("homeTable")
if not encoded or encoded == "" then
    -- build once: hand-made, or scanned from the live house
    local HT = {}
    for _, d in ipairs(api.get("/devices")) do
        if d.name == "Bedroom lamp" then
            HT.bedroom = HT.bedroom or {}
            HT.bedroom.lamp = d.id
        end
    end
    api.post("/globalVariables", { name = "homeTable", value = json.encode(HT) })
    encoded = json.encode(HT)
end
local HT = json.decode(encoded)

-- the code reads by name; when a device changes id, fix ONE place:
fibaro.call(HT.bedroom.lamp, "turnOn")
```

- Hand-made tables are the common case; auto-generation scans `/devices`
  and matches on stable fields (name, type, room).
- flua's extension generates the same table as code ("Flua: Generate home
  table (ht.lua)" — a LuaLS-annotated `HT` table, rooms → names → ids),
  and the sim seeds global variables via `--seed`/`--%%db`, so the pattern
  is testable offline.
- **Scenes cannot use variables in their trigger conditions** — scene
  declarations must carry literal ids. The homeTable protects QA code,
  not scene triggers; when a scene drives a QA it hardcodes the QA's id
  and the QA resolves its own devices by name.

## Timer Patterns

### Polling loop (setInterval)
```lua
function QuickApp:onInit()
    self.pollInterval = (tonumber(self:getVariable("interval")) or 30) * 1000
    setInterval(function() self:poll() end, self.pollInterval)
    self:poll()  -- also run immediately on start
end

function QuickApp:poll()
    -- your polling logic
    self:updateProperty("value", getReading())
end
```

### Fixed-rate loop (no drift) — prefer this for scheduled work

`setInterval` chains from *completion*: each cycle takes `interval + work
time`, so a daily task drifts a few seconds every day and minutes over
weeks. For anything that must stay on a schedule (00:00:00 runs, hourly
syncs), target ABSOLUTE times and let each delay absorb the work time:

```lua
-- fires every `seconds`, on the original cadence — the work time is
-- compensated, never accumulated
function QuickApp:loopEvery(seconds, fun)
    local next = os.time() + seconds
    local function tick()
        fun()
        next = next + seconds
        setTimeout(tick, math.max(0, (next - os.time()) * 1000))
    end
    setTimeout(tick, math.max(0, (next - os.time()) * 1000))
end

function QuickApp:onInit()
    self:loopEvery(60, function() self:checkTime() end)
end
```

Live example: `examples/drift.lua` shows `setInterval` drifting next to
this pattern. `os.time()` is whole seconds, so the delay math is
second-quantized — the cadence is exact on the second, and the leftover
fraction is re-absorbed every cycle.

### One-shot delayed action
```lua
setTimeout(function()
    self:doSomething()
end, 5000)
```

### Cancellable timer
```lua
function QuickApp:onInit()
    self.timer = nil
    self:startTimer()
end

function QuickApp:startTimer()
    if self.timer then clearTimeout(self.timer) end
    self.timer = setTimeout(function()
        self:doWork()
        self.timer = nil
    end, 10000)
end
```

### Retry after failure
```lua
function QuickApp:fetchWithRetry(attempt)
    attempt = attempt or 1
    if attempt > 3 then
        self:error("Failed after 3 attempts")
        return
    end
    local ok, data = pcall(function() return self:doFetch() end)
    if not ok then
        self:warning("Attempt", attempt, "failed, retrying in 5s")
        setTimeout(function() self:fetchWithRetry(attempt + 1) end, 5000)
    end
end
```

---

## HTTP Requests

### GET request
```lua
function QuickApp:fetchData()
    local http = net.HTTPClient()
    http:request("https://api.example.com/status", {
        options = { method = "GET" },
        success = function(response)
            if response.status == 200 then
                local data = json.decode(response.data)
                self:updateProperty("value", data.value)
            else
                self:warning("HTTP", response.status)
            end
        end,
        error = function(err)
            self:error("HTTP error:", tostring(err))
        end
    })
end
```

### POST request with JSON body
```lua
function QuickApp:sendCommand(cmd, payload)
    local http = net.HTTPClient()
    http:request("https://api.example.com/command", {
        options = {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. self:getVariable("token")
            },
            data = json.encode({ command = cmd, data = payload })
        },
        success = function(response)
            self:debug("Response:", response.status)
        end,
        error = function(err)
            self:error("POST failed:", tostring(err))
        end
    })
end
```

### Local HC3 REST API calls (synchronous via api.*)
```lua
-- These are synchronous and safe to use in onInit or timer callbacks
local device = api.get("/devices/" .. self.id)
local vars = api.get("/globalVariables")
local result = api.post("/customEvents/myEvent", {})
api.put("/devices/" .. self.id, { name = "New Name" })
```

### Installing another .fqa from a QA (QA-installs-QA)

A QA can install another QuickApp package on the controller through
`POST /quickApp`. The simplest form — a package carrying
`initialProperties.apiVersion` (flua-packed .fqas do) — is a plain
synchronous `api.post`:

```lua
function QuickApp:installFqa(fqa, cb)
    -- fqa: the PACKAGE table; must carry initialProperties.apiVersion
    -- ("1.3") — the JSON create preserves such packages verbatim, custom
    -- uiCallbacks included. Without the marker the controller re-derives
    -- uiCallbacks with generated ui<b2>OnReleased names (live-verified
    -- 5.221.22) — use the multipart recipe below for those.
    local dev, status = api.post("/quickApp/", json.encode(fqa))
    if status and status <= 201 then cb(dev and dev.id, status) else cb(nil, status) end
end
```

For packages WITHOUT the marker (arbitrary third-party .fqas), the web
UI's import endpoint is the preserving path — but it is **strictly
multipart**: a JSON body dies with HTTP 500 "Field name too long", so
hand-build the multipart body and send it with net.HTTPClient to the
loopback API (port 11111 — the HC3's own, credential-free; flua rewrites
it to the controller online and to the sim's `--ui` server offline, so
the same code runs in the emulator):

```lua
function QuickApp:installFqaMultipart(fqa, filename, cb)
    -- fqa must be the PACKAGE STRING (json.encode(table)), not the table
    local boundary = "----qaDist" .. string.format("%08x", os.time())
        .. string.format("%08x", math.random(0x7FFFFFFF))
    local body = "--" .. boundary .. "\r\n"
        .. 'Content-Disposition: form-data; name="file"; filename="' .. filename .. '"\r\n'
        .. "Content-Type: application/octet-stream\r\n"
        .. "\r\n"
        .. fqa .. "\r\n"
        .. "--" .. boundary .. "--\r\n"
    net.HTTPClient({ timeout = 30000 }):request(
        "http://127.0.0.1:11111/api/quickApp/import",
        {
            options = {
                method = "POST",
                headers = {
                    ["Accept"] = "application/json",
                    ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
                    ["X-Fibaro-Version"] = "2",
                },
                data = body,
            },
            success = function(response)
                -- 201 Created; response.data is the RAW JSON body string —
                -- json.decode it for the new device id
                local ok, device = pcall(json.decode, response.data or "")
                cb(ok and device and device.id or nil, response.status)
            end,
            error = function(err)
                cb(nil, nil, tostring(err))
            end,
        }
    )
end
```

The `file` part **must carry a filename** — a filename-less part crashes
the import handler with a bodyless HTTP 500 (live-verified 5.221.22).

---

## RefreshStates — Listening for HC3 Events

`refreshStates` is the HC3 long-polling mechanism to receive device property changes, custom events, and scene triggers in near-real-time.

### Pattern: polling refreshStates in a QuickApp

```lua
function QuickApp:onInit()
    self.lastRefresh = 0
    self:startRefreshPolling()
end

function QuickApp:startRefreshPolling()
    local function poll()
        local url = "/refreshStates?last=" .. self.lastRefresh
        local http = net.HTTPClient()
        http:request("http://localhost:11112" .. url, {
            options = { method = "GET", timeout = 5000 },
            success = function(response)
                if response.status == 200 then
                    local data = json.decode(response.data)
                    self.lastRefresh = data.last or self.lastRefresh
                    self:processEvents(data.changes or {})
                end
                setTimeout(function() poll() end, 0)
            end,
            error = function(err)
                self:warning("refreshStates error, retrying in 3s")
                setTimeout(function() poll() end, 3000)
            end
        })
    end
    poll()
end

function QuickApp:processEvents(changes)
    for _, change in ipairs(changes) do
        self:debug("Device", change.id, "property", change.name, "=", tostring(change.newValue))
        if change.id == 42 and change.name == "value" then
            self:onDeviceTriggered(change.newValue)
        end
    end
end
```

### Using the built-in RefreshStateSubscriber class

> **Prefer this over polling.** `RefreshStateSubscriber` listens to the HC3 event stream, so it reacts immediately when a device changes state — no waiting for the next poll interval. It is also more efficient because no repeated HTTP requests are made to fetch device state.

`subscribe(filter, handler)` — `filter(event)` is called first; if it returns `true`, `handler(event)` is called. A common pattern is to pass a filter that always returns `true` and do all filtering inside the handler.

```lua
function QuickApp:onInit()
    self.rss = RefreshStateSubscriber()

    -- filter always returns true; handler does the filtering
    self.rss:subscribe(
        function(event) return true end,
        function(event)
            if event.type == "DevicePropertyUpdatedEvent" then
                local id = event.data.id
                local prop = event.data.property
                local val = event.data.newValue
                self:debug("Device", id, prop, "->", tostring(val))
            end
        end
    )

    self.rss:run()
end

function QuickApp:onDestroy()
    if self.rss then self.rss:stop() end
end
```

### Narrowing with a real filter
```lua
-- Only invoke handler for a specific device's value changes
self.rss:subscribe(
    function(event)
        return event.type == "DevicePropertyUpdatedEvent"
            and event.data.id == watchedId
            and event.data.property == "value"
    end,
    function(event)
        self:applyValue(event.data.newValue)
    end
)
```

### Listening for CustomEvents
```lua
self.rss:subscribe(
    function(event) return true end,
    function(event)
        if event.type == "CustomEvent" and event.data.name == "myEvent" then
            self:debug("Custom event received!")
        end
    end
)
```

---

## Mocking a service with a dynamically loaded QA

The recipe for a client QA + a mock-service QA hosted with
`net.HTTPServer`, loaded at runtime (the Skoda pair is the worked
example — `examples/Skoda/`). The contracts, learned the hard way:

- **The mock binds a FIXED, deliberately unlikely port** (overridable via
  a variable). Port discovery between two QAs is the hard part — a
  published fixed port removes it. If the bind fails, warn and exit:
  another mock (or service) may already serve the port, and the mock
  must not pretend.
- **`server.port` is available immediately after `listen(port, handler)`**
  — no waiting, no callback.
- **The client loads the mock only when no url is configured AND `_FLUA`
  is present** — the whole block sits inside `if _FLUA then ... end`, so
  the same file runs on a real HC3 (where `_FLUA` is nil and the real
  url is configured instead):

```lua
local MOCK_PORT = 18290

function QuickApp:onInit()
  self.url = first(self:getVariable("url"), nil)
  if not self.url and _FLUA then
    self.url = "http://127.0.0.1:" .. MOCK_PORT
    pcall(_FLUA.loadQAfromFile, _PY.examples_dir .. "/mock.lua", {})
  end
  ...
end
```

- **Resolving the mock's path**: bundled example files live under
  `_PY.examples_dir` (the installed `flua.examples` package — pip users
  included); files shipped next to the QA resolve through
  `_FLUA.mainPath` (the QA's source dir, trailing slash included).
  Never `--%%file` the mock into the client — it would ship inside the
  `.fqa` package.
- **Readiness**: the loaded QA boots eagerly, but treat the mock as ready
  after the first successful request, not immediately after the load
  returns — a nil instance right after `loadQAfromFile` is a real state,
  not a bug. A bounded retry on the client's first request is the honest
  pattern.
- **Lifetime**: the mock keeps itself alive with `_FLUA.keepAlive()` and
  dies with its QA; the client polls with `setInterval`.
- **Mock-only defaults must not leak**: credentials defaulting to mock
  values apply ONLY on the mock path — a configured url is the real
  service, and missing credentials should warn, not silently call it
  with mock values.

## Child Device Patterns

> **Advanced / multi-child QAs**: prefer the **qwikchild** library
> (`--%%file:$qwikchild.lua,qwikchild`) — UID-based attach-or-create, a class
> per child, per-child UIs, and `internalStorage` state. The qwikchild skill
> has the full API; `examples/qwikchildtest.lua` is the self-tested fixture.
> The patterns below show the manual primitives it builds on.

### Defining a child class
```lua
class 'MyChild'(QuickAppChild)

function MyChild:__init(device)
    QuickAppChild.__init(self, device)
end

function MyChild:onInit()
    self:debug("Child", self.id, "started")
end

function MyChild:turnOn()
    self:updateProperty("value", true)
end

function MyChild:turnOff()
    self:updateProperty("value", false)
end
```

### Creating children from the parent
```lua
function QuickApp:onInit()
    self:initChildDevices({ ["com.fibaro.binarySwitch"] = MyChild })

    if #api.get("/devices?parentId=" .. self.id) == 0 then
        self:createChildDevice({
            name = "Channel 1",
            type = "com.fibaro.binarySwitch",
            initialProperties = { value = false }
        }, MyChild)
    end
end
```

### Calling parent from child
```lua
function MyChild:doSomething()
    -- self.parent is available after __init in child's onInit()
    self.parent:debug("Child reporting to parent")
    self.parent:updateProperty("log", "Child " .. self.id .. " active")
end
```

> **For more advanced child management** — UID-based addressing, declarative `initChildren`, per-child UI, and `internalStorage` per child — use the **QwikAppChild** library. Ask `/qwikchild` for full details.

---

## Variable Storage — When to Use What

| Storage | Visible in UI | Saved with QA | Shared across QAs | Use for |
|---|---|---|---|---|
| **Fibaro Global Variable** | No | No | Yes | System-wide values shared by multiple QAs or Scenes (e.g. `HomeMode`, `AlarmArmed`) |
| **QuickApp variable** (`self:getVariable`) | Yes | Yes | No | User-configurable parameters (API keys, IP addresses, poll intervals) — shown in the QA panel and exported with the QA `.fqa` file |
| **internalStorage** | No | No | No | Private runtime state that must survive QA restarts but should not be visible or user-editable (e.g. last-seen timestamps, cached values, counters) |

> **Fibaro Global Variables** are the right choice when a value needs to be read or written by more than one QuickApp or Scene. Note. They need to be created before they can be set, otherwise attempts to read or write them will fail. api.post("/globalVariables", { name = "HomeMode", value = "Away" }) can be used to create them programmatically.

> **Config fallbacks — the empty-string trap.** `self:getVariable(name)`
> returns `""` (not nil) when the variable is unset, and `""` is
> **truthy** in Lua — so `getVariable("url") or default` silently yields
> the empty string, and the QA then calls the API with a broken url.
> Check explicitly:
>
> ```lua
> local function first(v, fallback)
>     if v == nil or v == "" then return fallback end
>     return v
> end
> local url = first(self:getVariable("url"), "http://default")
> -- numbers are safe through tonumber: tonumber("") is nil
> local port = tonumber(self:getVariable("port")) or 8190
> ```

> **QuickApp variables** are the right choice for settings the user may want to change — they appear in the HC3 UI under the device panel and are bundled into the QA when it is downloaded as a `.fqa` file.

> **internalStorage** stores arbitrary Lua values (tables, strings, numbers, booleans — anything JSON-encodable). You do **not** need to call `json.encode`/`json.decode` yourself; the API handles serialisation transparently. Functions cannot be stored.

---

## Global Variable Patterns

```lua
local mode = fibaro.getGlobalVariable("HomeMode")
fibaro.setGlobalVariable("HomeMode", "Away")

-- Alternative via api.*
local gv = api.get("/globalVariables/HomeMode")
print(gv.value)
api.put("/globalVariables/HomeMode", { value = "Home" })
```

---

## State Persistence

### Using QuickApp variables (user-visible, saved with QA)
```lua
function QuickApp:onInit()
    -- Read user-configured parameter set in the HC3 UI
    local interval = tonumber(self:getVariable("pollInterval")) or 30
    self.pollInterval = interval * 1000
end
```

### Saving runtime state across restarts with QuickApp variables
```lua
function QuickApp:setState(val)
    self.state = val
    self:setVariable("savedState", tostring(val))
    self:updateProperty("value", val)
end

function QuickApp:onInit()
    local saved = self:getVariable("savedState")
    self.state = saved == "true"
end
```

### Using internalStorage (private, not user-visible)
```lua
-- Store any JSON-encodable Lua value — no manual json.encode needed
self:internalStorageSet("lastSeen", os.time())
self:internalStorageSet("cache", { temp = 21.5, hum = 55 })

local ts    = self:internalStorageGet("lastSeen")   -- nil if not set
local cache = self:internalStorageGet("cache")       -- returns Lua table directly
self:internalStorageRemove("lastSeen")
self:internalStorageClear()
```

---

## Error Handling

```lua
local ok, result = pcall(function()
    return json.decode(rawData)
end)
if not ok then
    self:error("JSON parse failed:", result)
    return
end

local function safeGet(path)
    local resp = api.get(path)
    if not resp then
        return nil, "API call failed: " .. path
    end
    return resp, nil
end
```

---

## UI Update Patterns

```lua
self:updateView("statusLabel", "text", "Connected")
self:updateView("tempSlider", "value", tostring(math.floor(temp)))
self:updateView("toggleBtn", "text", self.active and "Deactivate" or "Activate")
self:updateView("advancedPanel", "visible", "false")
self:updateView("modeSelect", "value", tostring(selectedMode))
```

---

## Calling Other Devices

```lua
fibaro.call(42, "turnOn")
fibaro.call(42, "setValue", 75)
local val = fibaro.getValue(42, "value")
self:turnOn()  -- prefer self:method() over fibaro.call(self.id, ...) for self
```

### Interface changes restart the QA — guard with hasInterface

`addInterfaces`/`deleteInterfaces` restart the plugin **unconditionally**
— even when the interface is already present (or absent), so a QA that
adds its own interfaces in `onInit` loops forever. Gate every change:

```lua
function QuickApp:onInit()
    if not self:hasInterface("autoTurnOff") then
        self:addInterfaces({"autoTurnOff"})
    end
end
```

Only add what is missing (and check before removing); a re-boot after a
real change is a one-time event, not a loop. The same holds in flua's
sim.

---

## Scheduler / Time-Based Actions

The naive version — `setInterval` every minute checking the clock — drifts
by the check's execution time each cycle and can also miss the exact minute
if the check runs just before it. Use the fixed-rate pattern (above) and
fire at the exact target instead:

```lua
-- Run exactly at every local midnight — recompute the next midnight from
-- the date each cycle so DST shifts are handled, never +86400 blindly.
function QuickApp:scheduleMidnight(fun)
    local function nextMidnightAfter(now)
        local t = os.date("*t", now)
        t.hour, t.min, t.sec = 0, 0, 0
        local midnight = os.time(t)
        if midnight <= now then
            -- os.time normalizes day overflow (day 32 -> next month)
            midnight = os.time{year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0}
        end
        return midnight
    end
    local function tick()
        fun()
        local now = os.time()
        setTimeout(tick, math.max(0, (nextMidnightAfter(now) - now) * 1000))
    end
    setTimeout(tick, math.max(0, (nextMidnightAfter(os.time()) - os.time()) * 1000))
end

function QuickApp:onInit()
    self:scheduleMidnight(function()
        fibaro.call(10, "turnOff")  -- lights out at 00:00:00
    end)
end
```

### Sunrise / sunset

Device 1 **is the HC3** — ask it for the sun: `fibaro.getValue(1,
"sunsetHour")` returns `"HH:MM"` (sunrise likewise). flua's sim computes
the same fields from the configured location and the virtual clock, so
`--start`/`--%%time:` tests the sunset moment deterministically.

```lua
function QuickApp:nextSunset()
    local h, m = fibaro.getValue(1, "sunsetHour"):match("(%d+):(%d+)")
    local now = os.date("*t")
    local t = os.time{year = now.year, month = now.month, day = now.day,
                       hour = tonumber(h), min = tonumber(m), sec = 0}
    if t <= os.time() then
        t = os.time{year = now.year, month = now.month, day = now.day + 1,
                    hour = tonumber(h), min = tonumber(m), sec = 0}
    end
    return t
end

function QuickApp:onInit()
    local function arm()
        setTimeout(function()
            fibaro.call(HT.bedroom.lamp, "turnOn")  -- the homeTable again
            arm()                                   -- re-arm for tomorrow
        end, math.max(0, (self:nextSunset() - os.time()) * 1000))
    end
    arm()
end
```

For a pure "at sunset, do X" automation, the HC3-native answer is a
**scene** with a sunset trigger (see the hc3-lua-scenes skill) — no code,
no drift. A QA timer is for when the QA must do real work around the sun
(recompute, notify, act on several devices).

---

## Sending Notifications

```lua
fibaro.alert("push", {1}, "Motion detected!")
fibaro.alert("email", {1}, "Temperature too high: " .. temp .. "°C")
fibaro.emitCustomEvent("MotionAlert")
```
