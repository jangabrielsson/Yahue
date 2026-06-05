# Yahue — Architectural Review & Refactoring Plan

> Generated 2026-06-04

## Overview

Yahue is a Fibaro HC3 QuickApp (Lua) that bridges the Philips Hue v2 REST API into HC3's device model. It discovers Hue resources, maps them to HC3 child device types, and keeps state synchronized via SSE and periodic health checks.

**Stats:**
- 6 Lua source files, ~4,000 total lines
- `engine.lua`: 1,765 lines (44% of total)
- Mature codebase with thorough comments, i18n (6 languages), solid edge-case handling

**Overall assessment:** The code is well-written at the line level — SSE reconnect, rate-limit governor with escalation, and per-member room aggregation are genuinely sophisticated. The architecture has accumulated organically and now shows clear separation-of-concerns problems.

---

## What Works Well

1. **Resource class hierarchy** — `hueResource` base class with prototypical inheritance for each Hue service type (light, motion, temperature, contact, button, etc.). Props/methods tables define the interface per type declaratively.

2. **Rate-limit governor** — 429 handling with escalation tracking, `Retry-After` header parsing, centralized `bridgeReady()` guard. Every code path (PUT pacer, SSE getw, refresher GET) routes through the same governor.

3. **Bucketed PUT queueing** — Deduplication by path+slot, FIFO with cap, last-write-wins semantics. The slot mechanism (`'off'` vs `'PUT'`) for instant-off-then-dim is well-designed.

4. **i18n properly isolated** — `lang.lua` is self-contained with a clean `T(key)` interface and fallback chain.

5. **User configuration escape hatch** — `userconfig.lua` is loaded before `devices.lua`, never auto-updated.

6. **Dirty-tracking resource refresh** — `_dirty` flag pattern for detecting removed resources on health-check refresh.

7. **Robust child lifecycle** — `qwikchild.lua` handles creation, loading, UI-version patching, cleanup, and stale-reference recovery — with per-child `pcall` wrappers.

---

## Architectural Problems

### 1. `engine.lua` is a monolith (1,765 lines)

The file mixes five distinct concerns inside a single closure (`main()`):

| Concern | Lines | Description |
|---|---|---|
| Event system shim | 61–67 | `fibaro.event`/`fibaro.post` |
| Resource model | 125–837 | Resource registry + ~25 class definitions |
| SSE polling | 839–1084 | Event stream fetch, parse, reconnect |
| HTTP + rate limiting | 1086–1390 | GET/PUT, governor, bucket queueing |
| Startup orchestration | 1391–1765 | State machine, health checks, public API |

These are locked inside `main()`'s closure — every function captures the closure's upvalues. You cannot test or reason about any unit in isolation.

### 2. No formal layering

Current implicit layers:
```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Yahue.lua  │────▶│   engine.lua     │◀────│  devices.lua    │
│ (entry pt)  │     │ (everything)     │     │ (child classes) │
└─────────────┘     └────────┬─────────┘     └────────┬────────┘
                             │                        │
                      ┌──────▼──────┐          ┌──────▼──────┐
                      │  utils.lua  │          │qwikchild.lua│
                      │  (colors)   │          │ (child mgmt) │
                      └─────────────┘          └─────────────┘
```

Everything communicates through the global `fibaro.engine` singleton. The engine is simultaneously a transport client, domain model registry, and public API.

### 3. `HUE:app()` in devices.lua owns startup orchestration

`HUE:app()` (line 110 of `devices.lua`) is the de facto application entry point — it discovers resources, builds child definitions, calls `initChildren`, and populates the UI dropdown. But it lives in `devices.lua`, which is supposed to be "device class definitions."

- Adding a new resource type requires touching both `engine.lua` (class definition) AND `devices.lua` (`devProps` mapping + `HUE:app()`)
- The startup sequence is split across two files
- The `callBack` chain (`_initEngine` → `main()` → `REFRESHED_RESOURCES` → `callBack()`) is fragile

### 4. Ad-hoc pub/sub without a formal event bus

```lua
self.listeners[key] = self.listeners[key] or {}
self.listeners[key][#self.listeners[key]+1] = callback
```

No unsubscribe mechanism, no namespacing, no error isolation (one broken listener crashes the publish loop). The `publishAll()` / `publishMySubs()` distinction is implicit.

