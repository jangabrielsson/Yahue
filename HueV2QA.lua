---@diagnostic disable: undefined-global
_DEVELOP = "../../hc3emu"
if require and not QuickApp then require("hc3emu") end

--%%name=YahueV2
--%%type=com.fibaro.deviceController
--%%uid=UPD896846032517896
--%%save=Yahue.fqa
--%%var=Hue_IP:config.Hue_IP
--%%var=Hue_User:config.Hue_user
--%% merge=QAs/HueV2Engine.lua,QAs/HueV2App.lua,QAs/HueV2File.lua
--%%file=HueV2Engine.lua,Engine;
--%%file=HueV2App.lua,App;
--%%file=HueV2Map.lua,Map;
--%%file=../../fibemu/lib/BetterQA.lua,BetterQA;
--%% file=HueV2File.lua,HueV2;
--%%u={label='info', text=''}
--%%u={button='restart', text='Restart', onReleased='restart'}
--%%u={button='dump', text='Dump resources', onReleased='dumpResources'}

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
  local ip = (self.qvar.Hue_IP or ""):match("(%d+.%d+.%d+.%d+)")
  local key = self.qvar.Hue_User --:match("(.+)")
  assert(ip,"Missing Hue_IP - hub IP address")
  assert(key,"Missing Hue_User - Hue hub key")

  HUE:init(ip,key,function()
    --HUEv2Engine:dumpDevices()
    --HUE:dumpDeviceTable()
    --HUE:listAllDevicesGrouped()
    HUE:app()
    end)
end

function QuickApp:onInit()
  quickApp = self
  HUE = HUEv2Engine
  function self.initChildDevices() end
  local updated = self:getVariable("update")
  if self.qvar.update=="yes" then
    self:debug("Updating HueV2App")
    self.qvar.update="_"
    update()
  elseif HUE then init() 
  else self:error("Missing HUE library, set QV update=yes") end
end

function QuickApp:restart() plugin.restart() end
function QuickApp:dumpResources() 
  if HUE then HUE:listAllDevicesGrouped() end
end

function update()
  local baseURL = "https://raw.githubusercontent.com/jangabrielsson/fibemu/master/"
  local file1 = baseURL.."QAs/HueV2File.lua"
  local function getFile(url,cont)
    quickApp:debug("Fetching "..url)
    net.HTTPClient():request(url,{
      options = { method = 'GET', checkCertificate=false, timeout=20000},
      success = function(resp) cont(resp.data) end,
      error = function(err) fibaro.error(__TAG,"Fetching "..err) end
    })
  end
  getFile(file1,function(data1)
    quickApp.qvar.update = os.date("%Y-%m-%d %H:%M:%S")
    local stat,err = api.put("/quickApp/"..quickApp.id.."/files",{
      {name="HueV2", isMain=false, isOpen=false, content=data1},
    })
    setTimeout(init,0)
  end)
end