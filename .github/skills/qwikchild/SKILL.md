---
name: qwikchild
description: How to use the QwikAppChild library (--%%file:$qwikchild.lua,qwikchild) for managing QuickApp child devices with UID-based addressing, declarative child definitions, per-child UI, internalStorage variables, and UI event routing to children. USE FOR: creating/loading/removing child devices, attaching UI to a child, routing UI callbacks to child methods, persisting child-scoped state, one-shot or declarative child management patterns.
---

# QwikAppChild Library

`QwikAppChild` is a built-in library that extends Fibaro's `QuickAppChild` with UID-based child management, declarative child definitions, per-child UI support, and automatic UI event routing.

## Include It

```lua
--%%file:$qwikchild.lua,qwikchild
```

Add this header to your QA file. No `require` needed — the file is executed on load and registers everything globally.

> The library prints `QwikAppChild library v2.x.x` on load to confirm it is active.

---

## Core Concepts

| Concept | Description |
|---|---|
| **UID** | A stable string ID you assign to each child (e.g. `"i1"`, `"sensor_kitchen"`). Survives restarts and recreations. |
| **ClassName** | The Lua class name of the child (`"MySensor"`). Stored in the child's internalStorage. |
| **`QwikAppChild`** | Base class — use instead of `QuickAppChild` for children managed by this library. |

---

## QuickApp Methods Added by the Library

### `self:initChildren(children)` — declarative, recommended

Creates missing children, loads existing ones, removes children not in the definition table. One call replaces manual create/load/remove logic.

```lua
local children = {
  i1 = {
    name       = "Kitchen Sensor",
    type       = "com.fibaro.temperatureSensor",
    className  = "KitchenSensor",
    properties = { value = 20 },
    interfaces = { "battery" },
    store      = { pollInterval = "30" },  -- written to internalStorage
    room       = 5,                        -- HC3 room ID (optional)
    UI         = {                         -- optional per-child UI
      { label="lbl", text="Ready" },
      { button="refresh", text="Refresh", onReleased="refresh" },
    },
  },
  i2 = {
    name      = "Bedroom Sensor",
    type      = "com.fibaro.temperatureSensor",
    className = "BedroomSensor",
  },
}

function QuickApp:onInit()
  self:initChildren(children)
end

-- (quickApp is set by the library itself, and it already suppresses the
-- default child init — no boilerplate needed.)
```

> **UID naming tip:** UIDs starting with `"i"` followed by a digit (e.g. `"i1"`, `"i2"`) are sorted numerically during creation — useful to control creation order.

---

### `self:createChild(uid, props, className [, UI])` — manual, single child

Creates one child (or recreates it if a child with that UID already exists).

```lua
local props = {
  name       = "Hallway Switch",
  type       = "com.fibaro.binarySwitch",
  properties = { value = false },
  interfaces = {},
  store      = {},
}
local UI = {
  { label = "status", text = "Off" },
  { button = "toggle", text = "Toggle", onReleased = "toggle" },
}
local child = self:createChild("hall_sw", props, "HallwaySwitch", UI)
```

---

### `self:loadExistingChildren([childrenDefs])` — load without recreating

Loads previously created children from HC3 without modifying them. Pass a definitions table to restrict which UIDs are loaded; omit it to load all children.

```lua
function QuickApp:onInit()
  self:loadExistingChildren()   -- load all children found on HC3
end
```

---

### `self:createMissingChildren(children)` — create only, no removal

Creates children that don't exist yet. Does not remove extras. Useful when you want additive-only management.

---

### `self:removeUndefinedChildren(childrenDefs)` — remove extras

Deletes any child on HC3 whose UID is not in `childrenDefs`. Called automatically by `initChildren`.

---

### `self:getChildrenUidMap()` → `{uid → {id, className}}`

Returns a map of all children found on HC3 for this parent QA.

```lua
local map = self:getChildrenUidMap()
for uid, info in pairs(map) do
  print(uid, info.id, info.className)
end
```

---

### `QuickApp.setChildRemovedHook(_, fn)` — removal callback

Called with the child device ID whenever a child is removed.

```lua
QuickApp.setChildRemovedHook(nil, function(id)
  print("child removed:", id)
end)
```

---

## Child Class Definition

Extend `QwikAppChild` instead of `QuickAppChild`:

```lua
class "MySensor"(QwikAppChild)

function MySensor:__init(device)
  QwikAppChild.__init(self, device)
  -- self._uid       → the UID string assigned at creation
  -- self._className → class name string
  -- self._sid       → numeric suffix of the UID (e.g. 1 for "i1")
  self:debug("MySensor ready, uid:", self._uid)
end

function MySensor:refresh(event)
  self:updateProperty("value", 21.5)
  self:updateView("lbl", "text", "21.5°C")
end
```

