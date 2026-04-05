--%%name:Yahue
--%%type:com.fibaro.deviceController
--%%uid:UPD896846032517896
--%%save:dist/Yahue.fqa
--%%var:Hue_IP=config.Hue_ip
--%%var:Hue_User=config.Hue_user
--%%file:engine.lua,Engine
--%%file:$fibaro.lib.qwikchild,qwickchild
--%%file:userconfig.lua,UserConfig
--%%file:devices.lua,App
--%%file:utils.lua,Utils
--%%u:{label='info', text=''}
--%%u:{label='huedevs', text='Hue devices found:'}
--%%u:{multi='devSelect', text='Devices', values={}, options={}, onToggled='devSelChanged'}
--%%u:{{button='pairHue', text='Pair with bridge', onReleased='pairHue'},{button='restart', text='Restart', onReleased='restart'}}
--%%u:{{button='dump', text='Dump', onReleased='dumpResources'},{button='applyDevices', text='Apply selection', onReleased='applyDevices'}}
--%%u:{label='releases', text='Available releases:'}
--%%u:{select='releaseSelect', text='Recovery: Select release', value='', options={}, onToggled='installRelease'}

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
local HUE,update

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
    self:updateView("info","text","Missing engine files — select a release to restore")
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
  HUE = fibaro.engine
  local updated = self:getVariable("update")
  if updated=="yes" then
    self:debug("Updating HueV2App")
    self:setVariable("update","_")
    update()
  elseif isEngineReady(HUE) then 
    init()
  else 
    self:updateView("info","text","Missing engine files — select a release to restore")
  end
  fetchReleases()  -- Always populate releases (for recovery or version switching)
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

function fetchReleases()
  local self = quickApp
  local repoURL = "https://api.github.com/repos/jangabrielsson/Yahue/releases"
  
  net.HTTPClient():request(repoURL, {
    options = { method='GET', checkCertificate=false, timeout=10000, headers={['Accept']='application/vnd.github.v3+json'} },
    success = function(resp)
      local ok, releases = pcall(json.decode, resp.data)
      if not ok or not releases then
        self:error("Failed to parse releases")
        return
      end
      
      local options = {{type='option', text='-- Choose version --', value=''}}
      for _, rel in ipairs(releases) do
        if rel.tag_name then
          -- Mark releases without .fqa asset with a note
          local hasFqa = false
          for _, asset in ipairs(rel.assets or {}) do
            if asset.name == "Yahue.fqa" then
              hasFqa = true
              break
            end
          end
          local label = rel.tag_name
          if not hasFqa then label = label .. " (no asset)" end
          options[#options+1] = {type='option', text=label, value=rel.tag_name}
        end
      end
      self:updateView("releaseSelect", "options", options)
      self:debug("Loaded "..#releases.." releases")
    end,
    error = function(err)
      self:error("Fetching releases: "..tostring(err))
    end
  })
end

function QuickApp:installRelease(event)
  local tag = event.values[1] or (type(event) == 'string' and event) or ''
  if tag == '' or tag == nil then return end
  
  self:updateView("releaseSelect", "value", '')  -- Reset dropdown
  self:updateView("info", "text", "Downloading release "..tag.."...")
  
  local releasesURL = "https://api.github.com/repos/jangabrielsson/Yahue/releases/tags/"..tag
  
  net.HTTPClient():request(releasesURL, {
    options = { method='GET', checkCertificate=false, timeout=10000, headers={['Accept']='application/vnd.github.v3+json'} },
    success = function(resp)
      local ok, release = pcall(json.decode, resp.data)
      if not ok or not release then
        self:error("Failed to parse release")
        return
      end
      
      -- Find the .fqa asset
      local fqaURL = nil
      local assetName = nil
      for _, asset in ipairs(release.assets or {}) do
        if asset.name == "Yahue.fqa" then
          fqaURL = asset.browser_download_url
          assetName = asset.name
          break
        end
      end
      
      if not fqaURL then
        self:error("No Yahue.fqa found in release")
        return
      end
      
      self:updateView("info", "text", "Downloading "..assetName.."...")
      
      -- Download the .fqa file
      net.HTTPClient():request(fqaURL, {
        options = { method='GET', checkCertificate=false, timeout=30000 },
        success = function(fqaResp)
          local ok, decoded = pcall(json.decode, fqaResp.data)
          local fqa = ok and decoded or nil
          
          if not fqa or not fqa.files then
            self:error("Invalid .fqa format")
            return
          end
          
          self:updateView("info", "text", "Installing "..tag.."...")
          
          -- Build batch: preserve UserConfig if it exists
          local existing = {}
          local currentFiles = api.get("/quickApp/"..self.id.."/files") or {}
          for _,f in ipairs(currentFiles) do existing[f.name] = true end
          
          local batch = {}
          for _,f in ipairs(fqa.files) do
            if f.name == "UserConfig" and existing["UserConfig"] then
              self:debug("Preserving UserConfig")
            else
              batch[#batch+1] = { name=f.name, isMain=f.isMain or false, isOpen=false, content=f.content }
            end
          end
          
          -- Install files (auto-restarts)
          self:setVariable("update", os.date("%Y-%m-%d %H:%M:%S").." from "..tag)
          api.put("/quickApp/"..self.id.."/files", batch)
          self:debug("Update complete — restarting")
        end,
        error = function(err)
          self:error("Downloading .fqa: "..tostring(err))
        end
      })
    end,
    error = function(err)
      self:error("Fetching release: "..tostring(err))
    end
  })
end

function update()
  local baseURL = "https://raw.githubusercontent.com/jangabrielsson/Yahue/master/"
  quickApp:debug("Fetching dist/Yahue.fqa...")
  net.HTTPClient():request(baseURL.."dist/Yahue.fqa", {
    options = { method='GET', checkCertificate=false, timeout=30000 },
    success = function(resp)
      local fqa = json.decode(resp.data)
      if not fqa or not fqa.files then
        quickApp:error("Failed to parse Yahue.fqa")
        return
      end
      -- Check which files already exist in this QA
      local existing = {}
      local currentFiles = api.get("/quickApp/"..quickApp.id.."/files") or {}
      for _,f in ipairs(currentFiles) do existing[f.name] = true end

      -- Build batch: include all files from the .fqa except UserConfig if it already exists
      local batch = {}
      for _,f in ipairs(fqa.files) do
        if f.name == "UserConfig" and existing["UserConfig"] then
          quickApp:debug("Skipping UserConfig (preserving user customisations)")
        else
          batch[#batch+1] = { name=f.name, isMain=f.isMain or false, isOpen=false, content=f.content }
        end
      end

      quickApp:setVariable("update", os.date("%Y-%m-%d %H:%M:%S"))
      api.put("/quickApp/"..quickApp.id.."/files", batch)
      quickApp:debug("Update complete — restarting")
      setTimeout(init, 0)
    end,
    error = function(err)
      quickApp:error("Fetching dist/Yahue.fqa: "..tostring(err))
    end
  })
end
