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

local _version_e = 0.61

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

local enterCooldown, parseRetryAfter, cooldownDefault

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
  -- SSE liveness probe: { id, t0, expects, timer, cb } while a probe is in flight.
  local _sseProbe = nil
  local app_key,url,callBack
  local fmt = string.format
  local merge = keyMerge
  local classes = {}
  local ctx  -- forward declaration; populated after defClass below
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
    return rr and ctx.resources.get(rr.rid) or 
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
  -- SHARED CONTEXT
  -- Built once and passed to each extracted module's define() function.
  -- Mutations to ctx fields are visible across all modules that share it.
  ---------------------------------------------------------------------------
  -- Bridge rate-limit governor state (mutated by transport, read by startup)
  local bridgeHealthy = true
  local bridgeCoolUntil = 0
  local bridgeNoticeAt = 0
  local bridgeLastHealthy = os.time()
  cooldownDefault = 5
  local recent429 = {}

  -- State machine locals (mutated by startup)
  local refreshInFlight = false
  local refreshBlockedUntil = 0

  ctx = {
    -- Module-level utilities
    DEBUG = DEBUG,
    WARNING = WARNING,
    ERROR = ERROR,
    fmt = string.format,
    PGET = PGET,
    PSET = PSET,
    keyMerge = keyMerge,
    copyShallow = copyShallow,
    copy = copy,
    strip = strip,
    HUE = HUE,

    -- Main-local state
    v2 = v2,
    err_retry = err_retry,
    post = post,
    resources = resources,
    props = props,
    meths = meths,
    hueGET = hueGET,
    huePUT = huePUT,
    _sseProbe = _sseProbe,
    app_key = app_key,
    url = url,
    callBack = callBack,
    merge = merge,
    classes = classes,
    defClass = defClass,
    resolve = resolve,
    createResourceTable = createResourceTable,
    _version_e = _version_e,

    -- Rate-limit governor state (shared mutable)
    bridgeHealthy = bridgeHealthy,
    bridgeCoolUntil = bridgeCoolUntil,
    bridgeNoticeAt = bridgeNoticeAt,
    bridgeLastHealthy = bridgeLastHealthy,
    cooldownDefault = cooldownDefault,
    recent429 = recent429,

    -- State machine
    refreshInFlight = refreshInFlight,
    refreshBlockedUntil = refreshBlockedUntil,

    -- Placeholders set by modules
    fetchEvents = nil,
    enterCooldown = nil,
    parseRetryAfter = nil,
    bridgeWaitMs = nil,
    bridgeReady = nil,
    _initEngine = nil,
  }

  -- Phase 1: Define resource classes (populates props, meths, classes)
  if fibaro.hueResources and fibaro.hueResources.define then
    fibaro.hueResources.define(ctx)
  end

  -- Phase 2: Set up transport (defines hueGET, huePUT, fetchEvents, governor)
  if fibaro.hueTransport and fibaro.hueTransport.define then
    fibaro.hueTransport.define(ctx)
  end

  -- Phase 3: Set up startup state machine and public API (defines _initEngine)
  if fibaro.hueStartup and fibaro.hueStartup.define then
    fibaro.hueStartup.define(ctx)
  end

  -- Pull back mutated state from context
  hueGET = ctx.hueGET
  huePUT = ctx.huePUT
  _sseProbe = ctx._sseProbe
  app_key = ctx.app_key
  url = ctx.url
  callBack = ctx.callBack
  resources = ctx.resources
  _initEngine = ctx._initEngine
  enterCooldown = ctx.enterCooldown
  parseRetryAfter = ctx.parseRetryAfter
  refreshInFlight = ctx.refreshInFlight
  refreshBlockedUntil = ctx.refreshBlockedUntil
  bridgeHealthy = ctx.bridgeHealthy
  bridgeCoolUntil = ctx.bridgeCoolUntil
  bridgeNoticeAt = ctx.bridgeNoticeAt
  bridgeLastHealthy = ctx.bridgeLastHealthy
  cooldownDefault = ctx.cooldownDefault
  recent429 = ctx.recent429
  
end -- main()

function HUE:init(ip,key,cb) 
  setup() 
  main() 
  _initEngine(ip,key,cb)
end
