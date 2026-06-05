-- hue-app.lua — Device discovery and child device orchestration
-- Extracted from devices.lua. Runs after engine startup completes.
-- Uses the HUE public API (getResource, getResourceType) which is set up by hue-startup.lua.

fibaro.engine = fibaro.engine or {}
local HUE = fibaro.engine

-- Rounds a number to the nearest integer.
local function ROUND(i) return math.floor(i+0.5) end

local devProps = {
  temperature   = "TemperatureSensor",
  relative_rotary = "MultilevelSensor",
  button        = "Button",
  light         = "LuxSensor",
  contact_report = "DoorSensor",
  motion        = "MotionSensor",
  [function(p) return p.on and not p.dimming and not p.color and not p.color_temperature and 'on' end] = "BinarySwitch",
  [function(p) return p.on and p.dimming and not p.color and not p.color_temperature and 'dimming' end] = "DimLight",
  [function(p) return p.on and p.dimming and p.color_temperature and not p.color and 'templight' end] = "TempLight",
  [function(p) return p.on and p.dimming and p.color and 'color' end] = "ColorLight",
}

-- Inspects a Hue room/zone resource and picks the QA class to use based on
-- the capabilities of its grouped_light service:
--   color present                              -> RoomZoneQA       (colorController)
--   color_temperature present (no color)       -> RoomZoneQA       (colorController, CT only)
--   dimming present (no color, no CT)          -> RoomZoneDimQA    (multilevelSwitch)
--   none of the above                          -> RoomZoneSwitchQA (binarySwitch)
local function pickRoomZoneClass(roomId)
  local res = HUE:getResource(roomId)
  if not res then return "RoomZoneQA" end
  local gsvc = res.findServiceByType and res:findServiceByType('grouped_light')[1]
  local r = gsvc and gsvc.rsrc
  if not r then return "RoomZoneQA" end
  if r.color then return "RoomZoneQA" end
  if r.color_temperature then return "RoomZoneQA" end
  if r.dimming then return "RoomZoneDimQA" end
  return "RoomZoneSwitchQA"
end

-- Builds the children descriptor table expected by initChildren/loadExistingChildren.
-- ddevices: map of tag → {name, id, class} from HUE:app() discovery.
-- tags: list of UID strings ("ClassName:hue-uuid") that should exist as children.
-- Returns a table keyed by UID with {name, type, className, interfaces, ...}.
local function buildChildren(ddevices, tags)
  local children = {}
  for _,tag in ipairs(tags) do
    local data = ddevices[tag]
    if data then
      local dev = HUE:getResource(data.id)
      if dev then
        local cls = _G[data.class]
        local uiVer
        if cls then
          local ok, v = pcall(function() return cls.uiVersion end)
          if ok then uiVer = v end
        end
        children[tag] = {
          name = dev.name,
          type = HUE.typeOverrides[data.id] or (cls and cls.htype) or "com.fibaro.deviceController",
          className = data.class,
          interfaces = dev:getProps()['power_state'] and {'battery'} or nil,
          uiVersion = uiVer,
        }
        if cls and cls.annotate then cls.annotate(children[tag]) end
      end
    end
  end
  return children
end

-- Main startup entry point called after the Hue engine has connected.
-- Orchestrates the full startup sequence:
--   1. Reads persisted mapped UIDs from internalStorage.
--   2. Discovers all relevant Hue resources.
--   3. Calls initChildren to sync HC3 children with the stored list.
--   4. Populates the device-select dropdown with mapped UIDs pre-checked.
function HUE:app()
  HUE:defClasses()

  -- Step 1: Read stored mapped UIDs (persistent across restarts)
  local mappedUids = quickApp:internalStorageGet("mappedUids") or {}

  -- Step 2: Discover all relevant Hue resources
  local ddevices = {}
  local props, ok
  for id,_ in pairs(HUE:getResourceType('device')) do
    local dev = HUE:getResource(id)
    props = dev:getProps()
    for p,cls in pairs(devProps) do
      if type(p) == 'function' then ok = p(props)
      else ok = props[p] and p end
      if ok then
        local tag = cls..":"..id
        ddevices[tag] = { name=dev.name, id=id, class=cls }
      end
    end
  end
  for id,zr in pairs(HUE:getResourceType('zone')) do
    local tag = "RoomZoneQA:"..id
    ddevices[tag] = { name=zr.name or tag, id=id, class=pickRoomZoneClass(id) }
  end
  for id,zr in pairs(HUE:getResourceType('room')) do
    local tag = "RoomZoneQA:"..id
    ddevices[tag] = { name=zr.name or tag, id=id, class=pickRoomZoneClass(id) }
  end
  for id,_ in pairs(HUE:getResourceType('motion_area_configuration')) do
    local dev = HUE:getResource(id)
    local tag = "MotionAreaSensor:"..id
    ddevices[tag] = { name=dev:getName("MotionArea-"..id:sub(1,8)), id=id, class="MotionAreaSensor" }
  end
  HUE._ddevices = ddevices

  -- Step 3+4: Sync children — skip any stored UIDs whose Hue resource no longer exists
  local validMapped = {}
  for _,uid in ipairs(mappedUids) do
    if ddevices[uid] then validMapped[#validMapped+1] = uid end
  end
  quickApp:initChildren(buildChildren(ddevices, validMapped))

  -- Step 5: Build dropdown; mapped UIDs are pre-checked
  local sorted = {}
  for tag,d in pairs(ddevices) do sorted[#sorted+1] = {tag=tag, d=d} end
  table.sort(sorted, function(a,b)
    return a.d.name < b.d.name or (a.d.name==b.d.name and a.tag < b.tag)
  end)
  local options = {}
  for _,item in ipairs(sorted) do
    local short = item.d.class:gsub("QA",""):gsub("Sensor","Snsr")
    options[#options+1] = {type='option', text=item.d.name..' ['..short..']', value=item.tag}
  end
  quickApp:updateView("devSelect","options",options)
  quickApp:updateView("devSelect","selectedItems",validMapped)
  quickApp.hueSelection = validMapped
end

-- Called when the user presses "Apply selection".
-- Persists the new tag list to internalStorage and restarts the QA.
-- On restart, HUE:app() will call initChildren to create/remove children.
-- tags: list of UID strings currently selected in the dropdown.
function HUE:applySelection(tags)
  quickApp:internalStorageSet("mappedUids", tags)
  plugin.restart()
end
