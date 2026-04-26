--[[
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
Everyone is permitted to copy and distribute verbatim copies
of this license document, but changing it is not allowed.
(C) 2022 jan@gabrielsson.com
--]]

-- luacheck: globals ignore quickApp plugin api net netSync setTimeout clearTimeout setInterval clearInterval json
-- luacheck: globals ignore hc3_emulator fibaro
-- luacheck: globals ignore homekit device light zigbee_connectivity device_power zgp_cpnnectivity entertainment entertainment_configuration
-- luacheck: globals ignore room zone grouped_light scene button relative_rotary temperature motion light_level bridge bridge_home behavior_script
-- luacheck: globals ignore behavior_instance geolocation geolocation_client
-- luacheck: ignore 212/self

local _version_e = 0.58

local fmt = string.format
fibaro.debugFlags = fibaro.debugFlags or {}
local debug = fibaro.debugFlags
local function DEBUG(flag,fm,...) if debug[flag] then quickApp:debug(fmt(fm,...)) end end
local function WARNING(fm,...) quickApp:warning(fmt(fm,...)) end
local function ERROR(fm,...) quickApp:error(fmt(fm,...)) end

fibaro.engine = fibaro.engine or {}
local HUE = fibaro.engine
HUE.version = _version_e

local function setup()
end
local function strip(l) local r={} for k,v in pairs(l) do r[#r+1]=k end return r end

--[[
debug.info          -- greetings etc
debug.class         -- class creation
debug.resource_mgmt -- creation/delation/modification of object
debug.event         -- incoming event from Hue hub
debug.v2api         -- v2api info (unhandled events etc)
debug.call          -- http calls to Hue hub
debug.unknownType   -- Unhandled device updates
debug.logger        -- Logs subscribption events
--]]

--[[
Room--+
|             +------ Service A
|             |
+---Device ---+
|
+--+------ Service B
|
Zone-------------+
|
+----- Service - Grouped Light
--]]

if not fibaro.event then
  local _events={}
  function fibaro.event(ev,h) _events[ev.type]=h end
  function fibaro.post(ev,t)
    return setTimeout(function() _events[ev.type](ev) end,t or 0)
  end
end

local function copyShallow(t) local r = {} for k,v in pairs(t) do r[k]=v end return r end
local function copy(t) 
  local r = {} 
  for k,v in pairs(t) do if type(v)=='table' then r[k]=copy(v) else r[k]=v end end 
  return r
end

local PGETCACHE = {}
local function PGET(path,tab,dflt)
---@diagnostic disable-next-line: undefined-field
    local ps = PGETCACHE[path] or string.split(path,".")
    if tab == nil then tab = {} end
    PGETCACHE[path] = ps
    for _,p in ipairs(ps) do
        tab = tab[p]
        if tab == nil then return dflt end
    end
    return tab
end

local function PSET(path,tab,val)
    if tab == nil then tab = {} end
---@diagnostic disable-next-line: undefined-field
    local ps,t,p = PGETCACHE[path] or string.split(path,"."),tab,nil
    PGETCACHE[path] = ps
    for i=1,#ps-1 do
        p = ps[i]
        if p and t[p] == nil then t[p] = {} end
        t = t[p]
    end
    t[ps[#ps]] = val
    return tab
end

local function keyMerge(t1,t2)
  for k,v in pairs(t2) do if t1[k]==nil then t1[k]=v end end
  return t1
end

local _initEngine
local function main()
  local v2 = "1948086000"
  local err_retry = 3
  local post = fibaro.post
  local resources = {}
  local props,meths={},{}
  local hueGET,huePUT
  local app_key,url,callBack
  local fmt = string.format
  local merge = keyMerge
  local classes = {}
  ---------------------------------------------------------------------------
  -- RESOURCE REGISTRY
  ---------------------------------------------------------------------------
  local function createResourceTable()
    local self = { resources={}, id2resource={} }
    local resources,id2resource = self.resources,self.id2resource
    local warnedTypes = {}
    function self.changeHook() end
    function self.add(id,rsrc)
      local typ = rsrc.type
      if id2resource[id] then self.modify(id,rsrc)
      else
        if classes[typ] then
          rsrc = classes[typ](rsrc)
        else
          if not warnedTypes[typ] then
            warnedTypes[typ] = true
            WARNING("Missing resource type:%s (further events for this type will be ignored)",typ)
          end
          return
        end
        resources[typ]=resources[typ] or {};
        resources[typ][id]=rsrc;
        id2resource[id]=rsrc
        rsrc:added()
      end
    end
    function self.modify(id,rsrc)
      -- Silently ignore modify for ids we never registered (e.g. resources
      -- of an unknown/unsupported type — see self.add).
      if not id2resource[id] then return end
      id2resource[id]:modified(rsrc)
    end
    function self.delete(id)
      -- Silently ignore delete for ids we never registered. Otherwise an
      -- asserted error here crashes the SSE event loop and the QA stops
      -- receiving events. This commonly happens when the bridge sends a
      -- delete for an unsupported resource type (e.g. smart_scene/clip).
      local rsrc=id2resource[id]
      if not rsrc then return end
      resources[rsrc.type][id]=nil
      rsrc:deleted()
      id2resource[id]=nil
    end
    function self.get(id) return id2resource[id] end
    return self
  end
  
  local function resolve(rr)
    return rr and resources.get(rr.rid) or 
    { subscribe=function(_,_,_) end, publishMySubs=function() end, publishAll=function() end } 
  end
  
  local function defClass(name,parent)
    local p = class(name)
    local cl = _G[name]
    classes[name] = cl
    _G[name] = nil
    if parent then p(parent) end
    return cl
  end
  
  ---------------------------------------------------------------------------
  -- RESOURCE CLASS DEFINITIONS
  ---------------------------------------------------------------------------
  local hueResource = defClass('hueResource')
  function hueResource:__init(rsrc) self:setup(rsrc) end
  
  function hueResource:setup(rsrc)
    local id = rsrc.id
    self.id = id
    for m,_ in pairs(self._inheritedFuns or {}) do self[m]=nil end
    self.rsrc = rsrc
    self.type = rsrc.type
    self.services = rsrc.services
    self.children = rsrc.children
    self.owner = rsrc.owner
    self.metadata = rsrc.metadata or {}
    self.product_data = rsrc.product_data or {}
    self.resourceType = self.product_data.model_id or self.metadata.archetype or "unknown"
    self.resourceName = self.product_data.product_name
    self.name = self.metadata.name
    self._inheritedFuns = {}
    self.path = "/clip/v2/resource/"..self.type.."/"..self.id
    self._inited = true
    self.listeners = {}
    self._props = props[self.type]
    self._meths = meths[self.type]
    DEBUG("class","Setup %s '%s' %s",self.id,self.type,self.name or "rsrc")
  end
  function hueResource:getName(dflt)
    if self.name then return self.name end
    local n = resolve(self.owner).name
    if n then self.name = n return n end
    return dflt
  end
  function hueResource:added() DEBUG('resource_mgmt',"Created %s",tostring(self)) end
  function hueResource:deleted() DEBUG('resource_mgmt',"Deleted %s",tostring(self)) end
  function hueResource:modified(rsrc) self:setup(rsrc) DEBUG('resource_mgmt',"Modified %s",tostring(self)) end
  function hueResource:findServiceByType(typ)
    local r = {}
    for _,s in ipairs(self.services or {}) do local x=resolve(s) if x.type==typ then r[#r+1]=x end end
    return r
  end
  function hueResource:getCommand(cmd)
    if self[cmd] then return self end
    for _,s in ipairs(self.services or {}) do
      local x=resolve(s)
      if x[cmd] then return x end
    end
  end
  
  function hueResource:getProps()
    local r,btns = {},0
    for _,s in ipairs(self.services or {}) do
      local r1 = resolve(s) or {}
      local ps = r1.getProps and r1:getProps() or {}
      merge(r,ps)
    end
    merge(r,self._props or {})
    return r
  end
  function hueResource:getMethods()
    local r = {}
    for _,s in ipairs(self.services or {}) do merge(r,resolve(s):getMethods()) end
    merge(r,self._meths or {})
    return r
  end
  function hueResource:event(data)
    DEBUG('event',"Event: %s",data)
    if self.update then self:update(data) return end
    local p = self._props -- { power_state = { get, set changed }, ...
    if p then
      local r = self.rsrc
      for k,f in pairs(p) do
        if data[k] and f.changed then
          local c,v = f.changed(r,data)
          if c then
            f.set(r,v)
            self:publish(k,v)
          end
        end
      end
    end
    if self.owner then
      local o = resolve(self.owner)
      if o._postEvent then o:_postEvent(self.id) end
    end
  end
  function hueResource:publishMySubs()
    local p = self._props -- { power_state = { get, set changed }, ...
    if p then
      local r = self.rsrc
      for k,f in pairs(p) do
        if r[k] then self:publish(k,f.get(r)) end
      end
    end
  end
  function hueResource:publishAll()
    if self.services then
      for _,s in ipairs(self.services or {}) do resolve(s):publishMySubs() end
    else
      self:publishMySubs()
    end
    if self._postEvent then self:_postEvent(self.id) end
  end
  function hueResource:publish(key,value)
    local ll = self.listeners[key] or {}
    if next(ll) then
      for l,_ in pairs(ll) do
        l(key,value,self)
      end
    end
  end
  
  function hueResource:subscribe(key,fun)
    if self.services then
      for _,s in ipairs(self.services or {}) do resolve(s):subscribe(key,fun) end
    elseif self._props and self._props[key] then
      self.listeners[key] = self.listeners[key] or {}
      self.listeners[key][fun]=true
    end
  end
  function hueResource:unsubscribe(key,fun)
    for _,s in ipairs(self.services or {}) do resolve(s):unsubscribe(key,fun) end
    if self.listeners[key] then
      if fun==true then self.listeners[key]={}
      else self.listeners[key][fun]=nil end
    end
  end
  function hueResource:sendCmd(cmd) return huePUT(self.path,cmd) end
  function hueResource:__tostring() return self._str or fmt("[rsrc:%s]",self.id) end
  function hueResource:annotateEvent(r)
    return setmetatable(r,{
      __tostring = function(r)
        return fmt("%s %s",r.type,self.name or r.id_v1 or "") 
      end
    })
  end
  -------
  
  local homekit = defClass('homekit',hueResource)
  function homekit:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[homekit:%s]",self.id)
  end
  
  local device = defClass('device',hueResource)
  function device:__init(id)
    hueResource.__init(self,id)
    self.archetype = self.rsrc.metadata.archetype
    self.name = self.name or "device"
    self._str = fmt("[device:%s,%s,%s]",self.id,self.name,self.resourceType)
  end
  
  local pprops = { color={"setColor"},color_temperature={"setTemperature"},dimming={"setDim"} }
  local function pruneLights(self)
    self._props = copyShallow(self._props)
    self._meths = copyShallow(self._meths)
    for p,m in pairs(pprops) do
      if self.rsrc[p]==nil then
        self._props[p]=nil
        for _,f in ipairs(m) do self._meths[f]=nil end
      end
    end
  end
  
  local light = defClass('light',hueResource)
  function light:__init(id)
    hueResource.__init(self,id)
    self.archetype = resolve(self.owner).archetype or "unknown_archetype"
    pruneLights(self)
    self._str = fmt("[light:%s,%s,%s]",self.id,self:getName("LGHT"),self.resourceType)
  end
  function light:turnOn(transition) self:sendCmd({on={on=true},dynamics=transition and {duration=transition} or nil}) end
  function light:turnOff(transition) self:sendCmd({on={on=false},dynamics=transition and {duration=transition} or nil}) end
  function light:setDim(val,transition)
    if val == -1 then
      self:sendCmd({dimming_delta={action='stop'}})
    else
      self:sendCmd({dimming={brightness=val},dynamics=transition and {duration=transition} or nil})
    end
  end
  function light:setColor(arg,transition) -- {x=x,y=y} <string>, {r=r,g=g,b=b}
    local xy
    if type(arg)=='string' then
      xy = HUE.xyColors[tostring(arg:lower())] or HUE.xyColors['white']
    elseif type(arg)=='table' then
      if arg.x and arg.y then xy = arg
      elseif arg.r and arg.g and arg.b then
      end
    end
    if xy then self:sendCmd({color={xy=xy},dynamics=transition and {duration=transition} or nil}) end
  end
  function light:toggle(transition)
    local on = self.rsrc.on.on
    self:sendCmd({on={on=not on},dynamics=transition and {duration=transition} or nil})
  end
  function light:rawCmd(cmd) self:sendCmd(cmd) end
  function light:setTemperature(t,transition) self:sendCmd({color_temperature={mirek=math.floor(t+0.5)},dynamics=transition and {duration=transition} or nil}) end
  function light:setEffect(effect)
    local e = effect == 'stop' and 'no_effect' or effect
    self:sendCmd({effects={effect=e}})
  end
  function light:setTimedEffect(effect, duration_ms)
    local e = effect == 'stop' and 'no_effect' or effect
    local cmd = {timed_effects={effect=e}}
    if e ~= 'no_effect' and duration_ms then cmd.timed_effects.duration = duration_ms end
    self:sendCmd(cmd)
  end
  function light:signal(sig, duration_ms, colors)
    if sig == 'stop' then self:sendCmd({signaling={signal='no_signal'}}) return end
    local cmd = { signaling = { signal=sig, duration=math.min(duration_ms or 5000, 65534000) } }
    if colors then
      cmd.signaling.colors = {}
      for _,hex in ipairs(colors) do
        local r = tonumber(hex:sub(1,2),16)/255
        local g = tonumber(hex:sub(3,4),16)/255
        local b = tonumber(hex:sub(5,6),16)/255
        local x,y = HUE:rgbToXy(r*255,g*255,b*255)
        cmd.signaling.colors[#cmd.signaling.colors+1] = {xy={x=x,y=y}}
      end
    end
    self:sendCmd(cmd)
  end
  meths.light = { turnOn=true, turnOff=true, setDim=true, setColor=true, setTemperature=true, toggle=true, rawCmd=true, signal=true, setEffect=true, setTimedEffect=true }
  props.light = {
    on={get=function(r) return r.on.on end,set=function(r,v) r.on.on=v end, changed=function(o,n) return o.on.on ~= n.on.on, n.on.on end },
    dimming={
      get=function(r) return r.dimming.brightness end,
      set=function(r,v) r.dimming.brightness=v end,
      changed=function(o,n) return o.dimming.brightness~=n.dimming.brightness,n.dimming.brightness end,
    },
    color_temperature={
      get=function(r) return r.color_temperature.mirek end,
      set=function(r,v) r.color_temperature.mirek=v end,
      changed=function(o,n) return n.color_temperature.mirek_valid and o.color_temperature.mirek~=n.color_temperature.mirek,n.color_temperature.mirek end,
    },
    color={
      get=function(r) return r.color.xy end,
      set=function(r,v) r.color.xy=v end,
      changed=function(o,n)
        local oxy,nxy = o.color.xy,n.color.xy
        return oxy.x~=nxy.x or oxy.y~=nxy.y,nxy
      end,
    },
  }
  
  props.zigbee_connectivity = {
    status={
      get=function(r) return r.status end,
      set=function(r,v) r.status=v end,
      changed=function(o,n) return o.status~=n.status,n.status end,
    },
  }
  local zigbee_connectivity = defClass('zigbee_connectivity',hueResource)
  function zigbee_connectivity:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[zigbee_connectivity:%s,%s]",self.id,self:getName("CON"))
  end
  function zigbee_connectivity:connected()
    return self.rsrc.status=="connected"
  end
  
  props.device_power = {
    power_state={
      get=function(r) return r.power_state end,
      set=function(r,v) r.power_state=v end,
      changed=function(o,n) local s0,s1 = o.power_state,n.power_state return s0.battery_state~=s1.battery_state or s0.battery_level~=s1.battery_level,s1  end
    },
  }
  local device_power = defClass('device_power',hueResource)
  function device_power:__init(id)
    hueResource.__init(self,id)
  end
  function device_power:power()
    return self.rsrc.power_state.battery_level,self.rsrc.power_state.battery_state
  end
  function device_power:__tostring()
    return fmt("[device_power:%s,%s,value:%s]",self.id,self:getName(),self:power())
  end
  function device_power:event(data)
    hueResource.event(self,data)
  end
  
  props.zgp_connectivity = {
    status={get=function(r) return r.status end,set=function(r,v) r.status=v end},
  }
  meths.zgp_connectivity = { connected=true }
  local zgp_connectivity = defClass('zgp_connectivity',hueResource)
  function zgp_connectivity:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[zgp_connectivity:%s,%s]",self.id,self:getName("ZGP"))
  end
  function zgp_connectivity:connected()
    return self.rsrc.status=="connected"
  end
  
  local zigbee_device_discovery = defClass('zigbee_device_discovery',hueResource)
  function zigbee_device_discovery:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[zigbee_device_discovery:%s,%s]",self.id,self:getName("ZDD"))
  end
  
  local device_software_update = defClass('device_software_update',hueResource)
  function device_software_update:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[device_software_update:%s,%s]",self.id,self:getName("DSU"))
  end
  
  props.contact = {
    contact_report={
      get=function(r) return (r.contact_report or {}).state or "off" end,
      set=function(r,v) r.contact_report.state=v end,
      changed=function(o,n) return o.contact_report.state~=n.contact_report.state,n.contact_report.state end,
    },
  }
  local contact = defClass('contact',hueResource)
  function contact:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[contact:%s,%s]",self.id,self:getName("CON"))
  end
  
  props.tamper = {
    tamper={
      get=function(r) return r.tamper_reports[1].state end,
      set=function(r,v) r.tamper_reports[1].state=v end,
      changed=function(o,n) return o.tamper[1].state~=n.tamper[1].state,n.tamper[1].state end,
    },
  }
  local tamper = defClass('tamper',hueResource)
  function tamper:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[tamper:%s,%s]",self.id,self:getName("TAM"))
  end
  
  local matter = defClass('matter',hueResource)
  function matter:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[matter:%s,%s]",self.id,self:getName("MATT"))
  end
  
  local entertainment = defClass('entertainment',hueResource)
  function entertainment:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[entertainment:%s,%s]",self.id,self:getName("ENT"))
  end
  
  local entertainment_configuration = defClass('entertainment_configuration',hueResource)
  function entertainment_configuration:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[entertainment_configuration:%s,%s]",self.id,self:getName("ENT_CFG"))
  end
  
  meths.room = { targetCmd=true }
  local room = defClass('room',hueResource)
  function room:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[room:%s,%s,%s]",self.id,self.name,self.resourceType)
  end
  function room:setup(rsrc) hueResource.setup(self,rsrc) self.resourceName="Room" end
  function room:targetCmd(cmd)
    for _,s in ipairs(self.services or {}) do
      s = resolve(s)
      if s and s.type == 'grouped_light' then
        s:sendCmd(cmd)
      end
    end
  end
  
  meths.zone = { targetCmd=true }
  local zone = defClass('zone',hueResource)
  function zone:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[zone:%s,%s,%s]",self.id,self.name,self.resourceType)
  end
  function zone:setup(rsrc) hueResource.setup(self,rsrc) self.resourceName="Zone" end
  function zone:targetCmd(cmd)
    for _,s in ipairs(self.services or {}) do
      s = resolve(s)
      if s and s.type == 'grouped_light' then
        s:sendCmd(cmd)
      end
    end
  end
  
  props.grouped_light = props.light
  meths.grouped_light = meths.light
  local grouped_light = defClass('grouped_light',hueResource)
  function grouped_light:__init(id)
    hueResource.__init(self,id)
    pruneLights(self)
  end
  function grouped_light:__tostring() return fmt("[grouped_light:%s,%s]",self.id,self:getName("GROUP")) end
  function grouped_light:turnOn(transition) self:sendCmd({on={on=true},dynamics=transition and {duration=transition} or nil}) end
  function grouped_light:turnOff(transition) self:sendCmd({on={on=false},dynamics=transition and {duration=transition} or nil}) end
  function grouped_light:setDim(val,transition)
    if val == -1 then
      self:sendCmd({dimming_delta={action='stop'}})
    else
      self:sendCmd({dimming={brightness=val},dynamics=transition and {duration=transition} or nil})
    end
  end
  function grouped_light:setColor(arg,transition) -- {x=x,y=y} <string>, {r=r,g=g,b=b}
    local xy
    if type(arg)=='string' then
      xy = HUE.xyColors[tostring(arg:lower())] or HUE.xyColors['white']
    elseif type(arg)=='table' then
      if arg.x and arg.y then xy = arg
      elseif arg.r and arg.g and arg.b then
      end
    end
    if xy then self:sendCmd({color={xy=xy},dynamics=transition and {duration=transition} or nil}) end
  end
  function grouped_light:toggle(transition)
    local on = self.rsrc.on.on
    self:sendCmd({on={on=not on},dynamics=transition and {duration=transition} or nil})
  end
  function grouped_light:rawCmd(cmd) self:sendCmd(cmd) end
  -- Hue v2 quirk: when a grouped_light is commanded (or recalled via scene),
  -- the bridge does not always emit per-member-light SSE events. Override
  -- event() to first apply the change to ourselves, then replay the same
  -- payload on each member light service. The light's own `changed` check
  -- makes this idempotent if Hue does also send per-light events.
  function grouped_light:event(data)
    hueResource.event(self,data)
    -- Only replay the on/off field to members, and ONLY for on=false.
    -- A grouped_light's `on=true` only means "at least one member is on" —
    -- replaying it would falsely mark every member as on whenever a single
    -- light in the group is switched on. `on=false` is unambiguous (all
    -- members are off) so it is safe to fan out. Dimming/color/CT are
    -- aggregated values and are never replayed; per-light events cover them.
    if not data.on or data.on.on ~= false then return end
    local relayed = { on = data.on }
    local owner = self.owner and resolve(self.owner) or nil
    if not owner or not owner.children then return end
    for _,c in ipairs(owner.children) do
      local dev = resolve(c)
      if dev and dev.services then
        for _,s in ipairs(dev.services) do
          local svc = resolve(s)
          if svc and svc.type == 'light' and svc.id ~= self.id then
            svc:event(relayed)
          end
        end
      end
    end
  end
  function grouped_light:setTemperature(t,transition) self:sendCmd({color_temperature={mirek=math.floor(t+0.5)},dynamics=transition and {duration=transition} or nil}) end
  function grouped_light:signal(sig, duration_ms, colors)
    if sig == 'stop' then self:sendCmd({signaling={signal='no_signal'}}) return end
    local cmd = { signaling = { signal=sig, duration=math.min(duration_ms or 5000, 65534000) } }
    if colors then
      cmd.signaling.colors = {}
      for _,hex in ipairs(colors) do
        local r = tonumber(hex:sub(1,2),16)/255
        local g = tonumber(hex:sub(3,4),16)/255
        local b = tonumber(hex:sub(5,6),16)/255
        local x,y = HUE:rgbToXy(r*255,g*255,b*255)
        cmd.signaling.colors[#cmd.signaling.colors+1] = {xy={x=x,y=y}}
      end
    end
    self:sendCmd(cmd)
  end
  
  meths.scene = { recall=true, targetCmd=true }
  local scene = defClass('scene',hueResource)
  function scene:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[scene:%s,%s]",self.id,self.name)
  end
  function scene:recall(transition) self:sendCmd({recall = { action = "active",dynamics=transition and {duration=transition} or nil  }}) end
  function scene:targetCmd(cmd)
    if not self.rsrc.group then return end
    local zoneroom = resolve(self.rsrc.group)
    if not zoneroom then return end
    if zoneroom.targetCmd then zoneroom:targetCmd(cmd) end
  end
  
  props.button = {
    button = {
      get=function(r) if r.button then return r.button end end,
      set=function(r,v) if not r.button then r.button = { last_event = v } else r.button.last_event=v end end,
      changed=function(o,n)
        local ob,nb = o.button or {},n.button or {}
        return ob.last_event~=nb.last_event,nb.last_event
      end
    }
  }
  local button = defClass('button',hueResource)
  function button:__init(id)
    hueResource.__init(self,id)
  end
  function button:button_state()
    return self.rsrc.button and self.rsrc.button.last_event,self.rsrc.metadata.control_id
  end
  function button:__tostring()
    return fmt("[button:%s,%s,value:%s]",self.id,self:getName("BTN"),self:button_state())
  end
  
  
  props.relative_rotary = {
    relative_rotary = {
      get=function(r) return PGET('relative_rotary.last_event',r) end,
      set=function(r,v) PSET('relative_rotary.last_event',r,v) end,
      changed=function(o,n)
        local ob,nb = o.relative_rotary or {},n.relative_rotary or {}
        return true,nb.last_event
      end
    }
  }
  local relative_rotary = defClass('relative_rotary',hueResource)
  function relative_rotary:__init(id)
    hueResource.__init(self,id)
  end
  function relative_rotary:relative_rotary_state()
    local le = PGET('relative_rotary.last_event',self.rsrc)
    if le then 
      return le.rotation.steps,le.rotation.direction 
    else return "N/A","N/A" end
  end
  function relative_rotary:__tostring()
    return fmt("[rotary:%s,%s,value:%s/%s]",self.id,self:getName("ROT"),self:relative_rotary_state())
  end
  
  props.temperature = {
    temperature={
      get=function(r) return PGET('temperature.temperature_report.temperature',r) end,
      set=function(r,v) PSET('temperature.temperature_report.temperature',r,v) end,
      changed=function(o,n) local ov,nv = PGET('temperature.temperature_report.temperature',o), PGET('temperature.temperature_report.temperature',n) return nv~=ov,nv end,
    },
  }
  
  local temperature = defClass('temperature',hueResource)
  function temperature:__init(id)
    hueResource.__init(self,id)
  end
  function temperature:temperature()
    return self.rsrc.temperature.temperature_report.temperature
  end
  function temperature:__tostring()
    return fmt("[temperature:%s,%s,value:%s]",self.id,self:getName(),self:temperature() or "N/A")
  end
  
  props.motion = {
    motion={
      get=function(r) return PGET('motion.motion_report.motion',r) end,
      set=function(r,v) PSET('motion.motion_report.motion',r,v) end,
      changed=function(o,n) local ov,nv = PGET('motion.motion_report.motion',o), PGET('motion.motion_report.motion',n) return nv~=ov,nv end
    },
  }
  local motion = defClass('motion',hueResource)
  function motion:__init(id)
    hueResource.__init(self,id)
  end
  function motion:motion()
    return self.rsrc.motion.motion
  end
  function motion:__tostring()
    return fmt("[motion:%s,%s,value:%s]",self.id,self:getName(),self:motion() or false)
  end
  
  props.camera_motion = {
    motion={
      get=function(r) return PGET('motion.motion_report.motion',r,false) end,
      set=function(r,v) PSET('motion.motion_report.motion',r,v) end,
      changed=function(o,n) local ov,nv = PGET('motion.motion_report.motion',o), PGET('motion.motion_report.motion',n) return nv~=ov,nv end
    },
  }
  local camera_motion = defClass('camera_motion',hueResource)
  function camera_motion:__init(id)
    hueResource.__init(self,id)
  end
  function camera_motion:motion()
    return PGET('motion.motion_report.motion',self.rsrc,false)
  end
  function camera_motion:__tostring()
    return fmt("[camera_motion:%s,%s,value:%s]",self.id,self:getName(),self:motion() or false)
  end
  
  props.light_level = {
    light={
      get=function(r) return PGET('light.light_level_report.light_level',r,0) end,
      set=function(r,v) PSET('light.light_level_report.light_level',r,v) end,
      changed=function(o,n) local ov,nv = PGET('light.light_level_report.light_level',o), PGET('light.light_level_report.light_level',n) return nv~=ov,nv end,
    },
  }
  local light_level = defClass('light_level',hueResource)
  function light_level:__init(id)
    hueResource.__init(self,id)
  end
  function light_level:light_level()
    return PGET('light.light_level_report.light_level',self.rsrc,0)
  end
  function light_level:__tostring()
    return fmt("[light_level:%s,%s,value:%s]",self.id,self:getName(),self:light_level() or 0)
  end
  
  local bridge = defClass('bridge',hueResource)
  function bridge:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[bridge:%s]",self.id)
  end
  
  local bridge_home = defClass('bridge_home',hueResource)
  function bridge_home:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[bridge_home:%s]",self.id)
  end
  
  local behavior_script = defClass('behavior_script',hueResource)
  function behavior_script:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[behavior_script:%s,%s,%s]",self.id,self.rsrc.metadata.name,self.rsrc.metadata.category)
  end
  
  local behavior_instance = defClass('behavior_instance',hueResource)
  function behavior_instance:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[behavior_instance:%s,%s,%s]",self.id,self.rsrc.metadata.name,self.rsrc.metadata.category)
  end
  
  local geolocation = defClass('geolocation',hueResource)
  function geolocation:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[geolocation:%s]",self.id)
  end
  
  local geofence_client = defClass('geofence_client',hueResource)
  function geofence_client:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[geofence_client:%s]",self.id)
  end
  
  ---------------------------------------------------------------------------
  -- SSE EVENT POLLING
  ---------------------------------------------------------------------------
  local fetchEvents
  local function handle_events(data)
    for _,e1 in ipairs(data) do
      if e1.type=='update' then
        for _,r in ipairs(e1.data) do
          local d = resources.get(r.id)
          if d and d.event then
            DEBUG('all_event',"Event id:%s type:%s",d.id,d.type)
            d:annotateEvent(r)
            d:event(r)
          else
            local _ = 0
            if debug.unknownType then WARNING("Unknow resource type: %s",json.encode(e1)) end
          end
        end
      elseif e1.type == 'delete' then
        for _,r in ipairs(e1.data) do
          resources.changeHook()
          resources.delete(r.id)
        end
      elseif e1.type == 'add' then
        for _,r in ipairs(e1.data) do
          resources.changeHook()
          resources.add(r.id,r)
        end
      else
        DEBUG('v2api',"New v2 event type: %s",e1.type)
        DEBUG('v2api',"%s",json.encode(e1))
      end
    end
  end
  
  local function fetchEvents_emu()
    local getw
    local eurl = url.."/eventstream/clip/v2"
    local backoff = 0   -- ms; grows on consecutive errors, reset on success
    local args = { options = { 
      method='GET', 
      checkCertificate=false, 
      headers={ 
        ['hue-application-key'] = app_key,
        ['Accept'] = "application/json",
      }}
    }
    local function bumpBackoff()
      if backoff == 0 then backoff = 1000
      else backoff = math.min(backoff * 2, 30000) end
      return backoff
    end
    function args.success(res)
      backoff = 0
      local ok,err = pcall(function()
        local data = json.decode(res.data)
        handle_events(data)
      end)
      if not ok then WARNING("/eventstream parse: %s", tostring(err)) end
      getw()
    end
    function args.error(err)
      local transient = err and (err:match("timed out") or err == "wantread")
      if not transient then
        local d = bumpBackoff()
        WARNING("/eventstream: %s (retry in %dms)", err, d)
        setTimeout(getw, d)
      else
        getw()
      end
    end
    function getw() net.HTTPClient():request(eurl,args) end
    setTimeout(getw,0)
  end
  
  local function fetchEvents_hc3()
    local getw
    local eurl = url.."/eventstream/clip/v2"
    local backoff = 0   -- ms; grows on consecutive errors, reset on success
    -- Watchdog: the SSE TCP socket can in theory go silently half-dead (router
    -- NAT timeout, Wi-Fi blip, bridge restart) so neither success nor error
    -- ever fires again. Hue sends a `: hi` keep-alive at least every ~30s,
    -- so if we see nothing for WATCHDOG_MS we force a reconnect.
    -- Disabled by default (sseWatchdog=0). Earlier "silent stoppage" reports
    -- turned out to be the assert-in-delete bug, not actually-dead sockets,
    -- and reconnecting a healthy SSE stream just churns the bridge.
    -- Set the QA variable `sseWatchdog` to a number of seconds (e.g. 300) to
    -- enable.
    local watchdogSec = tonumber(quickApp:getVariable("sseWatchdog")) or 0
    local WATCHDOG_MS = watchdogSec * 1000
    local lastSeen = 0
    local watchdogRef
    local function armWatchdog()
      if WATCHDOG_MS <= 0 then return end
      if watchdogRef then clearTimeout(watchdogRef) end
      watchdogRef = setTimeout(function()
        watchdogRef = nil
        local quiet = (os.time() - lastSeen) * 1000
        if quiet >= WATCHDOG_MS then
          WARNING("/eventstream: no data for %ds, reconnecting", math.floor(quiet/1000))
          getw()
        else
          armWatchdog()
        end
      end, WATCHDOG_MS)
    end
    local args = {
      options = { 
        method='GET', 
        checkCertificate=false,
        headers={
          ["hue-application-key"] = app_key, 
          ['Accept'] = "text/event-stream" 
        },
        timeout = 2000 
      }
    }
    local function bumpBackoff()
      if backoff == 0 then backoff = 1000
      else backoff = math.min(backoff * 2, 30000) end
      return backoff
    end
    -- HC3's HTTPClient keeps the SSE (text/event-stream) connection open and
    -- calls `success` repeatedly as the bridge pushes event chunks. We must
    -- NOT re-issue the request on every success — that would fan out to many
    -- concurrent connections. We only re-arm via getw() on error or on a
    -- parse failure (which means the underlying stream is broken).
    -- A good `success` resets the backoff; failures grow it (1s → 2s → ...
    -- → 30s cap) so an unreachable bridge does not spam reconnects.
    function args.success(res)
      backoff = 0
      lastSeen = os.time()
      local stat,err = pcall(function()
        local body = res and res.data
        if type(body) ~= 'string' or body == '' then return end
        if body:match("^: hi") then return end          -- SSE keep-alive comment
        local arr = body:match("(%b[])")
        if not arr then return end                      -- partial / non-data frame
        local data = json.decode(arr)
        if data then handle_events(data) end
      end)
      if not stat then
        local d = bumpBackoff()
        WARNING("/eventstream parse: %s (retry in %dms)", tostring(err), d)
        setTimeout(getw, d)
      end
    end
    function args.error(err)
      local transient = err == "timeout" or err == "wantread"
      if not transient then
        local d = bumpBackoff()
        WARNING("/eventstream: %s (retry in %dms)", err, d)
        setTimeout(getw, d)
      else
        getw()
      end
    end
    function getw() 
      lastSeen = os.time()
      armWatchdog()
      net.HTTPClient():request(eurl,args) 
    end
    setTimeout(getw,0)
  end
  
  if fibaro.plua then fetchEvents = fetchEvents_emu
  else fetchEvents = fetchEvents_hc3 end
  
  ---------------------------------------------------------------------------
  -- HTTP TRANSPORT
  ---------------------------------------------------------------------------
  function hueGET(api,event)
    local u = url..api
    net.HTTPClient():request(u,{
      options = { 
        method='GET',
        checkCertificate=false, 
        headers={ 
          ['hue-application-key'] = app_key,
          ["Accept"] = "application/json",
        }
      },
      success = function(res) 
        if res.status < 300 then
          post({type=event,result=json.decode(res.data)}) 
        else
          post({type=event,error=res.status}) 
        end
      end,
      error = function(err) post({type=event,error=err})  end,
    })
  end
  
  function huePUT(path,data,op)
    DEBUG('call',"%s %s",path,json.encode(data))
    net.HTTPClient():request(url..path,{
      options = {
        method=op or 'PUT', 
        data=data and json.encode(data) or nil,
        checkCertificate=false, 
        ['content-type']="application/json",
        headers={ ['hue-application-key'] = app_key }
      },
      success = function(resp)
        local body = resp.data and json.decode(resp.data)
        if body and body.errors and #body.errors > 0 then
          ERROR("hue PUT error, %s - %s",path,json.encode(body.errors))
        end
      end,
      error = function(err,f,g)
        ERROR("hue call, %s %s - %s",path,json.encode(data),err)
      end,
    })
  end
  
  --[[
  {
  "dimming":{"brightness":58.66}, // color,color_temperature,on
  "owner":{"rtype":"device","rid":"8dddf049-0a73-44e2-8fdd-e3c2310c1bb1"},
  "type":"light",
  "id_v1":"/lights/5",
  "id":"fb31c148-177b-4b52-a1a5-e02d46c1c3dd"
  }
  
  {
  "id_v1":"/groups/5",
  "type":"grouped_light",
  "on":{"on":true},
  "id":"39c94b33-7a3d-48e7-8cc1-dc603d401db2"
  }
  
  {
  "id":"efc3283b-304f-4053-a01a-87d0c51462c3",
  "owner":{"rtype":"device","rid":"a007e50b-0bdd-4e48-bee0-97636d57285a"},
  "button":{"last_event":"initial_press"}, 
  "id_v1":"/sensors/2",
  "type":"button"
  }
  
  {
  "type":"light_level",
  "light":{"light_level":0,"light_level_valid":true},
  "owner":{"rtype":"device","rid":"9222ea53-37a6-4ac0-b57d-74bca1cfa23f"},
  "id_v1":"/sensors/7",
  "id":"a7295dae-379b-4d61-962f-6f9ad9426eda"
  }
  
  {
  "type":"motion",
  "motion":{"motion":false,"motion_valid":true},
  "owner":{"rtype":"device","rid":"9222ea53-37a6-4ac0-b57d-74bca1cfa23f"},
  "id_v1":"/sensors/6","id":"6356a5c3-e5b7-455c-bf54-3af2ac511fe6"
  }
  
  {
  "type":"device_power",
  "power_state":{"battery_state":"normal","battery_level":76},
  "owner":{"rtype":"device","rid":"a007e50b-0bdd-4e48-bee0-97636d57285a"},
  "id_v1":"/sensors/2",
  "id":"d6bc1f77-4603-4036-ae5f-28b16eefe4b5"
  }
  
  {
  "type":"zigbee_connectivity",
  "owner":{"rtype":"device","rid":"3ab27084-d02f-44b9-bd56-70ea41163cb6"},
  "status":"connected",  // "status":"connectivity_issue"
  "id_v1":"/lights/9",
  "id":"c024b020-395d-45a4-98ce-9df1409eda30"
  }
  --]]
  
  ---------------------------------------------------------------------------
  -- STARTUP STATE MACHINE
  ---------------------------------------------------------------------------
  fibaro.event({type='STARTUP'},function(_) hueGET("/api/config",'HUB_VERSION') end)
  
  fibaro.event({type='HUB_VERSION'},function(ev)
    if ev.error then
      ERROR("%s",ev.error)
    else
      resources = createResourceTable()
      local res = ev.result
      if res.swversion >= v2 then
        DEBUG('info',"V2 api available (%s)",res.swversion)
        post({type='REFRESH_RESOURCES'})
      else
        WARNING("V2 api not available (%s)",res.swversion)
      end
    end
  end)
  
  fibaro.event({type='REFRESH_RESOURCES'},function(_) hueGET("/clip/v2/resource",'REFRESHED_RESOURCES') end)
  
  local refreshBackoff = err_retry
  fibaro.event({type='REFRESHED_RESOURCES'},function(ev)
    if ev.error then
      WARNING("/clip/v2/resource %s",ev.error)
      WARNING("Retry in %ss",refreshBackoff)
      post({type='REFRESH_RESOURCES'},1000*refreshBackoff)
      refreshBackoff = math.min(refreshBackoff * 2, 60)
      return
    end
    refreshBackoff = err_retry
    for _,r in pairs(resources.id2resource) do
      r._dirty = true
    end
    for _,r in ipairs(ev.result.data or {}) do
      --print(r.type)
      r._dirty=nil
      resources.add(r.id,r)
    end
    for _,r in pairs(resources.id2resource) do
      if r._dirty then
        resources.delete(r.id)
      end
    end
    local cb
    if callBack then cb,callBack=callBack,nil setTimeout(cb,0) end
  end)
  
  ---------------------------------------------------------------------------
  -- HUE PUBLIC API
  ---------------------------------------------------------------------------
  function HUE:getResources() return resources.resources end
  function HUE:getResourceIds() return resources.id2resource end
  function HUE:getResource(id) return resources.id2resource[id] end
  function HUE:getResourceType(typ) return resources.resources[typ] or {} end
  function HUE:_resolve(id) return resolve(id) end
  function HUE:getSceneByName(name,roomzone)
    local scenes = self:getResourceType('scene')
    for id,scene in pairs(scenes) do
      if scene.name == name then
        if not roomzone then return scene end
        local g = scene.rsrc.group and resolve(scene.rsrc.group) or {}
        if g.name == roomzone then return scene end
      end
    end
  end
  local filter1 = { device=1, scene=10, room=2, zone=3 }
  
  local filter2 = { device=1, light=4, button=5, relative_rotary=5.5, scene=10, room=2, zone=3, temperature=6, light_level=7, motion=8, tamper=7.5, contact=7.6, grouped_light=9, zigbee_connectivity=10, device_power=11 }
  
  local function printBuffer(init) 
    local b = {init}
    function b:add(s) b[#b+1]=s end
    function b:printf(fmt,...) b:add(fmt:format(...)) end
    function b:tostring() return table.concat(b) end
    return b
  end
  fibaro.printBuffer = printBuffer
  
  function HUE:dumpDeviceTable(filter,selector,orgDevMap)
    filter =filter and filter2 or filter1
    orgDevMap = orgDevMap or {}
    selector = selector or function() return true end
    local  pb = printBuffer("\n")
    pb:add("\nlocal HueDeviceTable = {\n")
    local rs = {}
    for _,r in pairs(HUE:getResourceIds()) do
      if filter[r.type] then
        rs[#rs+1]={order=filter[r.type],str=tostring(r),r=r}
      end
    end
    local parentMap = {room={},zone={}}
    for _,r0 in ipairs(rs) do
      local r = r0.r
      if r.type=='room' or r.type=='zone' then
        for _,c in ipairs(r.children) do
          parentMap[r.type][c.rid]=r.name
        end
      end
    end
    table.sort(rs,function(a,b) return a.order < b.order or a.order==b.order and a.str < b.str end)
    for _,r0 in ipairs(rs) do
      local r = r0.r
      local room = parentMap.room[r.id]
      local zone = parentMap.zone[r.id]
      local ref = (orgDevMap[r.id] or {}).ref
      room=room and (",room='"..room.."'") or ""
      zone=zone and (",zone='"..zone.."'") or ""
      ref=ref and (",ref='"..ref.."'") or ""
      if r.type=='scene' then
        room = (",room='"..resolve(r.rsrc.group).name.."'")
      end
      pb:printf("%s['%s']={type='%s',name='%s',model='%s'%s%s%s},\n",selector(r.id) and "  " or "--",r.id,r.type,r.name,r.resourceType,room,zone,ref)
    end
    pb:add("}\n")
    print(pb:tostring())
  end
  
  function HUE:createDeviceTable(filter)
    filter =filter and filter2 or filter1
    local rs,rs2,res = HUE:getResourceIds(),{},{}
    
    local parentMap = {room={},zone={}}
    for uid,r in pairs(rs) do
      if filter[r.type] then
        rs2[uid]=r
        if r.type=='room' or r.type=='zone' then
          for _,c in ipairs(r.children) do
            parentMap[r.type][c.rid]=r.name
          end
        end
      end
    end
    for uid,r in pairs(rs2) do
      local m = {}
      res[uid]=m
      m.room = parentMap.room[r.id]
      m.zone = parentMap.zone[r.id]
      if r.type=='scene' then
        m.room = resolve(r.rsrc.group).name
      end
      m.type=r.type
      m.name=r.name
      m.model=r.resourceType
      m.props=strip(r:getProps())
      local btns=0
      if r.services then
        for _,s in ipairs(r.services) do
          btns = btns + (s.rtype=='button' and 1 or 0)
        end
      end
      m.buttons=btns
    end
    return res
  end
  
  local function sortResources(list,f)
    local rs = {}
    for _,r in pairs(list) do
      r = f and f(r) or r
      if filter2[r.type] then
        rs[#rs+1]={order=filter2[r.type],resource=r}
      end
    end
    table.sort(rs,function(a,b) return a.order < b.order or a.order==b.order and a.resource.id < b.resource.id end)
    local r0 = {}
    for _,r in ipairs(rs) do r0[#r0+1]=r.resource end
    return r0
  end
  
  local function printResource(r,pb,ind)
    pb:add(string.rep(' ',ind)..tostring(r).."\n")
    if r.owner then pb:add(string.rep(' ',ind+2).."Parent:"..r.owner.rid.."\n") end
    local rs = r.children and sortResources(r.children,function(r) return resolve(r) end) or {}
    if rs[1] then
      pb:add(string.rep(' ',ind+2).."Children:\n")
      for _,c in ipairs(rs) do
        printResource(c,pb,ind+4)
      end
    end
    rs = r.services and sortResources(r.services,function(r) return resolve(r) end) or {}
    if rs[1] then
      pb:add(string.rep(' ',ind+2).."Services:\n")
      for _,c in ipairs(rs) do
        printResource(c,pb,ind+4)
      end
    end
    if r.rsrc.actions then
      local w = resolve(r.rsrc.group)
      pb:add(string.rep(' ',ind+2).."Group:"..tostring(w).."\n")
      pb:add(string.rep(' ',ind+2).."Targets:\n")
      for _,a in ipairs(r.rsrc.actions or {}) do
        local f = resolve(a.target)
        pb:add(string.rep(' ',ind+4)..tostring(f).."\n")
      end
    end
  end
  
  function HUE:listAllDevicesGrouped(groups)
    local  pb = printBuffer("\n")
    pb:add("------------------------\n")
    local rs = sortResources(HUE:getResourceIds())
    for _,r in ipairs(rs) do if not r.owner then printResource(r,pb,0) end end
    pb:add("------------------------\n")
    print(pb:tostring():gsub("\n","</br>"):gsub("%s","&nbsp;"))
  end
  
  function _initEngine(ip,key,cb)
    app_key = key
    url =  fmt("https://%s",ip)
    DEBUG('info',"HUEv2Engine v%s",_version_e)
    DEBUG('info',"Hub url: %s",url)
    callBack = function()
      fetchEvents()
      setInterval(function()
        DEBUG('info',"Health-check: refreshing Hue resources")
        post({type='REFRESH_RESOURCES'})
      end, 30*60*1000)
      if cb then cb() end
    end
    post({type='STARTUP'})
  end
  
end -- main()

function HUE:init(ip,key,cb) 
  setup() 
  main() 
  _initEngine(ip,key,cb)
end
