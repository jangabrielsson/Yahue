------- userconfig.lua -------
-- This file is NEVER auto-updated. Put all personal Yahue customisations here.
-- It is loaded before devices.lua, so anything set here takes effect at startup.

fibaro.engine = fibaro.engine or {}
local HUE = fibaro.engine

-- ─────────────────────────────────────────────────────────────────────────────
-- typeOverrides — per-device Fibaro type overrides
-- ─────────────────────────────────────────────────────────────────────────────
-- By default, Hue contact sensors become com.fibaro.doorSensor.
-- Use this table to remap individual devices to a different Fibaro type.
--
-- Key:   Hue device UUID — the part after the class prefix in the device
--        dropdown value, e.g. for "DoorSensor:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
--        the key is "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
-- Value: Fibaro device type string.
--
-- The override only takes effect when the child device is CREATED (or re-created
-- after being removed from the selection). To change an existing child:
--   1. Deselect it and press Apply
--   2. Add the entry below
--   3. Re-select it and press Apply
--
-- Common contact-sensor types:
--   "com.fibaro.doorSensor"       (default)
--   "com.fibaro.windowSensor"
--   "com.fibaro.garageDoorSensor"
--
-- Example:
-- HUE.typeOverrides = {
--   ["xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"] = "com.fibaro.windowSensor",
--   ["yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"] = "com.fibaro.garageDoorSensor",
-- }

HUE.typeOverrides = {
}
