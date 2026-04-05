--%%name:Yahue
--%%type:com.fibaro.deviceController
--%%uid:UPD896846032517896
--%%save:dist/Yahue.fqa
--%%var:Hue_IP=config.Hue_ip
--%%var:Hue_User=config.Hue_user
--%%file:engine.lua,Engine
--%%file:$fibaro.lib.qwikchild,qwickchild
--%%file:devices.lua,App
--%%file:utils.lua,Utils
--%%u:{label='info', text=''}
--%%u:{label='huedevs', text='Hue devices found:'}
--%%u:{multi='devSelect', text='Devices', values={}, options={}, onToggled='devSelChanged'}
--%%u:{{button='pairHue', text='Pair with bridge', onReleased='pairHue'},{button='restart', text='Restart', onReleased='restart'}}
--%%u:{{button='dump', text='Dump', onReleased='dumpResources'},{button='applyDevices', text='Apply selection', onReleased='applyDevices'}}

-- %%desktop:true
-- %%offline:true
-- %%proxy:true

-- Hue resource kind → Fibaro QA type mapping
-- ┌─────────────────────┬──────────────────────────────────┬────────────────────────────────────────────┐
-- │ Class               │ Fibaro type                      │ Hue resource / service condition           │
-- ├─────────────────────┼──────────────────────────────────┼────────────────────────────────────────────┤
-- │ TemperatureSensor   │ com.fibaro.temperatureSensor     │ device with 'temperature' service          │
-- │ LuxSensor           │ com.fibaro.lightSensor           │ device with 'light' service                │
-- │ MotionSensor        │ com.fibaro.motionSensor          │ device with 'motion' service               │
-- │ DoorSensor          │ com.fibaro.doorSensor            │ device with 'contact_report' service       │
-- │ Button              │ com.fibaro.remoteController      │ device with 'button' service               │
-- │ MultilevelSensor    │ com.fibaro.multilevelSensor      │ device with 'relative_rotary' service      │
-- │ BinarySwitch        │ com.fibaro.binarySwitch          │ light: on only (no dimming, no color)      │
-- │ DimLight            │ com.fibaro.multilevelSwitch      │ light: on + dimming (no color/color_temp)  │
-- │ TempLight           │ com.fibaro.colorController       │ light: on + dimming + color_temperature    │
-- │ ColorLight          │ com.fibaro.colorController       │ light: on + dimming + color (xy)           │
-- │ RoomZoneQA          │ com.fibaro.multilevelSwitch      │ room or zone resource                      │
-- └─────────────────────┴──────────────────────────────────┴────────────────────────────────────────────┘

fibaro.debugFlags = fibaro.debugFlags or {}
local HUE

local function isEngineReady(engine)
  return type(engine) == "table"
    and type(engine.init) == "function"
    and type(engine.app) == "function"
    and type(engine.appName) == "string"
    and type(engine.appVersion) == "string"
end

local function init()
  local self = quickApp
  if not isEngineReady(HUE) then
    self:updateView("info","text","Missing engine files")
    return
  end
  self:debug(HUE.appName,HUE.appVersion)
  self:updateView("info","text",HUE.appName.." v"..HUE.appVersion)

  fibaro.debugFlags.info=true
  --fibaro.debugFlags.class=true
  fibaro.debugFlags.event=true
  fibaro.debugFlags.call=true
  local ip,key = self:getVariable("Hue_IP"),self:getVariable("Hue_User")
  ip = ip:match("(%d+.%d+.%d+.%d+)")
  key = key:match("(.+)")
  if not ip then
    self:updateView("info","text","Set Hue_IP variable then restart")
    return
  end
  if not key then
    self:updateView("info","text","Set Hue_User, or press 'Pair with bridge'")
    return
  end

  HUE:init(ip,key,function()
    HUE:app()
    end)
end

function QuickApp:onInit()
  quickApp = self
  pcall(require, "include.UserConfig")
  HUE = fibaro.engine
  if isEngineReady(HUE) then 
    init()
  else 
    self:updateView("info","text","Missing engine files")
  end
  -- setTimeout(function() -- test signal
  --   print("Start signal for 5sec")
  --   fibaro.call(4222, "signal", "alternating", 30000, {"FF0000","0000FF"}) 
  -- end,5000)
end

function QuickApp:restart() plugin.restart() end
function QuickApp:dumpResources()
  if isEngineReady(HUE) and HUE.listAllDevicesGrouped then HUE:listAllDevicesGrouped() end
end
function QuickApp:devSelChanged(event)
  self.hueSelection = event.values[1]
end
function QuickApp:applyDevices()
  if not isEngineReady(HUE) then self:error("HUE not ready") return end
  HUE:applySelection(self.hueSelection or {})
end

function QuickApp:pairHue()
  local ip = self:getVariable("Hue_IP")
  ip = ip:match("(%d+.%d+.%d+.%d+)")
  if not ip then
    self:updateView("info","text","Set Hue_IP first, then press Pair")
    return
  end
  self:updateView("info","text","Press the button on your Hue bridge now…")
  local url = "http://"..ip.."/api"
  local body = json.encode({devicetype="yahue#hc3"})
  local tries = 0
  local maxTries = 15
  local function poll()
    tries = tries + 1
    net.HTTPClient():request(url, {
      options = { method='POST', headers={['Content-Type']='application/json'}, data=body,
                  checkCertificate=false, timeout=5000 },
      success = function(resp)
        local result = json.decode(resp.data)
        if result and result[1] and result[1].success and result[1].success.username then
          local key = result[1].success.username
          self:setVariable("Hue_User", key)
          self:updateView("info","text","Paired! Restarting\xe2\x80\xa6")
          setTimeout(function() plugin.restart() end, 3000)
        elseif tries < maxTries then
          setTimeout(poll, 2000)
        else
          self:updateView("info","text","Timed out — press Pair and try again")
        end
      end,
      error = function(err)
        self:updateView("info","text","Pair error: "..tostring(err))
      end
    })
  end
  poll()
end
