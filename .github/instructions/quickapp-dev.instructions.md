---
applyTo: "**/*.lua"
---

# QuickApp Development — Quick Reference

You are helping develop Fibaro HC3 QuickApps run under **flua** (a Lua engine for QuickApps, emulating the HC3 locally and online).

## File headers (must be at top of file)
```lua
--%%name:My QuickApp          -- device display name
--%%type:com.fibaro.binarySwitch  -- Fibaro device type
--%%mode:offline              -- offline (default) | online | proxy
--%%var:myKey="myValue"       -- QuickApp variable (value is Lua: strings need quotes)
--%%var:count=10              -- numbers work without quotes
--%%u:{label="lbl",text="Status"}  -- UI element (one per row)
--%%u:{button="btn",text="Go",onReleased="handleBtn"}
--%%u:{slider="s1",text="",min="0",max="100",value="50",onChanged="handleSlider"}
--%%debug:refreshState=true,api=true,http=true  -- debug logging categories
--%%loglength:120             -- debug line length cap
```

## QuickApp skeleton
```lua
function QuickApp:onInit()
    self:debug(self.name, self.id)
    -- init timers, load variables, set initial state
end

-- UI callbacks receive an event table
function QuickApp:handleBtn(event)     end   -- button
function QuickApp:handleSlider(event)  end   -- slider: tonumber(event.values[1])
function QuickApp:handleSwitch(event)  end   -- switch: event.values[1] == true/false
```

## Core API quick-ref
```lua
-- State
self:updateProperty("value", true)           -- persist property + emit event
self:updateView("elemId", "text", "hello")   -- update UI (values must be STRINGS)
self:getVariable("key")   -- returns "" if missing (not nil)
self:setVariable("key", "val")

-- Fibaro globals
fibaro.call(id, "action", ...)
fibaro.getValue(id, "value")
fibaro.getGlobalVariable("name") / fibaro.setGlobalVariable("name", "val")
fibaro.emitCustomEvent("name")

-- REST
api.get("/devices/42")
api.post("/customEvents/evt", {})
api.put("/globalVariables/mode", {value="Away"})

-- Timers (never use fibaro.sleep — it blocks everything)
local ref = setTimeout(function() ... end, ms)
clearTimeout(ref)
local ref2 = setInterval(function() ... end, ms)
clearInterval(ref2)

-- JSON
json.encode(table)  /  json.decode(string)
```

## Key rules
- `self:getVariable()` returns `""` not `nil` when missing
- `self:updateView()` values must be strings — use `tostring(n)`
- Use `self:method()` to call self (not `fibaro.call(self.id, ...)`)
- Private helpers should be `local function`s **outside** the `QuickApp:` methods
- Use `pcall` to guard JSON parsing and HTTP responses

## Verify (virtual time)
Run the QA to verify a change; timer logic must not wait for real time:
```bash
flua --api local --instant qa.lua                 # timers fire immediately
flua --api local --start '2027/10/6 12:00:00' qa.lua   # pin the virtual date
flua --api local --speed 60 qa.lua                # 60x virtual speed
flua --api local --log json qa.lua                # machine-readable logs
```
Use the built-in assertions instead of hand-rolled expect():
`local Test = require("flua-test"); local t = Test.new()` — `t:expect`,
`t:assert_eq` (deep), `t:assert_json`, `t:finish()` (summary + exit code).
UI from Lua: `_FLUA.uiEvent(element, eventType[, value])` injects a UI
event, `self:getView()` reads the rendered view, `flua --tool ui qa.lua`
prints the UI as text. Use `exit(failures > 0 and 1 or 0)` (or
`t:finish()`) so the exit code is the verdict (see `/quickapp-test`).

## Common device types
`com.fibaro.binarySwitch` · `com.fibaro.multilevelSwitch` · `com.fibaro.binarySensor`
`com.fibaro.temperatureSensor` · `com.fibaro.humiditySensor` · `com.fibaro.motionSensor`
`com.fibaro.doorSensor` · `com.fibaro.deviceController` · `com.fibaro.thermostat`

## Querying live HC3 state
Use `flua --api remote -e "..."` in the terminal to inspect the real HC3 —
credentials come from the .env chain. `api.get` returns (data, status);
passing it to `json.encode` keeps the data (the first value).
```bash
# Get a device's full structure
flua --api remote -e "print(json.encode(api.get('/devices/45')))"
# List all QuickApps
flua --api remote -e "print(json.encode(api.get('/devices?interface=quickApp')))"
# Get a global variable
flua --api remote -e "print(json.encode(api.get('/globalVariables/myVar')))"
# Get QA variables for device 45
flua --api remote -e "print(json.encode(api.get('/plugins/45/variables')))"
```
Run these to understand the actual structure before writing code that reads or updates it.

## Available skills
Type a slash command in chat to load detailed reference:
`/quickapp-api` · `/quickapp-types` · `/quickapp-patterns` · `/hc3-rest-api` · `/lua-basics` · `/flua-troubleshooting` · `/flua-setup` · `/quickapp-troubleshooting` · `/quickapp-test`
