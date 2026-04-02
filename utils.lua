-- HueV2Utils.lua — Color and math utilities for YahueV2
fibaro.engine = fibaro.engine or {}
local HUE = fibaro.engine

-- Named colors → CIE xy gamut C
HUE.xyColors = {
  red     = {x=0.675,  y=0.322},
  green   = {x=0.409,  y=0.518},
  blue    = {x=0.167,  y=0.040},
  white   = {x=0.3227, y=0.3290},
  warm    = {x=0.5140, y=0.4147},
  cool    = {x=0.2398, y=0.2448},
  yellow  = {x=0.4432, y=0.5154},
  orange  = {x=0.6114, y=0.3697},
  purple  = {x=0.2724, y=0.1341},
  pink    = {x=0.3866, y=0.2247},
  cyan    = {x=0.1715, y=0.3546},
}

-- RGB (0-255) → CIE xy  (Wide gamut D65)
function HUE:rgbToXy(r, g, b)
  r = r / 255; g = g / 255; b = b / 255
  r = r > 0.04045 and ((r + 0.055) / 1.055) ^ 2.4 or r / 12.92
  g = g > 0.04045 and ((g + 0.055) / 1.055) ^ 2.4 or g / 12.92
  b = b > 0.04045 and ((b + 0.055) / 1.055) ^ 2.4 or b / 12.92
  local X = r * 0.664511 + g * 0.154324 + b * 0.162028
  local Y = r * 0.283881 + g * 0.668433 + b * 0.047685
  local Z = r * 0.000088 + g * 0.072310 + b * 0.986039
  local s = X + Y + Z
  if s == 0 then return 0.3227, 0.3290 end
  return X / s, Y / s
end

-- CIE xy + brightness (0-100) → RGB (0-255)
function HUE:xyToRgb(x, y, bri)
  bri = (bri or 100) / 100
  local z = 1.0 - x - y
  local Y = bri
  local X = y ~= 0 and (Y / y) * x or 0
  local Z = y ~= 0 and (Y / y) * z or 0
  local r =  X * 1.656492 - Y * 0.354851 - Z * 0.255038
  local g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
  local b =  X * 0.051713 - Y * 0.121364 + Z * 1.011530
  local function gamma(v)
    v = math.max(0, v)
    return v <= 0.0031308 and 12.92 * v or 1.055 * v ^ (1 / 2.4) - 0.055
  end
  r = gamma(r); g = gamma(g); b = gamma(b)
  local mx = math.max(r, g, b, 1)
  return math.floor(r / mx * 255 + 0.5),
         math.floor(g / mx * 255 + 0.5),
         math.floor(b / mx * 255 + 0.5)
end

-- HSV (h:0-360, s:0-100, v:0-100) → RGB (0-255)
function HUE:hsvToRgb(h, s, v)
  s = s / 100; v = v / 100
  local i = math.floor(h / 60) % 6
  local f = h / 60 - math.floor(h / 60)
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local r, g, b
  if     i == 0 then r,g,b = v,t,p
  elseif i == 1 then r,g,b = q,v,p
  elseif i == 2 then r,g,b = p,v,t
  elseif i == 3 then r,g,b = p,q,v
  elseif i == 4 then r,g,b = t,p,v
  else              r,g,b = v,p,q end
  return math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5)
end

-- Color temperature conversions
function HUE:kelvinToMired(k) return math.floor(1000000 / k + 0.5) end
function HUE:miredToKelvin(m) return math.floor(1000000 / m + 0.5) end