### 5. `defClass` removes classes from `_G` — non-obvious side effect

```lua
local function defClass(name, parent)
  local p = class(name)     -- Fibaro's class() puts it in _G
  local cl = _G[name]
  classes[name] = cl
  _G[name] = nil            -- removed from global!
  if parent then p(parent) end
  return cl
end
```

Intended as isolation, but done through side effects rather than a clear module boundary. Engine classes are invisible outside the closure — `devices.lua` can't reference them.

### 6. Duplicated command logic (~150 lines)

`DimmableLight` (individual lights) and `RoomZoneQA` (room/zone groups) both implement `turnOn`, `turnOff`, `setValue`, `setDim`, `fadeTo`, `startLevelIncrease`, `startLevelDecrease`, `stopLevelChange` — copy-pasted with slight variations (`self.light` vs `self.group`).

### 7. Complex scene loading is inline

`loadScenesForRoom()` in `devices.lua` is ~70 lines of nested iteration over scenes, groups, and actions — all inline in the class definition.

---

## Refactoring Plan

Given Fibaro HC3 constraints (all files bundled into a single `.fqa`, limited Lua environment, `%%file` includes), the refactoring is structured as evolutionary phases — split files without changing behavior, then introduce new abstractions.

### Phase 1 — File split (low risk, high value)

Split `engine.lua` into logical modules that still share the `fibaro.engine` namespace:

| New file | Lines | Content |
|---|---|---|
| `hue-core.lua` | ~200 | `setup()`, `main()` skeleton, `_initEngine` |
| `hue-resources.lua` | ~650 | Resource registry, `hueResource`, all ~25 subclasses |
| `hue-transport.lua` | ~300 | `hueGET`, `huePUT`, SSE polling, rate-limit governor, bucket queueing |
| `hue-startup.lua` | ~200 | State machine, health checks, public API (`HUE:pingSSE`, `HUE:getSceneByName`, dump utilities) |

**Risk:** Near zero. Same code, same closure, same behavior. Just organizing `main()`'s body into `%%file` includes.

### Phase 2 — Extract discovery orchestration (medium risk, medium value)

Move `HUE:app()` from `devices.lua` into new `hue-app.lua`:

| New file | Content |
|---|---|
| `hue-app.lua` | Discovery, child definition building, UI population |

Keep `devices.lua` purely as class definitions (`HueClass`, `TemperatureSensor`, `BinarySwitch`, `RoomZoneQA`, etc.)

**Risk:** Medium. The callback chain must be preserved, but the boundary is already implicit.

### Phase 3 — Formalize the event bus (medium risk, high value)

Replace the ad-hoc `.listeners` table with a proper event bus:

```lua
-- Before
self.listeners[key][#self.listeners[key]+1] = callback

-- After
hueBus:on(resourceId, eventName, callback)
hueBus:emit(resourceId, eventName, value)
```

Benefits:
- Unsubscribe (prevents listener leaks)
- Error isolation (`pcall` per handler)
- Namespaced events (`"light:on"`, `"light:dimming"`)
- Testability (inject a mock bus)

**Risk:** Medium. Every `:subscribe` and `:publish` call site changes, but semantics are identical.

### Phase 4 — Extract adapter layer (medium risk, medium value)

Create `hue-hc3-adapter.lua` owning the mapping between Hue resources and HC3 types:

```lua
-- Before (inline in devices.lua)
local devProps = {
  temperature = "TemperatureSensor",
  [function(p) return p.on and p.dimming ... end] = "DimLight",
}

-- After (in adapter)
HUE.adapter = {
  mapDeviceToClass = function(props) ... end,
  mapRoomZoneToClass = function(resource) ... end,
  buildChildDef = function(resource, class) ... end,
}
```

**Risk:** Medium. Changes the interface between engine and `devices.lua`, but the mapping logic is already declarative.

### Phase 5 — Shared light command mixin (medium risk, low value)

Extract duplicated `turnOn`/`turnOff`/`setValue`/`setDim`/`fadeTo`/`startLevelIncrease` logic from `DimmableLight` and `RoomZoneQA`:

