# Yahue — User Documentation

Yahue is a Fibaro HC3 QuickApp that bridges the Philips Hue v2 API. It discovers all Hue devices and rooms on your bridge and lets you selectively expose them as native HC3 child devices — sensors, lights, switches, and room controllers — that work seamlessly with scenes, automations, and the Fibaro mobile app.

---

## Installation

### Prerequisites

- Fibaro HC3 with firmware supporting QuickApp child devices
- Philips Hue Bridge (v2, firmware ≥ 1.60)

### Installing the QuickApp

1. Download `dist/Yahue.fqa` from the [GitHub releases page](https://github.com/jangabrielsson/Yahue/releases)
2. On your HC3 go to **Settings → QuickApps → Add QuickApp** and upload the `.fqa` file
3. Open the newly created QuickApp and set the `Hue_IP` QuickApp Variable to the IP address of your Hue bridge (e.g. `192.168.1.50`)
4. Save and restart the QuickApp

On startup, if no application key is stored yet, the info label will show:
> _Set Hue_User, or press 'Pair with bridge'_

### Option A — Pair from the QuickApp panel (recommended)

This is the easiest method and requires no tools.

1. Make sure `Hue_IP` is set correctly and the QuickApp has been restarted
2. Press **Pair with bridge** in the QuickApp panel
3. The info label changes to _"Press the button on your Hue bridge now…"_
4. Walk to your Hue bridge and press the physical link button within **30 seconds**
5. Yahue fetches the application key automatically, saves it to the `Hue_User` variable, and restarts itself

### Option B — Enter an existing key manually

If you already have a Hue application key (e.g. from another app or from using the Hue developer debug tool):

1. Open the QuickApp settings and set the `Hue_User` QuickApp Variable to your key
2. Save and restart the QuickApp

On startup the QuickApp connects to the bridge, discovers all devices and rooms, and populates the device selector.

---

## Selecting devices

The QuickApp panel shows a multi-select list of every Hue resource that can be exposed as an HC3 child device. Each entry shows the device name and its type abbreviation in brackets.

1. Tick the devices and rooms you want to create child devices for
2. Press **Apply selection**
3. The QuickApp restarts and creates (or removes) child devices to match your selection

Child devices are persistent — they survive QuickApp restarts. You only need to use the selector when you want to add or remove devices.

---

## Device type mapping

Yahue automatically picks the appropriate HC3 device type based on the Hue resource's capabilities.

### Sensors

| Hue capability | HC3 type | Notes |
|---|---|---|
| Temperature service | `com.fibaro.temperatureSensor` | Reports °C |
| Light / illuminance service | `com.fibaro.lightSensor` | Reports lux |
| Motion service | `com.fibaro.motionSensor` | `value = true` when motion detected |
| Contact report service | `com.fibaro.doorSensor` | `value = true` when open. Remappable — see below |
| Button service | `com.fibaro.remoteController` | Emits centralSceneEvents (keys 1–4) |
| Relative rotary service | `com.fibaro.multilevelSensor` | Accumulates rotation into 0–100 |
| Motion area configuration | `com.fibaro.motionSensor` | OR-logic across all sensors in the area |

### Lights

| Hue light capabilities | HC3 type | Notes |
|---|---|---|
| On/off only | `com.fibaro.binarySwitch` | |
| On + dimming | `com.fibaro.multilevelSwitch` | |
| On + dimming + color temperature | `com.fibaro.colorController` | |
| On + dimming + color (xy) | `com.fibaro.colorController` | Full RGB + color temperature |

### Rooms and zones

| Hue resource | HC3 type | Notes |
|---|---|---|
| Room or Zone | `com.fibaro.colorController` | Controls all lights in the group; supports scenes |

---

## Configuring type overrides

By default, Hue contact sensors become `com.fibaro.doorSensor`. If you have window sensors or garage door sensors you can remap them individually.

Open the **UserConfig** file inside the QuickApp (or edit `userconfig.lua` locally before uploading). Add entries to the `HUE.typeOverrides` table:

```lua
HUE.typeOverrides = {
  ["xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"] = "com.fibaro.windowSensor",
  ["yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"] = "com.fibaro.garageDoorSensor",
}
```

The key is the Hue device UUID — it is the part after the class prefix in the device dropdown value. For example, if the dropdown shows `DoorSensor:a1b2c3d4-...`, the key is `a1b2c3d4-...`.

> **Note:** The override only takes effect when the child device is first **created**. To change the type of an existing child:
> 1. Deselect it in the selector and press **Apply**
> 2. Add the override entry to `userconfig.lua`
> 3. Re-select it and press **Apply**

The `UserConfig` file is **never overwritten by auto-update**.

---

## Room / Zone controller

Room and zone devices (`RoomZoneQA`) give you full control over a Hue group.

### Scene support

Each Room/Zone child has a **Scene** dropdown in its panel. Selecting a scene from the dropdown stores it on the device. The next `turnOn` call will recall that scene automatically.

You can also set the scene programmatically:

```lua
fibaro.call(deviceId, "setScene", sceneId)   -- store scene UUID
fibaro.call(deviceId, "turnOn")              -- recalls stored scene
fibaro.call(deviceId, "turnOn", "Relax")     -- recall by name (one-off, not stored)
```

---

## Available Lua methods per device type

These methods can be called from scenes, automations, and other QuickApps via `fibaro.call(deviceId, "methodName", ...)`.

---

### All sensor types

Sensors are read-only. Their `value` property is updated automatically from Hue SSE events.

| Method | Description |
|---|---|
| _(none)_ | No callable methods — use property triggers in scenes |

**Battery:** Devices with a battery (Hue sensors) automatically report `batteryLevel` and `dead` status.

---

### BinarySwitch — `com.fibaro.binarySwitch`

| Method | Arguments | Description |
|---|---|---|
| `turnOn` | — | Turns the light on |
| `turnOff` | — | Turns the light off |

---

### DimLight — `com.fibaro.multilevelSwitch`

| Method | Arguments | Description |
|---|---|---|
| `turnOn` | — | Turns on at last brightness |
| `turnOff` | — | Turns off |
| `setValue` | `level` (0–100) | Sets brightness |
| `startLevelIncrease` | — | Smooth ramp to 100% |
| `startLevelDecrease` | — | Smooth ramp to 0% |
| `stopLevelChange` | — | Stops any active ramp |

---

### TempLight — `com.fibaro.colorController`

White-ambiance lights (tunable white, no colour).

| Method | Arguments | Description |
|---|---|---|
| `turnOn` | — | Turns on |
| `turnOff` | — | Turns off |
| `setValue` | `level` (0–100) | Sets brightness |
| `setColorTemperature` | `mirek` (153–454) | Sets colour temperature. 153 = 6500 K cool white, 454 = 2200 K warm white |

---

### ColorLight — `com.fibaro.colorController`

Full-colour lights.

| Method | Arguments | Description |
|---|---|---|
| `turnOn` | — | Turns on |
| `turnOff` | — | Turns off |
| `setValue` | `level` (0–100) | Sets brightness |
| `setColor` | `"RRGGBB"` | Sets colour from hex string, e.g. `"FF0000"` for red |
| `setColorComponents` | `{red,green,blue,warmWhite}` | Sets colour by component (0–255 each). RGB triggers colour mode; warmWhite alone triggers colour temperature mode |
| `setColorTemperature` | `mirek` (153–454) | Sets colour temperature |
| `startLevelIncrease` | — | Smooth ramp to 100% |
| `startLevelDecrease` | — | Smooth ramp to 0% |
| `stopLevelChange` | — | Stops any active ramp |
| `signal` | `sig, duration_ms, colors` | Signalling effect (see below) |
| `setEffect` | `effect` | Looping light effect (see below) |
| `setTimedEffect` | `effect, duration_ms` | One-shot timed effect (see below) |

---

### RoomZoneQA — `com.fibaro.colorController`

Controls all lights in a Hue room or zone simultaneously.

| Method | Arguments | Description |
|---|---|---|
| `turnOn` | _(optional scene name)_ | Turns group on, optionally recalling a named scene |
| `turnOff` | — | Turns entire group off |
| `setValue` | `level` (0–100) | Sets group brightness |
| `setColor` | `"RRGGBB"` | Sets group colour from hex string |
| `setColorComponents` | `{red,green,blue,warmWhite}` | Sets group colour by component |
| `setColorTemperature` | `mirek` (153–454) | Sets group colour temperature |
| `startLevelIncrease` | — | Smooth group ramp to 100% |
| `startLevelDecrease` | — | Smooth group ramp to 0% |
| `stopLevelChange` | — | Stops group ramp |
| `setScene` | `sceneId` | Stores a scene UUID to recall on next `turnOn` |
| `signal` | `sig, duration_ms, colors` | Signalling effect on all group lights (see below) |

---

## Light effects reference

### signal — blink / alerting effects

Applies a visual signalling effect to the light or group.

```lua
fibaro.call(deviceId, "signal", sig, duration_ms, colors)
```

| Parameter | Type | Description |
|---|---|---|
| `sig` | string | Effect type (see table below) |
| `duration_ms` | number | Duration 1000–65534000 ms. Default 5000 |
| `colors` | table | Optional array of 1–2 RRGGBB hex strings |

| `sig` value | Colors required | Description |
|---|---|---|
| `"on_off"` | none | Blink between max brightness and off |
| `"on_off_color"` | 1 color | Blink between off and the given color |
| `"alternating"` | 2 colors | Alternate between two colors |
| `"stop"` | none | Cancel any active signal immediately |

**Examples:**
```lua
fibaro.call(id, "signal", "on_off", 5000)
fibaro.call(id, "signal", "on_off_color", 10000, {"FF0000"})
fibaro.call(id, "signal", "alternating", 30000, {"FF0000", "0000FF"})
fibaro.call(id, "signal", "stop")
```

---

### setEffect — continuous looping effect

_Individual lights only (not supported on rooms/zones)._

```lua
fibaro.call(deviceId, "setEffect", effect)
```

| `effect` value | Description |
|---|---|
| `"candle"` | Candle flicker |
| `"fire"` | Fire effect |
| `"prism"` | Prism colour cycle |
| `"sparkle"` | Random sparkle |
| `"opal"` | Opal shimmer |
| `"glisten"` | Glisten |
| `"underwater"` | Underwater wave |
| `"cosmos"` | Cosmos |
| `"sunbeam"` | Sunbeam |
| `"enchant"` | Enchant |
| `"stop"` | Cancel active effect |

---

### setTimedEffect — one-shot timed effect

_Individual lights only (not supported on rooms/zones)._

```lua
fibaro.call(deviceId, "setTimedEffect", effect, duration_ms)
```

| `effect` value | Description |
|---|---|
| `"sunrise"` | Sunrise simulation |
| `"sunset"` | Sunset simulation |
| `"stop"` | Cancel active timed effect |

---

## Updating Yahue

To update to the latest version:

1. Open the QuickApp on the HC3
2. Set the QuickApp Variable `update` to `yes`
3. Save

The QuickApp downloads `dist/Yahue.fqa` from GitHub, installs all files, and restarts. Your `UserConfig` file is **never overwritten** — your type overrides and any other customisations are preserved.

---

## Troubleshooting

**Info label shows "Set Hue_IP variable then restart"**  
The `Hue_IP` QuickApp Variable is empty or not a valid IPv4 address. Set it in the QuickApp settings and restart.

**Info label shows "Set Hue_User, or press 'Pair with bridge'"**  
No application key is stored yet. Either press **Pair with bridge** and follow the prompt, or enter an existing key manually into the `Hue_User` QuickApp Variable.

**Pairing timed out ("Timed out — press Pair and try again")**  
You have 30 seconds to press the physical link button on the bridge after pressing **Pair with bridge**. Press **Pair with bridge** again and try once more.

**Pairing shows an error message**  
The bridge at `Hue_IP` was unreachable. Verify the IP address is correct and that your HC3 can reach the bridge on port 80.

**No devices appear in the dropdown**  
The bridge was unreachable or returned an error. Check the HC3 log for `ERROR` lines from the QuickApp. Confirm the bridge IP is reachable from the HC3.

**A child device shows as dead**  
The corresponding Hue device has gone offline (e.g. bulb removed or powered off). The `dead` property will clear automatically when the device reconnects.

**Changing a contact sensor to windowSensor has no effect**  
The `typeOverrides` setting only applies when the child device is first created. Remove the device from the selection, apply, add the override to `userconfig.lua`, re-add the device, apply again.

**Scene dropdown is empty on a Room/Zone device**  
Scenes are loaded at startup. If you added scenes to the Hue app after the QuickApp started, press **Restart** to reload them.
