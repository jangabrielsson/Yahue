---
name: quickapp-test
description: How to test and verify a QuickApp offline with flua, without the flua repo or Python tooling. The QA is its own test: assert inside the QA, exit with the failure count, check the exit code; drive UI events and device actions over the HTTP sim API (--ui), use deterministic virtual time and --seed. USE FOR: testing a QA, verifying a change, checking QA behavior offline, writing self-asserting QAs, driving the simulated HC3 from a script or agent.
---

# Testing QuickApps with flua (offline)

flua runs a QA against a simulated HC3 — no controller, no repo needed. The
QA itself is the test harness: it asserts its own behavior and exits with a
code the caller (shell, CI, or an agent) checks. Runtime errors also exit
non-zero, so no code path silently passes.

## The verification loop

```bash
flua --check qa.lua              # 1. static: syntax, --%% directives, deprecated APIs
flua --api local qa.lua          # 2. run offline; the QA must exit itself
echo $?                          # 3. exit code: 0 = pass, non-zero = fail
flua test                        # or: the whole suite — every *_test.lua under
                                 # the cwd, one flua process per file, a per-file
                                 # timeout, and a PASS/FAIL/TIME report (exit 0
                                 # only when everything passes)
```

- The run lasts until the QA calls `exit(0)` / `os.exit(0)` (HC3 names) — a
  QA that never exits runs forever, so every test QA must end with an exit.
- `exit(N)` exits with N; an uncaught Lua error exits 1.
- Several QA files can run in one flua process (each isolated, its own
  device id from 5000): `flua --api local a.lua b.lua`.

## Self-asserting QA pattern

