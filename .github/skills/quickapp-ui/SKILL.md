---
name: quickapp-ui
description: HC3 QuickApp UI at runtime: self:updateView(...) for every element type (label, button, slider, switch, select, multi) — which properties and values each accepts (text, value, visible, disabled, image, min/max/step, color, options, selectedItem/selectedItems/values), the value rules (strings, select matching by option value, not text), the UI event contract (onReleased/onLongPress*/onToggleOn/onToggleOff/onChanged/onToggled and their event.values shapes), and how to assert or drive UI state in tests (self:getView(), _FLUA.uiEvent, /plugins/callUIEvent). USE FOR: changing UI elements at runtime, updating a label/slider/select from QA code, debugging why an updateView call does not show in the viewer, wiring UI callbacks.
---

# QuickApp UI at Runtime: updateView, Events, Viewer Semantics

How UI elements change while the QA runs. For the `--%%u:` directive syntax that
*declares* the elements, see `/quickapp-types`; this skill covers what happens
after that — `self:updateView`, the callback events, and how the flua viewer
renders each element. flua matches the HC3 5.221 behavior; where they differ,
it is called out below.

## The one method: self:updateView

```lua
self:updateView(componentName, property, value)
```

It writes `value` under `property` for the named component (HTTP
`/plugins/updateView`). The viewer merges this live state over the declared
element on every poll, and `self:getView()` returns the merged view — assert
UI state with it.

## updateView reference per element

- **label** — `text` (string, **HTML allowed**: `<font color='red'>`, `<table>`, …)
- **button** — `text` (string), `image` (named icon from the viewer's icon set;
  unknown names render text-only), `disabled` (bool)
- **slider** — `value` (string), `min`/`max`/`step` (strings), `unit` (string,
  rendered right of the value: "21 °C"), `color` (CSS color, sets the thumb),
  `disabled` (bool)
- **switch** — `value` (`"true"`/`"false"` strings), `text`, `image`
- **select** (single) — `selectedItem` (scalar), `options` (full replacement of
  the option list), `values` (list; the 5.221 schema reads the first entry),
  `text` (the placeholder shown when nothing matches)
- **multi** — `selectedItems` (list of values), `options`, `values`, `text`
- **every element** — `visible` (bool; `false` hides the element — it takes no
  row space)

```lua
self:updateView("statusLbl", "text", "Zone 1: 21.5°C")
self:updateView("setpoint", "value", "21.5")
self:updateView("autoSwitch", "value", "true")
self:updateView("modeSelect", "selectedItem", "eco")
self:updateView("modeSelect", "options", {{type='option',text='Eco',value='eco'},
                                              {type='option',text='Manual',value='manual'}})
self:updateView("tagMulti", "selectedItems", {"1", "3"})
self:updateView("warnLbl", "visible", false)
```

## Value rules that bite

- **Values are strings.** Sliders and switches compare by string; always
  `tostring(n)` numbers. `updateView("s", "value", 75)` renders but compares
  as `"75"` on the wire — pass strings deliberately.
- **`selectedItem` matches an option's `value`, not its `text`.** Setting the
  label (e.g. `"Partly cloudy"` when the option values are `clear`, `rain`, …)
  selects nothing and the dropdown shows its placeholder. Normalize the value
  to the option-value vocabulary before the call.
- **`options` replaces the whole list** — send the complete new list, not a
  delta. It is a structure change (the dropdown rebuilds).
- **`selectedItems` is a Lua table**, `selectedItem` a scalar. On the HC3,
  using `"values"` where the canonical property applies silently does nothing;
  prefer `selectedItem`/`selectedItems`.
- **`disabled`** only disables buttons and sliders in the viewer; switches and
  selects ignore it (HC3 UI parity — use `visible` to hide instead).
- **Viewer precedence**: live `updateView` state wins over the user's last
  click on the element, which wins over the declared directive value. The QA
  is not expected to echo the user's interaction back — but once the QA sets
  a live value, it wins until changed again.

## The UI event contract

The viewer delivers interactions through `event = {deviceId, eventType,
elementName, values}`. Wire callbacks with the directive's event keys
(`--%%u:{slider='s',text='S',onChanged='handler'}`); the QA method receives
the event table.

- **button** — `onReleased`, `onLongPressDown`, `onLongPressReleased`.
  `event.values` is empty (no value).
- **switch** — `onReleased`, plus the 5.221 split events `onToggleOn` /
  `onToggleOff` (sent when declared; the viewer prefers them). The value is a
  **string**: `event.values[1] == "true"` / `"false"` — not a boolean.
- **slider** — `onChanged`. `event.values[1]` is the value as a **string**;
  `tonumber()` it.
- **select** — `onToggled`. `event.values[1]` is the picked option **value**
  (string).
- **multi** — `onToggled`. `event.values[1]` is the **list** of picked values
  (flua restores the list; on the real HC3 they arrive comma-joined in the
  single value parameter).

```lua
function QuickApp:modeToggled(event)
  self:updateView("modeSelect", "selectedItem", event.values[1])  -- echo the pick
end
```

**Buttons call `uib2OnReleased` instead of your handler?** The QA was
created from a package without `initialProperties.apiVersion` — on recent
firmware (live-verified 5.22x) the HC3's JSON `POST /quickApp`
API-create treats marker-less packages as legacy and re-derives
uiCallbacks with generated default names, so custom handlers get dropped
and taps log "Class does not have uib2OnReleased function defined". Fix
it by adding the marker (`initialProperties.apiVersion = "1.3"` — flua's
pack writes it) and re-creating through the JSON API — or re-import the
package, which preserves it verbatim regardless: via the HC3 web UI's
Import button or flua's `--tool uploadFQA`/`uploadQA` (both use
`POST /quickApp/import` — see the hc3-rest-api skill).

## Asserting and driving UI state in tests

- `self:getView()` — the QA's current rendered view including all `updateView`
  changes; parse it to assert label texts, slider values, `selectedItem`, …
- `_FLUA.uiEvent(elementName, eventType[, value])` — inject a UI event from a
  test/verify QA, exactly like a tap on the real UI would deliver it.
- `GET /plugins/callUIEvent?deviceID=<id>&elementName=<n>&eventType=<t>[&value=<v>]`
  — the viewer's channel; drive it from outside the QA (curl, tests). POST with
  a JSON body is the proxy channel.

```lua
_FLUA.uiEvent("setpoint", "onChanged", "21.5")
local view = self:getView()
assert(tostring(view.body.sections.items[1].components[1].value) == "21.5")
```

A runnable QA exercising every element's updateView and callbacks lives in
[`templates/updateview-demo.lua`](./templates/updateview-demo.lua) — run it
with `flua --ui` and watch the viewer, or drive it from a test QA.
