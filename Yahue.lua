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
--%%u:{multi='devSelect', text='Devices', values={}, options={}, onToggled='devSelChanged'}
--%%u:{button='restart', text='Restart', onReleased='restart'}
--%%u:{{button='dump', text='Dump', onReleased='dumpResources'},{button='applyDevices', text='Apply selection', onReleased='applyDevices'}}

-- %%desktop:true
-- %%offline:true
--%%proxy:true

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
local HUE,update

local function init()
  local self = quickApp
  self:debug(HUE.appName,HUE.appVersion)
  self:updateView("info","text",HUE.appName.." v"..HUE.appVersion)

  fibaro.debugFlags.info=true
  --fibaro.debugFlags.class=true
  fibaro.debugFlags.event=true
  fibaro.debugFlags.call=true
  local ip,key = self:getVariable("Hue_IP"),self:getVariable("Hue_User")
  ip = ip:match("(%d+.%d+.%d+.%d+)")
  key = key:match("(.+)")
  assert(ip,"Missing Hue_IP - hub IP address")
  assert(key,"Missing Hue_User - Hue hub key")

  HUE:init(ip,key,function()
    HUE:app()
    end)
end

function QuickApp:onInit()
  quickApp = self
  HUE = fibaro.engine
  local updated = self:getVariable("update")
  if updated=="yes" then
    self:debug("Updating HueV2App")
    self:setVariable("update","_")
    update()
  elseif HUE then init() 
  else self:error("Missing HUE library, set QV update=yes") end
end

function QuickApp:restart() plugin.restart() end
function QuickApp:dumpResources()
  if HUE then HUE:listAllDevicesGrouped() end
end
function QuickApp:devSelChanged(event)
  self.hueSelection = event.values[1]
end
function QuickApp:applyDevices()
  if not HUE then self:error("HUE not ready") return end
  HUE:applySelection(self.hueSelection or {})
end

function update()
  local baseURL = "https://raw.githubusercontent.com/jangabrielsson/Yahue/master/"
  local files = {
    {url=baseURL.."engine.lua",  name="Engine"},
    {url=baseURL.."devices.lua", name="App"},
    {url=baseURL.."utils.lua",   name="Utils"},
  }
  local fetched = {}
  local function getFile(url,cont)
    quickApp:debug("Fetching "..url)
    net.HTTPClient():request(url,{
      options = {method='GET', checkCertificate=false, timeout=20000},
      success = function(resp) cont(resp.data) end,
      error = function(err) fibaro.error(__TAG,"Fetching "..err) end
    })
  end
  local function fetchNext(i)
    if i > #files then
      quickApp:setVariable("update",os.date("%Y-%m-%d %H:%M:%S"))
      local batch = {}
      for _,f in ipairs(fetched) do
        batch[#batch+1] = {name=f.name, isMain=false, isOpen=false, content=f.content}
      end
      api.put("/quickApp/"..quickApp.id.."/files",batch)
      setTimeout(init,0)
      return
    end
    getFile(files[i].url,function(data)
      fetched[#fetched+1] = {name=files[i].name, content=data}
      fetchNext(i+1)
    end)
  end
  fetchNext(1)
end

-- local var,cid,n = "RPC"..plugin.mainDeviceId,plugin.mainDeviceId,0
-- local vinit,path = { name=var, value=""},"/plugins/"..cid.."/variables/"..var

-- api.post("/plugins/"..cid.."/variables",{ name=var, value=""}) -- create var if not exist
-- function fibaro._rpc(id,fun,args,timeout,qaf)
--   n = n + 1
--   api.put(path,vinit)
--   fibaro.call(id,"RPC_CALL",path,var,n,fun,args,qaf)
--   timeout = os.time()+(timeout or 3)
--   while os.time() < timeout do
--     local r,_ = api.get(path)
--     if r and r.value~="" then
--       r = r.value 
--       if r[1] == n then
--         if not r[2] then error(r[3],3) else return select(3,table.unpack(r)) end
--       end
--     end 
--   end
--   error(string.format("RPC timeout %s:%d",fun,id),3)
-- end

-- function fibaro.rpc(id,name,timeout) return function(...) return fibaro._rpc(id,name,{...},timeout) end end

-- function QuickApp:RPC_CALL(path2,var2,n2,fun,args,qaf)
--   local res
--   if qaf then res = {n2,pcall(self[fun],self,table.unpack(args))}
--   else res = {n2,pcall(_G[fun],table.unpack(args))} end
--   api.put(path2,{name=var2, value=res}) 
-- end