Built-in version — `require("flua-test")`, no boilerplate (the module is
provided by flua itself; require'd code never travels in a packaged .fqa):

```lua
--%%name:my_qa_test
local Test = require("flua-test")
local t = Test.new()

t:expect(cond, "msg")          -- PASS:/FAIL: line, counts failures
t:assert_eq(got, want, "msg")  -- deep compare, tables included
t:assert_json(text, "msg")     -- json.decode succeeds
t:finish()                     -- "failures: N" + exit(failures > 0 and 1 or 0)
```

Asserts can travel to a real HC3 without editing the QA: add
`--%%file:$flua-test.lua,flua_test` to the header — the library ships in
the .fqa, `require("flua-test")` works there too (the file registers
itself in package.preload; main loads last), and on the controller every
assertion is a no-op (flua-only `_FLUA` is absent: no printing, no
counting, `finish()` returns 0). In flua the shipped copy is the full
library. Global spelling: `fluaTest.new()`.

`_FLUA` is flua's **emulator marker**: flua always sets it, the HC3 never
does — the plua equivalent is `fibaro.plua`, which flua does NOT set.
Migrate `if fibaro.plua then ... end` to `if _FLUA then ... end`.

The hand-rolled equivalent (plain Lua, for QAs that must stay dependency-free):

```lua
--%%name:my_qa_test
local failures = 0

local function assertTrue(cond, msg)
  if cond then print("PASS: " .. msg)
  else failures = failures + 1; print("FAIL: " .. msg) end
end

local function assertEq(actual, expected, msg)
  if tostring(actual) == tostring(expected) then
    print("PASS: " .. msg .. " (" .. tostring(actual) .. ")")
  else
    failures = failures + 1
    print("FAIL: " .. msg .. " — expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

function QuickApp:onInit()
  local device = api.get("/devices/" .. self.id)  -- the sim sees the QA
  assertEq(device.id, self.id, "device visible in the sim")

  self:updateProperty("value", 50)
  assertEq(self.properties.value, 50, "updateProperty round trip")

  print("failures:", failures)
  exit(failures > 0 and 1 or 0)
end
```

A ready-made example ships with flua: `flua --examples` prints the examples
directory — run `examples/selfTest.lua`. Read updated properties back via
`self.properties.<name>` (in flua, `updateProperty` does not create a
`self.<name>` field).

## Driving interactions over HTTP (`--ui`)

When the logic under test needs UI events or device actions, serve the sim
API and drive it with curl (or any HTTP client):

```bash
flua --api local --ui 8090 qa.lua &    # sim API + UI viewer on :8090

# UI event (what the HC3 UI sends; value optional, multi selects comma-joined)
curl "http://127.0.0.1:8090/plugins/callUIEvent?deviceID=5000&elementName=B1&eventType=onReleased"
curl "http://127.0.0.1:8090/plugins/callUIEvent?deviceID=5000&elementName=slider&eventType=onChanged&value=42"

# device action
curl -X POST -H "Content-Type: application/json" \
  -d '{"args":["42"]}' http://127.0.0.1:8090/devices/5000/action/setValue

# inspect state: properties + view (updateView target), device list, live layout
curl http://127.0.0.1:8090/devices/5000
curl http://127.0.0.1:8090/flua/devices
curl "http://127.0.0.1:8090/plugins/getView?id=5000"
```

The QA's PASS/FAIL output goes to the flua process's stdout. Kill the
background flua when done.

UI events and the rendered view work from inside the QA too — no curl, no
browser:

```lua
local data, status = _FLUA.uiEvent("onBtn", "onReleased")   -- like the HC3 UI
local data, status = _FLUA.uiEvent("s1", "onChanged", "42") -- values are strings
local view = self:getView()                                  -- current viewLayout
                                                            -- (updateView changes included)
```

The callback fires asynchronously after the call returns — assert on the
callback's effects. `flua --tool ui qa.lua` prints the whole UI as text
(elements, callbacks, options) for a quick eyeball check — **declared**
elements only, not post-init values or callback behavior; for live state
use `self:getView()` or the viewer.

### Simulated devices (bundled)

When the QA under test reacts to *other* devices (sensors, switches,
climate, alarm), load the matching simulated device — bundled with flua,
no files needed:

```lua
local temp = _FLUA.loadSimDevice("temperatureSensor")  -- throws on unknown name
fibaro.call(temp, "setValue", 21.5, "C")               -- value + optional unit
local motion = _FLUA.loadSimDevice("motionSensor")
fibaro.call(motion, "breach")       -- value = true (the sensor's breach state)
fibaro.call(motion, "clearBreach") -- value = false
```

The bundled set mirrors the `quickapp-types` device templates (30 types):
value sensors take `setValue(value, unit?)`/`setUnit(unit)`, breach sensors
`setValue(bool)`/`breach()`/`clearBreach()` (the sensor's `value` IS the
breach state — no separate `breached` property on sensors; that is alarm
partitions), switches `turnOn`/`turnOff`/
`setValue`, controllers their stock actions (`arm`/`disarm`/`setArmed`,
`setThermostatMode`, `setColor`, `createChild`, …). Each device calls
`_FLUA.keepAlive()` in `onInit` (stays up for the whole run); the loader can
end it with `_FLUA.exit(0)`.

### A complete interaction test (copy-paste)

The runnable `examples/ui-interaction-test.lua` chains the whole pattern
— fixture-backed, clock-pinnable, self-asserting, exit code = verdict:

```bash
flua --api local examples/ui-interaction-test.lua
flua --start 2027-01-04 examples/ui-interaction-test.lua   # pin os.date
```

It loads a JSON fixture, injects a button release and a select change via
`_FLUA.uiEvent`, **waits for each asynchronous callback**, asserts both
`self:getView()` (the rendered `$jason` view tree) and the simulator state
(`self.properties` / `api.get("/devices/<id>")`), prints PASS/FAIL lines
and exits with the failure count. The data-driven variant — a table of
`{element, eventType, value, expected}` and one loop — scales the same
pattern to a whole UI (44 buttons, no manual clicking).

**Fixture paths**: `io.open` resolves against the process CWD, not the QA
file — run flua from the fixture's directory, or pass an absolute path
(`-D 'var:fixture=/abs/path/data.json'`). The example's loader errors with
exactly that explanation when the file is missing.

## Machine-readable logs

Agents parsing flua's output should use JSON lines — one object per log
line, exit code unchanged:

```bash
flua --api local --log json qa.lua       # {time, level, tag, qaid, msg} per line
flua --api local --logfile run.log qa.lua   # log copy (ANSI stripped) appended
```

stdout stays pure JSON in `--log json` mode (flua's own notices and the
final verdict — `flua: QA <name> (<id>) exited with code N` — go to
stderr). The verdict line appears for every failing QA, in any log mode.

## Deterministic virtual time

Timer logic must be reproducible — never sleep in a test QA:

```bash
flua --api local --start '2027/10/6 12:00:00' qa.lua   # fixed start time
flua --api local --speed 60 qa.lua                     # 60x virtual speed
flua --api local --instant qa.lua                      # timers fire immediately
flua --api local --step qa.lua                         # deadline-ordered fast-forward (os.time()-coherent)
flua --api local --max-hours 24 qa.lua                 # bound the run
```

`--instant` collapses the whole timer heap into one pass — safe only for
QAs that never compute delays from `os.time()`/`os.date()` (pure
`setTimeout` chains). Event engines with `@@`-rules and any
`os.time()`-relative re-scheduling need `--step` (fast, deadline by
deadline, `os.time()` equals each fired deadline) or `--speed` (flowing).

## Mock the outside world (`net.*Server`)

flua extension (no HC3 counterpart): the QA itself can host the services its
clients talk to, so HTTP/TCP/UDP/WebSocket logic is testable offline with no
Python. Handler runs on each request; its return value is the reply:

```lua
local http = net.HTTPServer()
http:listen(0, function(req)  -- {method,url,headers,body}
  return {status=200, body="ok", headers={["X-Mock"]="1"}}  -- or a string, or nil (204)
end)
local tcp = net.TCPServer()      -- tcp:listen(0, function(data) return data:upper() end)
local udp = net.UDPServer()      -- udp:listen(0, function(data, ip, port) return "got:"..data end)
local ws = net.WebSocketServer() -- ws:listen(0, function(msg, isBinary) return "echo:"..msg end)
-- port 0 = free port; read server.port
net.HTTPClient():request("http://127.0.0.1:" .. http.port .. "/x", {
  success = function(resp) print("mock answered", resp.status, resp.data) end,
})
```

One-shot request/response semantics: the TCP handler sees the first data
package, UDP one datagram, WS one message (binary replies come back as
binary frames). Handler errors reply `500` (HTTP); no reply within 10 s is
`504`. `server:close()` stops a server; servers die with their QA. Canonical
self-test: `examples/mockServer.lua` (`flua --examples` prints the dir).

Handlers are plain closures — they can keep mock state across requests
(`local hits = 0`), branch on `req.url`, and call `api.get` etc. like any QA
code. The reply is the handler's *synchronous* return value, so a mock
cannot simulate latency; for client-timeout tests use an unreachable port or
close the server before the client connects.

Mock code can live in a separate file next to the QA: `require("mocklib")`
finds `mocklib.lua` in the QA's directory and is **not** packaged into the
`.fqa` (only `--%%file` files ship) — keep test scaffolding out of what gets
deployed to the HC3.

## Seeding the simulated HC3

`--seed FILE` loads a JSON world: `{"devices": [...], "rooms": [...],
"scenes": [...], "globalVariables": {...}}` — give the QA devices to talk
to, then assert on the resulting calls and state.

## Gotchas

- Offline is the default; `--api local` makes it explicit and immune to a
  stray `--%%mode:online` (which needs HC3 credentials).
- `self:updateProperty` lands in `self.properties.<name>` — read it back
  there.
- Multi selects deliver `event.values[1]` as the *list* of selected values
  (HC3 contract); empty lists must be `json.array()` so they encode as `[]`.
