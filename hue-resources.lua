-- hue-resources.lua — Hue v2 API resource class definitions
-- Extracted from engine.lua. Called by engine.lua's main() with a shared context table.

fibaro.hueResources = fibaro.hueResources or {}

function fibaro.hueResources.define(ctx)
  -- Alias context fields
  local defClass, resolve = ctx.defClass, ctx.resolve
  local props, meths = ctx.props, ctx.meths
  local classes = ctx.classes
  local fmt = ctx.fmt
  local merge = ctx.merge
  local PGET, PSET = ctx.PGET, ctx.PSET
  local DEBUG, WARNING = ctx.DEBUG, ctx.WARNING
  local copyShallow = ctx.copyShallow
  local HUE = ctx.HUE

  
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
    -- Preserve listeners across :modified() — :setup() is called both on
    -- initial construction AND every time the resource is re-sent by the
    -- bridge (e.g. the 30-min health-check refresh). Resetting listeners
    -- here would drop every child QA's subscription, so events keep being
    -- received and processed but never propagate (children stop updating).
    self.listeners = self.listeners or {}
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
    local ll = self.listeners[key]
    if ll then
      for _, l in ipairs(ll) do
        local ok, err = pcall(l, key, value, self)
        if not ok then
          WARNING("EventBus error in %s:%s: %s", self.id, key, tostring(err))
        end
      end
    end
  end
  
  function hueResource:subscribe(key,fun)
    if self.services then
      for _,s in ipairs(self.services or {}) do resolve(s):subscribe(key,fun) end
    elseif self._props and self._props[key] then
      self.listeners[key] = self.listeners[key] or {}
      self.listeners[key][#self.listeners[key]+1] = fun
    end
  end
  function hueResource:unsubscribe(key,fun)
    for _,s in ipairs(self.services or {}) do resolve(s):unsubscribe(key,fun) end
    if self.listeners[key] then
      if fun==true then self.listeners[key]={}
      else
        for i, f in ipairs(self.listeners[key]) do
          if f == fun then
            table.remove(self.listeners[key], i)
            break
          end
        end
      end
    end
  end
  function hueResource:sendCmd(cmd,slot) return ctx.huePUT(self.path,cmd,nil,slot) end
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
  -- Instant off + snap brightness to 1% (no transition). Uses slot 'off' so a
  -- subsequent setValue() in the same sync burst is queued separately.
  function light:snapOff() self:sendCmd({on={on=false},dimming={brightness=1}},'off') end
  function light:setDim(val,transition)
    if val == -1 then
      self:sendCmd({dimming_delta={action='stop'}},'setDim')
    else
      self:sendCmd({dimming={brightness=val},dynamics=transition and {duration=transition} or nil},'setDim')
    end
  end
  -- Fades from `from`% to `to`% (with turn-on) over `duration` ms.
  -- Pre-positions at `from` (no turn-on) then sends the fade in a single queue
  -- cycle — no user-side timer needed.
  function light:fadeTo(from,to,duration)
    self:sendCmd({dimming={brightness=from}},'setDim')
    self:sendCmd({on={on=true},dimming={brightness=to},dynamics=duration and {duration=duration} or nil})
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
    local cmd = {effects={effect=e}}
    if e ~= 'no_effect' then cmd.on = {on=true} end
    self:sendCmd(cmd)
  end
  function light:setTimedEffect(effect, duration_ms)
    local e = effect == 'stop' and 'no_effect' or effect
    local cmd = {timed_effects={effect=e}}
    if e ~= 'no_effect' and duration_ms then cmd.timed_effects.duration = duration_ms end
    if e ~= 'no_effect' then cmd.on = {on=true} end
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
  function grouped_light:snapOff() self:sendCmd({on={on=false},dimming={brightness=1}},'off') end
  function grouped_light:setDim(val,transition)
    if val == -1 then
      self:sendCmd({dimming_delta={action='stop'}},'setDim')
    else
      self:sendCmd({dimming={brightness=val},dynamics=transition and {duration=transition} or nil},'setDim')
    end
  end
  function grouped_light:fadeTo(from,to,duration)
    self:sendCmd({dimming={brightness=from}},'setDim')
    self:sendCmd({on={on=true},dimming={brightness=to},dynamics=duration and {duration=duration} or nil})
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
  
  --- iterateMemberLights(self, fn)
  -- Calls fn(svc) for each individual light service in this group.
  -- fn receives the resolved light service object.
  local function iterateMemberLights(self, fn)
    local owner = self.owner and resolve(self.owner) or nil
    if not owner or not owner.children then return end
    for _,c in ipairs(owner.children) do
      local dev = resolve(c)
      if dev and dev.services then
        for _,s in ipairs(dev.services) do
          local svc = resolve(s)
          if svc and svc.type == 'light' and svc.id ~= self.id then
            fn(svc)
          end
        end
      end
    end
  end

  --- grouped_light:setEffect(effect)
  -- Hue bridge does not support effects on grouped_light resources.
  -- Fan out to each individual light in the group instead.
  function grouped_light:setEffect(effect)
    local e = effect == 'stop' and 'no_effect' or effect
    local cmd = {effects={effect=e}}
    if e ~= 'no_effect' then cmd.on = {on=true} end
    iterateMemberLights(self, function(svc)
      svc:sendCmd(cmd)
    end)
  end

  --- grouped_light:setTimedEffect(effect, duration_ms)
  function grouped_light:setTimedEffect(effect, duration_ms)
    local e = effect == 'stop' and 'no_effect' or effect
    local cmd = {timed_effects={effect=e}}
    if e ~= 'no_effect' and duration_ms then cmd.timed_effects.duration = duration_ms end
    if e ~= 'no_effect' then cmd.on = {on=true} end
    iterateMemberLights(self, function(svc)
      svc:sendCmd(cmd)
    end)
  end

  meths.scene = { recall=true, targetCmd=true }
  local scene = defClass('scene',hueResource)
  function scene:__init(id)
    hueResource.__init(self,id)
    self._str = fmt("[scene:%s,%s]",self.id,self.name)
  end
  function scene:recall(transition, dynamic)
    local action = dynamic and "dynamic_palette" or "active"
    self:sendCmd({recall = { action = action, dynamics = transition and {duration=transition} or nil }})
  end
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
end