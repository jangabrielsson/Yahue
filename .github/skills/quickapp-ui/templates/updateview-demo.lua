--%%name:UI Demo
--%%type:com.fibaro.genericDevice
--%%property:useUiView=true
--%%property:typeTemplateInitialized=true
--%%description:"Exercises updateView on every UI element type — run with flua --ui"

--%%u:{label='statusLbl',text='Starting...'}
--%%u:{button='btn',text='Press me',onReleased='btnPressed'}
--%%u:{slider='setpoint',text='Setpoint',min='0',max='30',step='0.5',value='21',unit='°C',onChanged='sliderChanged'}
--%%u:{switch='auto',text='Auto',value='false',onToggleOn='autoOn',onToggleOff='autoOff'}
--%%u:{select='mode',text='Mode',onToggled='modePicked',options={{type='option',text='Eco',value='eco'},{type='option',text='Manual',value='manual'},{type='option',text='Turbo',value='turbo'}}}
--%%u:{multi='zones',text='Zones',onToggled='zonesPicked',options={{type='option',text='Kitchen',value='k'},{type='option',text='Hall',value='h'},{type='option',text='Bedroom',value='b'}}}

-- Callbacks receive event = {deviceId, eventType, elementName, values}

function QuickApp:btnPressed(event)
  self:debug("button pressed, values:", json.encode(event.values))  -- empty
  self:updateView("statusLbl", "text", "<font color='green'>Button pressed</font>")
end

function QuickApp:sliderChanged(event)
  local v = tonumber(event.values[1])  -- string!
  self:updateView("setpoint", "value", tostring(v))
  self:updateView("statusLbl", "text", "Setpoint " .. tostring(v))
end

function QuickApp:autoOn(event)
  self:debug("auto on, value:", json.encode(event.values[1]))  -- "true" (string)
  self:updateView("auto", "value", "true")
end

function QuickApp:autoOff(event)
  self:updateView("auto", "value", "false")
end

function QuickApp:modePicked(event)
  -- selectedItem matches the option VALUE ("eco"/"manual"/"turbo")
  self:updateView("mode", "selectedItem", event.values[1])
end

function QuickApp:zonesPicked(event)
  -- multi: event.values[1] is the LIST of picked values
  self:updateView("zones", "selectedItems", event.values[1])
end

-- Demonstrates the updateView calls a QA makes programmatically

function QuickApp:onInit()
  self:debug("UI demo running, id", self.id)
  setTimeout(function()
    self:updateView("statusLbl", "text", "Slider + switch + select updated")
    self:updateView("setpoint", "value", "23.5")
    self:updateView("auto", "value", "true")
    self:updateView("mode", "selectedItem", "manual")
    self:updateView("zones", "selectedItems", {"h", "b"})
    self:updateView("btn", "text", "Pressed by QA")
  end, 1000)
  setTimeout(function()
    self:updateView("statusLbl", "visible", false)  -- hide the label
    self:updateView("statusLbl", "visible", true)
    self:updateView("mode", "options", {{type='option',text='Eco',value='eco'},
                                         {type='option',text='Boost',value='boost'}})
    self:updateView("mode", "selectedItem", "boost")
    self:debug("demo done")
    _FLUA.exit(0)
  end, 3000)
end
