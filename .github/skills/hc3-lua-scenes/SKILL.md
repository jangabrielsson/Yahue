---
name: hc3-lua-scenes
description: Write and debug Lua scenes for the Fibaro HC3 / Yubii Home — declarations (triggers and conditions: device, cron, sunrise/sunset, global variables, custom events), actions code, sourceTrigger, scene variables, the restart option, and the scene-vs-QuickApp choice. USE FOR: a "when X then Y" automation, converting a block scene to Lua, a scene that does not start, scene variables, or any mention of fibaro scenes. Also explains what flua can and cannot do with scenes.
---

# HC3 Lua Scenes

## Scene or QuickApp?

| Need | Scene | QuickApp |
|---|---|---|
| React to an event (button, door, time, variable) with a few actions | ✅ | heavier |
| Keep state in memory, run permanently, network I/O (HTTP/TCP/MQTT) | ❌ starts fresh each run | ✅ |
| Buttons / labels in the UI | ❌ | ✅ |

Rule of thumb: QuickApps are the drivers, scenes chain actions by calling QA methods
(`fibaro.call(qaId, "setMode", "Away")`).

## Two parts

1. **Declarations** (conditions / triggers): a Lua *table*, not code — *when* the scene starts.
2. **Actions**: Lua code executed at each start.

Tip: build the scene in **block mode**, then "Convert to Lua" — the HC3 writes exact
declarations (property names, weekday numbers). Conversion is one-way.

## Declarations

```lua
{
  operator = "all",               -- "all" (AND) | "any" (OR); groups can be nested
  conditions = {
    { type = "device", id = 201, property = "value", operator = "==", value = true, isTrigger = true },
    { type = "date", property = "cron", operator = "match", value = {"*", "*", "*", "*", "*", "*"}, isTrigger = false },
  }
}
```

- `isTrigger = true`: a **change** of this condition starts the scene (all conditions are
  then evaluated); `false`: filter only. At least one trigger is needed or the scene never
  starts by itself.
- Operators: `==`, `!=`, `>`, `>=`, `<`, `<=`, `anyValue` (any change), `match` (dates).
- `duration = 60` in a device condition: must stay true 60 s (visible in converted block scenes).
- Condition types: device, central scene button, cron, sunrise/sunset, global variable,
  custom event, alarm, location, weather, HC3 start.

## Actions

```lua
fibaro.debug("MyScene", json.encode(sourceTrigger))      -- first line while developing
if sourceTrigger.type == "device" then                    -- .id, .property, .value
elseif sourceTrigger.type == "date" then
elseif sourceTrigger.type == "user" then                  -- started by hand (Run button, app)
end
```

Functions: `fibaro.call`, `fibaro.getValue`, `fibaro.get` (value + timestamp),
`fibaro.getGlobalVariable` / `setGlobalVariable` (strings), `fibaro.getSceneVariable` /
`setSceneVariable` (persist between runs of the same scene), `fibaro.alert`,
`fibaro.emitCustomEvent`, `fibaro.scene("execute"|"kill", {ids})`, `fibaro.profile`,
`fibaro.alarm`, `fibaro.setTimeout(ms, fn)`, `api.*`, `net.HTTPClient`, `json`.
Logs need a **tag**: `fibaro.debug("Tag", "msg")`.
Notifications: same rules as QuickApps — see the quickapp-api skill, `assets/notifications.md`.

## Traps (read before answering "my scene does not work")

1. No memory between runs → scene variables or global variables.
2. **"Allow restarting a running scene"**: *Yes* = a new trigger kills the running instance
   (pending `setTimeout` lost) and starts again — right for "light off 5 min after the last
   motion"; *No* = triggers are ignored while it runs (including while a `setTimeout` waits).
3. Manual mode ignores declarations.
4. Triggers fire on **changes** only: the same value again does nothing.
5. Value types: switch `true/false`, dimmer / shutter 0–99, sensors numbers; global variables
   are always strings (`== "1"`, not `== 1`); in declarations write `value = true` unquoted.
6. A scene that changes its own trigger device can loop: filter with `sourceTrigger`.
7. Only device **properties** trigger scenes; a QuickApp's internal variable does not (a
   global variable does, and QA property updates like `value` do).
8. Avoid `while true` / long `fibaro.sleep`: use triggers, `setTimeout`, or a QuickApp.
9. Weekday numbering in cron and some property names vary: check a converted block scene.

## flua and scenes

flua now **runs scene code**: a QA with `--%%scene:true` is a scene — the
file's declarations (`COND = {...}`) go above a marker line, the actions
below it (`-- ===== SCENE ACTIONS =====`), and the actions re-run on every
scene start with `sourceTrigger` and `_sceneId` in scope, like the HC3.

- **Phase 1**: boot parses the declarations only (actions do NOT run at
  boot); `POST /scenes/{id}/execute` — or `fibaro.scene("execute", {id})` —
  runs the actions with `sourceTrigger = {type = "manual", property = "execute"}`.
  The scene answers `GET /scenes`.
- **Phase 2 (current)**: the conditions evaluator. refreshEvents are
  transformed to sourceTrigger tables and posted through the pump; date
  triggers (cron `match`, `matchInterval`, `sunrise`/`sunset`) arm
  virtual-clock timers; `se-start` fires at boot. On each event the scene
  checks whether any **trigger** leaf (`isTrigger = true`) matches, then
  evaluates the whole tree against current state and runs the actions.
  `duration` defers the run and re-checks the whole tree at `now + duration`
  (a change that breaks the condition cancels the pending run).
- **Semantics** (verified against the spec): filters never start a check —
  only trigger leaves do; `anyValue` triggers on any change; `match>` /
  `match>=` / `match<` / `match<=` are filters-only (a trigger flag on them
  warns and is ignored); cron is `{minute, hour, dom, month, dow, year}`
  with dow 1=Monday, lists like `"1,3"` allowed; `matchInterval` fires at
  `date + k*interval` (grid-aligned); sunrise/sunset take a minute offset
  (−before, +after).
- **Not yet**: `getSceneVariable`/`setSceneVariable` (still stubs), the
  allowRestart option. Weather/profile/alarm condition state is best-effort
  offline (the sim's fake weather, simulated alarm partitions, seeded
  profiles); in online mode weather, alarm partitions and profiles are
  served from the real HC3.
- **Seeding**: the `--seed` JSON file accepts a `"scenes"` array
  (`{id, name, ...}`) — metadata-only scenes (no runner).
- **Reading**: `api.get("/scenes")`, `api.get("/scenes/{id}")`.
- **Custom events**: `fibaro.emitCustomEvent(name)` — on the real HC3 these
  trigger scenes; flua delivers them to QAs that define `onCustomEvent(name)`
  (a flua extension).

To develop scene *logic* in flua: `--%%scene:true`, drive the triggers with
`--start`, timers, or `api` calls, and execute the scene to see the actions
run with a chosen `sourceTrigger`. Living example: `examples/scenes.lua` —
a self-testing driver that loads a scene from an inline string, triggers it
by flipping a device, and checks the result.