### Methods inherited from `QuickAppChild` (still available)

- `self:updateProperty(name, value)`
- `self:updateView(elementName, property, value)`
- `self:debug(...)` / `self:warning(...)` / `self:error(...)`
- `self:getVariable(name)` / `self:setVariable(name, value)`
- `self:internalStorageGet(key)` / `self:internalStorageSet(key, value)`
- `self:callAction(name, ...)` — call a method by name

> `self.parent` is set to the parent `QuickApp` object after the child is initialized.

---

## Per-Child UI

Pass a `UI` table to `createChild` or inside the `initChildren` definition. The library converts it to the HC3 `uiView` and `uiCallbacks` format automatically.

```lua
UI = {
  { label = "status", text = "Idle" },
  { button = "on",  text = "On",  onReleased = "turnOn"  },
  { button = "off", text = "Off", onReleased = "turnOff" },
  { slider = "dim", text = "Dim", min = "0", max = "100", onChanged = "setLevel" },
}
```

UI callback methods are defined on the child class:

```lua
function MySensor:turnOn(event)   self:updateProperty("value", true) end
function MySensor:turnOff(event)  self:updateProperty("value", false) end
function MySensor:setLevel(event) self:updateProperty("value", tonumber(event.values[1])) end
```

### UI event routing — `setupUIhandler`

The library installs a `UIHandler` on the parent QA that routes UI events to the correct child object automatically. You do not need to implement `UIHandler` yourself as long as you use `QwikAppChild`.

Routing priority for an element named `elm`:
1. `obj[elm](obj, event)` — method named exactly after the element
2. `obj[uiCallbacks[elm][eventType]](obj, event)` — callback registered via `uiCallbacks`
3. `obj[elm.."Clicked"](obj, event)` — fallback convenience naming

---

## internalStorage Helpers

Per-child key/value storage backed by QA variables on HC3:

```lua
-- In child __init or anywhere with the child object:
local interval = self:internalStorageGet("pollInterval")  -- returns nil if not set
self:internalStorageSet("lastSeen", os.date("%Y-%m-%d"))
```

The `store` field in a child definition pre-sets keys at creation time:

```lua
i1 = {
  ...
  store = { pollInterval = "30", location = "kitchen" },
}
```

---

## Debug Flag

```lua
fibaro.debugFlags.qwikchild = true   -- enable verbose library logging (default: true)
fibaro.debugFlags.qwikchild = false  -- silence it
```

---

## The living example

`examples/qwikchildtest.lua` — two children with UIs, self-tested: the QA
injects UI events through the same REST route the HC3 UI viewer uses
(`/plugins/callUIEvent?deviceID=..&elementName=..&eventType=..`) and
asserts the children reacted (label updated, property changed). Copy the
pattern for your own tests.

## Full Minimal Example

```lua
--%%name:MultiSensor Hub
--%%type:com.fibaro.deviceController
--%%offline:true
--%%file:$qwikchild.lua,qwikchild

class "RoomSensor"(QwikAppChild)

function RoomSensor:__init(device)
  QwikAppChild.__init(self, device)
  self:debug("RoomSensor init, uid:", self._uid)
end

function RoomSensor:refresh(event)
  -- called from button press
  self:updateView("lbl", "text", "Refreshed!")
end

local CHILDREN = {
  i1 = {
    name      = "Kitchen",
    type      = "com.fibaro.temperatureSensor",
    className = "RoomSensor",
    UI = {
      { label = "lbl", text = "Ready" },
      { button = "refresh", text = "Refresh", onReleased = "refresh" },
    },
  },
  i2 = {
    name      = "Bedroom",
    type      = "com.fibaro.temperatureSensor",
    className = "RoomSensor",
  },
}

function QuickApp:onInit()
  self:initChildren(CHILDREN)
end
```

---

## Common Gotchas

- **`quickApp = self`** — the library sets the `quickApp` global itself
  (`createChild`/`loadExistingChildren` do it); setting it yourself is
  harmless insurance, not a requirement.
- **`initChildDevices`** — the library already overrides the default child
  init with a no-op; you do not need to suppress it yourself.
- **`initChildren` attaches or creates** — existing children (matched by
  UID through their internalStorage) are LOADED and reused, not recreated;
  only missing ones are created, and undefined ones are removed. That is
  the whole point: the same code runs on a fresh HC3 and on one with
  existing children. `createChild` is the one that deletes-and-recreates a
  child with the same UID.
- **flua offline mode** — children are sim devices: they vanish between
  runs unless state is persisted. `initChildren` warns about it; pin state
  with `--%%db:+file.json` (the plua `--%%save:` directive is not a flua
  thing).
- **UID uniqueness** — UIDs must be unique within a parent QA. The library uses them as stable identifiers; duplicate UIDs cause the old child to be deleted.