```lua
local LightCommands = {
  turnOn = function(self) ... end,   -- uses self._cmdTarget
  turnOff = function(self) ... end,
  -- etc.
}

-- Usage:
DimmableLight:__init → self._cmdTarget = self.light; LightCommands.mixin(self)
RoomZoneQA:__init    → self._cmdTarget = self.group;  LightCommands.mixin(self)
```

**Risk:** Low. Same code, same behavior. The `self.light` vs `self.group` difference is the only variable.

### Phase 6 — Extract scene utilities (low risk, low value)

Pull `loadScenesForRoom()` and related helpers into `hue-scenes.lua`.

**Risk:** Low. Pure extraction, no logic changes.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Yahue.lua                         │
│              (QuickApp entry point)                  │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                  hue-core.lua                        │
│              (setup, main skeleton)                  │
└──────────────────────┬──────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
┌───────▼──────┐ ┌──────▼──────┐ ┌────▼──────────┐
│hue-transport │ │hue-resources│ │ hue-startup    │
│   .lua       │ │   .lua      │ │   .lua         │
│              │ │              │ │                │
│ HTTP GET/PUT │ │ Resource     │ │ State machine  │
│ SSE polling  │ │  registry    │ │ Health checks  │
│ Rate governor│ │ ~25 classes  │ │ Public API     │
│ Bucket queue │ │              │ │ Dump utils     │
└──────┬───────┘ └──────┬───────┘ └────┬───────────┘
       │                │              │
       └────────────────┼──────────────┘
                        │
              ┌─────────┴─────────┐
              │                   │
     ┌────────▼────────┐  ┌───────▼────────┐
     │ hue-hc3-adapter │  │  hue-app.lua   │
     │     .lua         │  │                │
     │                  │  │  Discovery     │
     │ Type mapping     │  │  Child defs    │
     │ devProps         │  │  UI population │
     └────────┬────────┘  └───────┬────────┘
              │                   │
     ┌────────▼────────┐  ┌───────▼────────┐
     │  devices.lua     │  │ hue-scenes.lua │
     │                  │  │                │
     │  Child classes   │  │  Scene loading │
     │  HueClass        │  │  Dropdowns     │
     │  ~13 subclasses  │  │  Recall        │
     └──────────────────┘  └────────────────┘

┌──────────┐  ┌───────────┐  ┌──────────────┐
│utils.lua │  │ lang.lua  │  │qwikchild.lua │
│ Colors   │  │   i18n    │  │ Child mgmt   │
│ RGB↔xy   │  │  6 langs  │  │ UI versioning│
│ Kelvin   │  │  T(key)   │  │ Lifecycle    │
└──────────┘  └───────────┘  └──────────────┘
```

---

## What Not to Touch

- **`qwikchild.lua`** — Mature, well-tested, self-contained. Leave as-is.
- **`utils.lua`** — Pure functions, no dependencies, clean namespace. Leave as-is.
- **`lang.lua`** — Perfectly isolated, clean interface. Leave as-is.
- **`userconfig.lua`** — User-facing, must remain stable.
- **Rate-limit governor** — Current design (escalation tracking, `bridgeReady()` guard, centralized cooldown) is one of the best parts of the codebase. Phase 1 moves it to its own file but the logic doesn't change.

---

## Summary Table

| Dimension | Current | Target |
|---|---|---|
| Files | 1 monolith (44% of code) + 5 support | 7–10 focused modules |
| Layers | Implicit, everything talks to `fibaro.engine` | Transport → Domain → Adapter → App |
| Pub/sub | Ad-hoc listeners table | Formal event bus with unsubscribe |
| Duplication | ~150 lines duplicated between DimmableLight/RoomZoneQA | Shared command mixin |
| Testability | None (closure captures everything) | Some (event bus mockable, domain classes separable) |
| Risk of refactoring | N/A | Low to medium, phased, behavior-preserving |

## Priority Order

1. **Phase 1** — File split `engine.lua`. Dramatically improves navigability. Near zero risk.
2. **Phase 2** — Extract discovery from `devices.lua`. Clarifies boundaries.
3. **Phase 3** — Formalize event bus. Enables testability.
4. **Phase 4** — Extract adapter layer. Cleaner type mapping.
5. **Phase 5** — Shared command mixin. Reduce duplication.
6. **Phase 6** — Extract scene utilities. Optional polish.
