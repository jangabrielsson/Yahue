---@diagnostic disable: undefined-global
------- devices.lua ----------
fibaro.debugFlags = fibaro.debugFlags or {}
local HUE

local VERSION = "0.2.1"
local serial = "UPD896661234567893"
fibaro.engine = fibaro.engine or {}
local HUE = fibaro.engine
HUE.typeOverrides = HUE.typeOverrides or {}  -- safety fallback if userconfig.lua is absent
HUE.appName = "YahueV2"
HUE.appVersion = tostring(VERSION)

-- Rounds a number to the nearest integer.
local function ROUND(i) return math.floor(i+0.5) end

-- Reads a single plugin variable from any device by id and key.
-- Returns the value string, or nil if the variable does not exist.
local function getVar(id,key)
  local res, stat = api.get("/plugins/" .. id .. "/variables/" .. key)
  if stat ~= 200 then return nil end
  return res.value
end

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

local defClasses
local classesLoaded = false

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
        children[tag] = {
          name = dev.name,
          type = HUE.typeOverrides[data.id] or (cls and cls.htype) or "com.fibaro.deviceController",
          className = data.class,
          interfaces = dev:getProps()['power_state'] and {'battery'} or nil,
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
  defClasses()

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
    ddevices[tag] = { name=zr.name or tag, id=id, class="RoomZoneQA" }
  end
  for id,zr in pairs(HUE:getResourceType('room')) do
    local tag = "RoomZoneQA:"..id
    ddevices[tag] = { name=zr.name or tag, id=id, class="RoomZoneQA" }
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

function defClasses()
  if classesLoaded then return end
  classesLoaded = true
  print("Defining QA classes")
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- HueClass  (base class for all Hue child devices)
  -- Extends QwikAppChild. Resolves the Hue resource from the UID stored in
  -- self._uid, sets up dead/battery subscriptions, and fills userDescription.
  -- ─────────────────────────────────────────────────────────────────────────
  class 'HueClass'(QwikAppChild)
  -- Initialises the Hue resource binding and common subscriptions.
  function HueClass:__init(dev)
    QwikAppChild.__init(self,dev)
    self.uid = self._uid:match(".-:(.*)")
    self.dev = HUE:getResource(self.uid)
    self.pname = "CHILD"..self.id
    local props = self.dev:getProps()
    self.dev:subscribe("status",function(key,value,b)
      self:print("status %s",value)
      if value ~= 'connected' then
        self:updateProperty("dead",true)
      end
      self:updateProperty("dead",value~='connected')
    end)
    self.dev:subscribe("power_state",function(key,value,b)
      self:print("battery %s",value.battery_level)
      self:updateProperty("batteryLevel",value.battery_level)
    end)
    if self.properties.userDescription == nil or self.properties.userDescription == "" then
      local fmt = string.format
      local d = fmt("%s\n%s",self.dev.type,self.dev.id)
      if self.dev.product_data then
        local pd = self.dev.product_data
        d = d..fmt("\n%s\n%s",pd.product_name or "",pd.model_id or "")
      end
      self:updateProperty("userDescription",d)
    end
  end
  -- Override in subclasses to send raw Hue API commands.
  function HueClass:hueCommand(tab)
  end
  -- Prints a debug line tagged with this child's name instead of the QA name.
  function HueClass:print(fmt,...)
    local TAG = __TAG; __TAG = self.pname
    self:debug(string.format(fmt,...))
    __TAG = TAG
  end
  -- Recalls the Hue scene whose ID is in event.values[1] (from sceneSelect dropdown).
  function HueClass:sceneChanged(event)
    local sceneId = event.values[1]
    if not sceneId or sceneId == '' then return end
    local sc = HUE:getResource(sceneId)
    if sc then
      self:print("Recall scene %s", sc.name)
      sc:recall()
    end
  end
  -- Triggers a signaling effect on the light or group.
  -- sig:        "on_off"        – blink max brightness / off (no color needed)
  --             "on_off_color"  – blink off / color (1 hex color required)
  --             "alternating"   – alternate between 2 colors (2 hex colors required)
  --             "stop"          – cancel any active signal immediately
  -- duration_ms: 1000–65534000 (rounded to nearest second). Default 5000. Ignored for "stop".
  -- colors:     optional list of 1–2 RRGGBB hex strings, e.g. {"FF0000","0000FF"}
  -- Examples:
  --   child:signal("on_off", 5000)                            -- doorbell flash
  --   child:signal("on_off_color", 10000, {"FF0000"})         -- red alert
  --   child:signal("alternating", 30000, {"FF0000","0000FF"}) -- police lights
  --   child:signal("stop")                                    -- cancel
  function HueClass:signal(sig, duration_ms, colors)
    if type(sig) == 'table' then
      local v = sig.values or sig
      sig         = v[1]
      duration_ms = v[2]
      colors      = v[3]
    end
    local svc = rawget(self,'light') or rawget(self,'group')
    if svc and svc.signal then
      svc:signal(sig, duration_ms, colors)
    end
  end
  -- Sets a continuous looping effect on the light.
  -- effect: "fire"|"candle"|"sparkle"|"glisten"|"prism"|"opal"|"underwater"|"cosmos"|"sunbeam"|"enchant"|"stop"
  -- "stop" cancels any active effect. Not supported on room/zone devices.
  -- Example: child:setEffect("fire")  /  child:setEffect("stop")
  function HueClass:setEffect(effect)
    if type(effect) == 'table' then effect = (effect.values or effect)[1] end
    local svc = rawget(self,'light')
    if svc and svc.setEffect then svc:setEffect(effect) end
  end
  -- Plays a one-shot timed effect that ends after duration_ms.
  -- effect:   "sunrise"|"sunset"|"stop"
  -- duration: 1000–21600000 ms (required unless stopping). Ignored for "stop".
  -- Example: child:setTimedEffect("sunrise", 60000)  /  child:setTimedEffect("stop")
  function HueClass:setTimedEffect(effect, duration_ms)
    if type(effect) == 'table' then
      local v = effect.values or effect
      effect, duration_ms = v[1], v[2]
    end
    local svc = rawget(self,'light')
    if svc and svc.setTimedEffect then svc:setTimedEffect(effect, duration_ms) end
  end

  -- Populates the 'sceneSelect' dropdown for a RoomZoneQA child.
  -- Finds all scenes whose group is this room/zone resource directly.
  local function loadScenesForRoom(child)
    local groupId = child.uid
    local options = {{type='option', text='- None -', value=''}}
    for id, sc in pairs(HUE:getResourceType('scene')) do
      if sc.rsrc and sc.rsrc.group and sc.rsrc.group.rid == groupId then
        options[#options+1] = {type='option', text=sc.name, value=id}
      end
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    child:updateView("sceneSelect", "options", options)
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- TemperatureSensor  →  com.fibaro.temperatureSensor
  -- Hue service: temperature. Updates the 'value' property (°C).
  -- ─────────────────────────────────────────────────────────────────────────
  class 'TemperatureSensor'(HueClass)
  TemperatureSensor.htype = "com.fibaro.temperatureSensor"
  function TemperatureSensor:__init(device)
    HueClass.__init(self,device)
    self.dev:subscribe("temperature",function(key,value,b)
      self:print("temperature %s",value)
      self:updateProperty("value",value)
    end)
    self.dev:publishAll()
  end
  function TemperatureSensor.annotate() end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- BinarySwitch  →  com.fibaro.binarySwitch
  -- Hue service: light with on/off only (no dimming, no color).
  -- Drives self.light (the light service resource).
  -- ─────────────────────────────────────────────────────────────────────────
  class 'BinarySwitch'(HueClass)
  BinarySwitch.htype = "com.fibaro.binarySwitch"
  function BinarySwitch:__init(device)
    HueClass.__init(self,device)
    self.light = self.dev:findServiceByType('light')[1] or self.dev
    self.dev:subscribe("on",function(key,value,b)
      self:print("on %s",value)
      self:updateProperty("value",value)
      self:updateProperty("state",value)
    end)
    self.dev:publishAll()
  end
  function BinarySwitch:turnOn()
    self:updateProperty("value",true)
    self:updateProperty("state",true)
    self.light:turnOn()
  end
  function BinarySwitch:turnOff()
    self:updateProperty("value",false)
    self:updateProperty("state",false)
    self.light:turnOff()
  end
  function BinarySwitch.annotate() end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- LuxSensor  →  com.fibaro.lightSensor
  -- Hue service: light (illuminance). Converts Hue lux value to lux (10^((v-1)/10000)).
  -- ─────────────────────────────────────────────────────────────────────────
  class 'LuxSensor'(HueClass)
  LuxSensor.htype = "com.fibaro.lightSensor"
  function LuxSensor:__init(device)
    HueClass.__init(self,device)
    self.dev:subscribe("light",function(key,value,b)
      value = 10 ^ ((value - 1) / 10000)
      self:print("lux %s",value)
      self:updateProperty("value",value)
    end)
    self.dev:publishAll()
  end
  function LuxSensor.annotate() end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- MotionSensor  →  com.fibaro.motionSensor
  -- Hue service: motion. Updates 'value' (true = motion detected).
  -- ─────────────────────────────────────────────────────────────────────────
  class 'MotionSensor'(HueClass)
  MotionSensor.htype = "com.fibaro.motionSensor"
  function MotionSensor:__init(device)
    HueClass.__init(self,device)
    self.dev:subscribe("motion",function(key,value,b)
      self:print("motion %s",value)
      self:updateProperty("value",value)
    end)
    self.dev:publishAll()
  end
  function MotionSensor.annotate() end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- MotionAreaSensor  →  com.fibaro.motionSensor
  -- Hue resource type: motion_area_configuration.
  -- Subscribes to each motion sensor service listed in rsrc.motion_sensors[].
  -- Reports true if ANY of the member sensors currently detects motion (OR logic).
  -- ─────────────────────────────────────────────────────────────────────────
  class 'MotionAreaSensor'(HueClass)
  MotionAreaSensor.htype = "com.fibaro.motionSensor"
  function MotionAreaSensor:__init(device)
    HueClass.__init(self, device)
    local states = {}
    local function refresh()
      local any = false
      for _,v in pairs(states) do any = any or v end
      self:updateProperty("value", any)
    end
    local sensors = self.dev.rsrc and self.dev.rsrc.motion_sensors or {}
    for _, ref in ipairs(sensors) do
      local svc = HUE:getResource(ref.rid)
      if svc then
        states[ref.rid] = false
        svc:subscribe("motion", function(key, value)
          self:print("motion %s from %s", value, ref.rid:sub(1,8))
          states[ref.rid] = value or false
          refresh()
        end)
        svc:publishAll()
      end
    end
  end
  function MotionAreaSensor.annotate() end

  -- ─────────────────────────────────────────────────────────────────────────
  -- Button  →  com.fibaro.remoteController
  -- Hue service: button. Translates Hue button events to HC3 centralSceneEvents.
  -- Supports multi-click (Pressed2, Pressed3) via a 1.5 s debounce window.
  -- annotate() adds centralSceneSupport for 4 keys.
  -- ─────────────────────────────────────────────────────────────────────────
  local btnMap = {
    initial_press="Pressed",
    ['rep'..'eat']="HeldDown",
    short_release="Released",
    long_release="Released"
  }
  class 'Button'(HueClass)
  Button.htype = 'com.fibaro.remoteController'
  function Button:__init(device)
    HueClass.__init(self,device)
    local deviceId,ignore = self.id,false
    local btnSelf = self
    local buttons = {}
    self.dev:subscribe("button",function(key,value,b)
      local _modifier,key = b:button_state()
      b._props.button.set(b.rsrc,"_")
      local modifier = btnMap[_modifier] or _modifier
      local function action(r)
        btnSelf:print("button:%s %s %s",key,modifier,_modifier)
        local data = {
          type =  "centralSceneEvent",
          source = deviceId,
          data = { keyAttribute = modifier, keyId = key }
        }
        if not ignore then api.post("/plugins/publishEvent", data) end
        btnSelf:updateProperty("log",string.format("Key:%s,Attr:%s",key,modifier))
        if r and not ignore then
          btnSelf:print("button:%s %s",key,"Released")
          data.data.keyAttribute = "Released"
          api.post("/plugins/publishEvent", data)
          btnSelf:updateProperty("log",string.format("Key:%s,Attr:%s",key,"Released"))
        end
      end
      if modifier == 'Pressed' then
        local bd = buttons[key] or {click=0}; buttons[key] = bd
        if bd.ref then clearTimeout(bd.ref) end
        bd.click = bd.click + 1
        bd.ref = setTimeout(function()
          buttons[key] = nil
          if bd.click > 1 then modifier = modifier..bd.click end
          action(true)
        end,1500)
      elseif modifier == 'Released' then
      else action() end
    end)
    ignore = true
    self.dev:publishAll()
    ignore = false
  end
  function Button.annotate(child)
    child.properties = child.properties or {}
    child.properties.centralSceneSupport = {
      { keyAttributes = {"Pressed","Released","HeldDown","Pressed2","Pressed3"},keyId = 1 },
      { keyAttributes = {"Pressed","Released","HeldDown","Pressed2","Pressed3"},keyId = 2 },
      { keyAttributes = {"Pressed","Released","HeldDown","Pressed2","Pressed3"},keyId = 3 },
      { keyAttributes = {"Pressed","Released","HeldDown","Pressed2","Pressed3"},keyId = 4 },
    }
    child.interfaces = child.interfaces or {}
    table.insert(child.interfaces,"zwaveCentralScene")
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- DoorSensor  →  com.fibaro.doorSensor
  -- Hue service: contact_report. 'value' = true when open (not 'contact').
  -- ─────────────────────────────────────────────────────────────────────────
  class 'DoorSensor'(HueClass)
  DoorSensor.htype = "com.fibaro.doorSensor"
  function DoorSensor:__init(device)
    HueClass.__init(self,device)
    self.dev:subscribe("contact_report",function(key,value,b)
      value = not(value=='contact')
      self:print("contact %s",value)
      self:updateProperty("value",value)
    end)
    self.dev:publishAll()
  end
  function DoorSensor.annotate() end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- MultilevelSensor  →  com.fibaro.multilevelSensor
  -- Hue service: relative_rotary (e.g. Hue Tap Dial).
  -- Accumulates rotary steps into a 0-100 value; self.div can scale step size.
  -- ─────────────────────────────────────────────────────────────────────────
  class 'MultilevelSensor'(HueClass)
  MultilevelSensor.htype = "com.fibaro.multilevelSensor"
  function MultilevelSensor:__init(device)
    HueClass.__init(self,device)
    self.div = 1
    self.value = 0
    self.rotaryMode = (self:getVariable("rotaryMode") or "absolute"):lower()
    self.rotaryStopMs = tonumber(self:getVariable("rotaryStopMs")) or 400
    if self.rotaryStopMs < 100 then self.rotaryStopMs = 100 end
    self.rotaryStopRef = nil
    self.rotaryMoving = false
    self.rotaryEventEnsured = {}
    self.rotaryEventsReady = false

    local function ensureRotaryEvents()
      if self.rotaryEventsReady then return end
      local suffix = tostring(self.id)
      for _,prefix in ipairs({"left","right","stop"}) do
        local eventName = prefix .. suffix
        pcall(api.post, "/customEvents", { name = eventName, userDescription = "Yahue rotary event" })
        self.rotaryEventEnsured[eventName] = true
      end
      self.rotaryEventsReady = true
    end

    if self.rotaryMode == "relative" or self.rotaryMode == "relativeevent" or self.rotaryMode == "event" then
      ensureRotaryEvents()
    end

    local function emitRotaryEvent(prefix)
      local eventName = prefix .. self.id
      ensureRotaryEvents()
      local ok = pcall(fibaro.emitCustomEvent, eventName)
      if ok then return end
      pcall(fibaro.emitCustomEvent, eventName)
    end

    local function armStopEvent()
      if self.rotaryStopRef then clearTimeout(self.rotaryStopRef) end
      self.rotaryMoving = true
      self.rotaryStopRef = setTimeout(function()
        self.rotaryStopRef = nil
        if self.rotaryMoving then
          self.rotaryMoving = false
          emitRotaryEvent("stop")
        end
      end, self.rotaryStopMs)
    end

    self.dev:subscribe("relative_rotary",function(key,v,b)
      if not v then return end
      local steps = math.max(ROUND(v.rotation.steps / self.div),1)
      local dir = (1 - (v.rotation.direction=='clock_wise' and 0 or 2))

      if self.rotaryMode == "relative" or self.rotaryMode == "relativeevent" or self.rotaryMode == "event" then
        emitRotaryEvent(dir > 0 and "right" or "left")
        armStopEvent()
      end

      self.value = self.value + steps*dir
      if self.value < 0 then self.value = 0 end
      if self.value > 100 then self.value = 100 end
      self:print("rotary %s",self.value)
      self:updateProperty("value",self.value)
    end)
    self.dev:publishAll()
  end
  function MultilevelSensor.annotate(rsrc)
  end

  -- ─────────────────────────────────────────────────────────────────────────
  -- DimLight  →  com.fibaro.multilevelSwitch
  -- Hue service: light with on + dimming (no color, no color_temperature).
  -- setValue(0-100) sets brightness via light:setDim().
  -- annotate() adds the levelChange interface.
  -- ─────────────────────────────────────────────────────────────────────────
  class 'DimLight'(HueClass)
  DimLight.htype = "com.fibaro.multilevelSwitch"
  function DimLight:__init(device)
    HueClass.__init(self,device)
    self.light = self.dev:findServiceByType('light')[1] or self.dev
    self.dev:subscribe("on",function(key,value,b)
      self:print("on %s",value)
      local d = b._props.dimming and ROUND(b._props.dimming.get(b.rsrc)) or 0
      self:updateProperty("state",value)
      self:updateProperty("value",value and d or 0)
    end)
    self.dev:subscribe("dimming",function(key,value,b)
      self:print("dimming %s",value)
      self:updateProperty("value",ROUND(value))
    end)
    self.dev:publishAll()
  end
  function DimLight:turnOn()
    self:updateProperty("state",true)
    self.light:turnOn()
  end
  function DimLight:turnOff()
    self:updateProperty("state",false)
    self:updateProperty("value",0)
    self.light:turnOff()
  end
  function DimLight:setValue(value)
    if type(value)=='table' then value = value.values[1] end
    value = tonumber(value)
    self:updateProperty("value",value)
    self.light:setDim(value)
  end
  function DimLight.annotate(rsrc)
    rsrc.interfaces = rsrc.interfaces or {}
    table.insert(rsrc.interfaces,"levelChange")
  end

  -- ─────────────────────────────────────────────────────────────────────────
  -- TempLight  →  com.fibaro.colorController
  -- Hue service: light with on + dimming + color_temperature (no xy color).
  -- setColorTemperature() sets Hue color_temperature (mirek) via light:setTemperature().
  -- ─────────────────────────────────────────────────────────────────────────
  class 'TempLight'(HueClass)
  TempLight.htype = "com.fibaro.colorController"
  function TempLight:__init(device)
    HueClass.__init(self,device)
    self.light = self.dev:findServiceByType('light')[1] or self.dev
    self.dev:subscribe("on",function(key,value,b)
      self:print("on %s",value)
      self:updateProperty("state",value)
      if not value then self:updateProperty("value",0) end
    end)
    self.dev:subscribe("dimming",function(key,value,b)
      self:print("dimming %s",value)
      self:updateProperty("value",ROUND(value))
      if value > 0 then self:updateProperty("state",true) end
    end)
    self.dev:subscribe("color_temperature",function(key,value,b)
      self:print("color_temperature %s",value)
      self:updateProperty("colorTemperature",value)
    end)
    self.dev:publishAll()
  end
  function TempLight:turnOn()
    self:updateProperty("state",true)
    self.light:turnOn()
  end
  function TempLight:turnOff()
    self:updateProperty("state",false)
    self:updateProperty("value",0)
    self.light:turnOff()
  end
  function TempLight:setValue(value)
    if type(value)=='table' then value = value.values[1] end
    value = tonumber(value)
    self:updateProperty("value",value)
    self.light:setDim(value)
  end
  function TempLight:setColorTemperature(value)
    if type(value)=='table' then value = value.values[1] end
    self.light:setTemperature(tonumber(value))
  end
  function TempLight.annotate(rsrc)
    rsrc.interfaces = rsrc.interfaces or {}
    table.insert(rsrc.interfaces,"levelChange")
  end

  -- ─────────────────────────────────────────────────────────────────────────
  -- ColorLight  →  com.fibaro.colorController
  -- Hue service: light with on + dimming + color (xy) [+ optional color_temperature].
  -- setColor("RRGGBB") converts RGB to CIE xy via HUE:rgbToXy() and sends to Hue.
  -- annotate() adds the color interface.
  -- ─────────────────────────────────────────────────────────────────────────
  class 'ColorLight'(HueClass)
  ColorLight.htype = "com.fibaro.colorController"
  function ColorLight:__init(device)
    HueClass.__init(self,device)
    self.dimdelay = tonumber(self:getVariable("dimdelay")) or 8000
    self.light = self.dev:findServiceByType('light')[1] or self.dev
    self.dev:subscribe("on",function(key,value,b)
      self:print("on %s",value)
      self:updateProperty("state",value)
      if not value then self:updateProperty("value",0) end
    end)
    self.dev:subscribe("dimming",function(key,value,b)
      self:print("dimming %s",value)
      self:updateProperty("value",ROUND(value))
      if value > 0 then self:updateProperty("state",true) end
    end)
    self.dev:subscribe("color",function(key,value,b)
      if value.xy then
        local r,g,b0 = HUE:xyToRgb(value.xy.x,value.xy.y,value.brightness or 100)
        self:print("color xy %s,%s,%s",r,g,b0)
        self:updateProperty("color",string.format("%02X%02X%02X",r,g,b0))
        self:updateProperty("colorComponents",{red=r,green=g,blue=b0,white=0})
      end
    end)
    self.dev:subscribe("color_temperature",function(key,value,b)
      self:print("color_temperature %s",value)
      self:updateProperty("colorTemperature",value)
    end)
    self.dev:publishAll()
  end
  function ColorLight:turnOn()
    self:updateProperty("state",true)
    self.light:turnOn()
  end
  function ColorLight:turnOff()
    self:print("Turn off")
    self:updateProperty("value",0)
    self:updateProperty("state",false)
    self.light:turnOff()
  end
  function ColorLight:setValue(value)
    if type(value)=='table' then value = value.values[1] end
    value = tonumber(value)
    self:updateProperty("value",value)
    self.light:setDim(value)
  end
  function ColorLight:startLevelIncrease()
    self:print("startLevelIncrease")
    local val = self.properties.value
    val = ROUND((100-val)/100.0*self.dimdelay)
    self.light:setDim(100,val)
  end
  function ColorLight:startLevelDecrease()
    self:print("startLevelDecrease")
    local val = self.properties.value
    val = ROUND((val-0)/100.0*self.dimdelay)
    self.light:setDim(0,val)
  end
  function ColorLight:stopLevelChange()
    self.light:setDim(-1)
  end
  function ColorLight:setColor(value)
    if type(value)=='table' then value = value.values[1] end
    local r = tonumber(value:sub(1,2),16)
    local g = tonumber(value:sub(3,4),16)
    local b = tonumber(value:sub(5,6),16)
    self:print("setColor %s,%s,%s",r,g,b)
    local x,y = HUE:rgbToXy(r,g,b)
    self.light:sendCmd({color={xy={x=x,y=y}}})
    self:updateProperty("color",string.format("%02X%02X%02X",r,g,b))
    self:updateProperty("colorComponents",{red=r,green=g,blue=b,warmWhite=0})
  end
  function ColorLight:setColorComponents(value)
    if type(value)=='table' and value.values then value = value.values[1] end
    local cur = self.properties.colorComponents or {red=0,green=0,blue=0,warmWhite=0}
    local r = tonumber(value.red)       or cur.red       or 0
    local g = tonumber(value.green)     or cur.green     or 0
    local b = tonumber(value.blue)      or cur.blue      or 0
    local w = tonumber(value.warmWhite) or cur.warmWhite or 0
    self:print("setColorComponents r=%s g=%s b=%s w=%s",r,g,b,w)
    local hasRGB = value.red ~= nil or value.green ~= nil or value.blue ~= nil
    if hasRGB then
      local x,y = HUE:rgbToXy(r,g,b)
      self.light:sendCmd({color={xy={x=x,y=y}}})
      self:updateProperty("color",string.format("%02X%02X%02X",r,g,b))
    elseif value.warmWhite ~= nil then
      -- Map warmWhite 0-255 to mirek range 153 (6500K cool) to 454 (2200K warm)
      local mirek = math.floor(153 + (w/255)*(454-153))
      self.light:sendCmd({color_temperature={mirek=mirek}})
      self:updateProperty("colorTemperature",mirek)
    end
    self:updateProperty("colorComponents",{red=r,green=g,blue=b,warmWhite=w})
  end
  function ColorLight.annotate(rsrc)
    rsrc.interfaces = rsrc.interfaces or {}
    table.insert(rsrc.interfaces,"ringColor")
    table.insert(rsrc.interfaces,"colorTemperature")
    table.insert(rsrc.interfaces,"levelChange")
    rsrc.properties = rsrc.properties or {}
    rsrc.properties.colorComponents = {red=0,green=0,blue=0,warmWhite=0}
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- RoomZoneQA  →  com.fibaro.multilevelSwitch
  -- Hue resource type: room or zone.
  -- Controls all lights in the group via group:targetCmd().
  -- Tracks per-device connectivity and marks child dead when all members offline.
  -- turnOn() optionally recalls a named Hue scene (setScene/getVar("scene")).
  -- Supports dimming ramp via startLevelIncrease/startLevelDecrease/stopLevelChange.
  -- annotate() adds the levelChange interface.
  -- ─────────────────────────────────────────────────────────────────────────
  class 'RoomZoneQA'(HueClass)
  RoomZoneQA.htype = "com.fibaro.colorController"
  function RoomZoneQA:__init(device)
    HueClass.__init(self,device)
    self.dimdelay = tonumber(self:getVariable("dimdelay")) or 8000
    self.group = self.dev:findServiceByType('grouped_light')[1] or self.dev
    
    -- Check room/zone dead status
    local statuses = {}
    local devsons = {}
    for _,c in pairs(self.dev.children or {}) do
      c = HUE:_resolve(c)
      if c.type ~= 'device' then
        c = HUE:_resolve(c.owner)
      end
      local props = c:getProps()
      --if props.status then
      statuses[c.id] = true
      c = HUE:getResource(c.id)
      c:subscribe("status",function(key,value,b)
        statuses[b.id] = value == 'connected'
        local stat = true
        for _,s in pairs(statuses) do stat=stat and s end
        local oldDead = fibaro.getValue(self.id,'dead')
        self:updateProperty("dead",not stat)
        local state = fibaro.getValue(self.id,'state')
        local value = fibaro.getValue(self.id,'value')
        if (not stat) ~= oldDead then -- change in dead state
           if not stat then -- Now dead
              self.deadStatus = {state,value}
              self:updateProperty('state',false)
              self:updateProperty('value',0)
           else -- Now living
              if self.deadStatus then
                self:updateProperty('state',self.deadStatus[1])
                self:updateProperty('value',self.deadStatus[2])
              end
           end
        end
        self:print("status %s",stat)
      end)
      c:subscribe("on",function(key,value,b)
        devsons[b.id] = value
        print("c on",value,b.id)
        for _,s in pairs(devsons) do
          --
        end
      end)
      local c0 = c
      setTimeout(function()
        c0:publishAll()
      end,0)
      --end
    end
    
    self.dev:subscribe("on",function(key,value,b)
      self:print("on %s",value)
      local d = b._props.dimming and ROUND(b._props.dimming.get(b.rsrc)) or 0
      self:updateProperty("state",value)
      self:updateProperty("value",value and d or 0)
    end)
    
    self.dev:subscribe("dimming",function(key,value,b)
      self:print("dimming %s",value)
      self:updateProperty("value",ROUND(value))
    end)
    
    self.dev:subscribe("color",function(key,value,_)
      if not value or not value.x then return end
      local r,g,b0 = HUE:xyToRgb(value.x,value.y,100)
      self:print("color xy %s,%s,%s",r,g,b0)
      self:updateProperty("color",string.format("%02X%02X%02X",r,g,b0))
      self:updateProperty("colorComponents",{red=r,green=g,blue=b0,warmWhite=0})
    end)
    
    self.dev:subscribe("color_temperature",function(key,value,b)
      if not value then return end
      self:print("color_temperature %s",value)
      self:updateProperty("colorTemperature",value)
    end)
    
    self.dev:publishAll()
    loadScenesForRoom(self)
  end
  
  -- Stores a Hue scene name in the QA variable 'scene' for use by turnOn().
  function RoomZoneQA:setScene(event)
    self:setVariable("scene",event)
  end
  -- Turns the group on. If a scene name is provided (or stored via setScene),
  -- recalls that scene; otherwise sends a plain on command to the group.
  function RoomZoneQA:turnOn(sceneArg)
    self:updateProperty("value", 100)
    self:updateProperty("state", true)
    local sceneName = type(sceneArg)=='string' and sceneArg or self:getVar("scene")
    local scene = HUE:getSceneByName(sceneName,self.dev.name)
    if sceneName and not scene then self:print("Scene %s not found",sceneName) end
    if not scene then
      self.group:turnOn()
    else
      self:print("Turn on Scene %s",scene.name)
      scene:recall()
    end
  end
  -- Turns the entire group off.
  function RoomZoneQA:turnOff()
    self:print("Turn off")
    self:updateProperty("value", 0)
    self:updateProperty("state", false)
    self.group:turnOff()
  end
  -- Sets group brightness (0-100).
  function RoomZoneQA:setValue(value)
    if type(value)=='table' then value = value.values[1] end
    value = tonumber(value)
    self:print("setValue")
    self:updateProperty("value", value)
    self.group:setDim(value)
  end
  -- Starts a smooth ramp up to 100% over self.dimdelay ms (default 8 s).
  function RoomZoneQA:startLevelIncrease()
    self:print("startLevelIncrease")
    local val = self.properties.value
    val = ROUND((100-val)/100.0*self.dimdelay)
    self.group:setDim(100,val)
  end
  function RoomZoneQA:startLevelDecrease()
    self:print("startLevelDecrease")
    local val = self.properties.value
    val = ROUND((val-0)/100.0*self.dimdelay)
    self.group:setDim(0,val)
  end
  function RoomZoneQA:stopLevelChange()
    self.group:setDim(-1)
  end
  -- Sets color temperature in mirek.
  function RoomZoneQA:setColorTemperature(value)
    if type(value)=='table' then value = value.values[1] end
    self.group:setTemperature(tonumber(value))
  end
  -- Sets color from RRGGBB hex string.
  function RoomZoneQA:setColor(value)
    if type(value)=='table' then value = value.values[1] end
    local r = tonumber(value:sub(1,2),16)
    local g = tonumber(value:sub(3,4),16)
    local b = tonumber(value:sub(5,6),16)
    self:print("setColor %s,%s,%s",r,g,b)
    if not (self.group.rsrc and self.group.rsrc.color) then
      self:print("setColor ignored – group does not support color (CT-only lights)")
      return
    end
    local x,y = HUE:rgbToXy(r,g,b)
    self.group:rawCmd({color={xy={x=x,y=y}}})
    self:updateProperty("color",string.format("%02X%02X%02X",r,g,b))
    self:updateProperty("colorComponents",{red=r,green=g,blue=b,warmWhite=0})
  end
  -- Sets color from a colorComponents table {red,green,blue,warmWhite}.
  function RoomZoneQA:setColorComponents(value)
    if type(value)=='table' and value.values then value = value.values[1] end
    local cur = self.properties.colorComponents or {red=0,green=0,blue=0,warmWhite=0}
    local r = tonumber(value.red)       or cur.red       or 0
    local g = tonumber(value.green)     or cur.green     or 0
    local b = tonumber(value.blue)      or cur.blue      or 0
    local w = tonumber(value.warmWhite) or cur.warmWhite or 0
    self:print("setColorComponents r=%s g=%s b=%s w=%s",r,g,b,w)
    local hasRGB = value.red ~= nil or value.green ~= nil or value.blue ~= nil
    if hasRGB and (self.group.rsrc and self.group.rsrc.color) then
      local x,y = HUE:rgbToXy(r,g,b)
      self.group:rawCmd({color={xy={x=x,y=y}}})
      self:updateProperty("color",string.format("%02X%02X%02X",r,g,b))
    elseif value.warmWhite ~= nil then
      local mirek = math.floor(153 + (w/255)*(454-153))
      self.group:rawCmd({color_temperature={mirek=mirek}})
      self:updateProperty("colorTemperature",mirek)
    end
    self:updateProperty("colorComponents",{red=r,green=g,blue=b,warmWhite=w})
  end
  -- Reads a QA variable from this child device by name. Returns nil if not found.
  function RoomZoneQA:getVar(name)
    local qvs = __fibaro_get_device_property(self.id,"quickAppVariables").value
    for _,var in ipairs(qvs or {}) do
      if var.name==name then return var.value end
    end
    return nil
  end
  function RoomZoneQA.annotate(rsrc)
    rsrc.interfaces = rsrc.interfaces or {}
    table.insert(rsrc.interfaces,"levelChange")
    table.insert(rsrc.interfaces,"ringColor")
    table.insert(rsrc.interfaces,"colorTemperature")
    rsrc.properties = rsrc.properties or {}
    rsrc.properties.colorComponents = {red=0,green=0,blue=0,warmWhite=0}
    rsrc.UI = rsrc.UI or {}
    table.insert(rsrc.UI, {select='sceneSelect', text='Scene', value='', onToggled='sceneChanged', options={}})
  end
  
end