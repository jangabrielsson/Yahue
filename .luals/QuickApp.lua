--https://github.com/LuaLS/lua-language-server/wiki/Annotations

---@meta

---Overrides the global print function to use fibaro.debug for logging
---@param ... any Arguments to be logged
---@return nil
function print(...) end

---Creates a class constructor function that supports inheritance
---@param name string The name of the class to create
---@return function constructor A function that can be used to set up inheritance
function class(name) end

---Global plugin table for QuickApp management
---@class plugin
---@field mainQA QuickApp Reference to the main QuickApp instance
---@field mainDeviceId number The main device ID
plugin = {}

---Retrieves a device by its ID
---@param deviceId number The ID of the device to retrieve
---@return table device Device object from the HC3 API
---@return number status HTTP status code
function plugin.getDevice(deviceId) end

---Deletes a device by its ID
---@param deviceId number The ID of the device to delete
---@return any result Result of the delete operation
---@return number status HTTP status code
function plugin.deleteDevice(deviceId) end

---Gets a specific property of a device
---@param deviceId number The ID of the device
---@param propertyName string The name of the property to retrieve
---@return any value The property value
function plugin.getProperty(deviceId, propertyName) end

---Gets all child devices of a parent device
---@param deviceId number The ID of the parent device
---@return table children Array of child device objects
---@return number status HTTP status code
function plugin.getChildDevices(deviceId) end

---Creates a new child device
---@param opts table Options for creating the child device
---@return table device The created child device object
---@return number status HTTP status code
function plugin.createChildDevice(opts) end

---Restarts a QuickApp plugin
---@param id? number The device ID to restart (optional, defaults to mainDeviceId)
---@return any result Result of the restart operation
---@return number status HTTP status code
function plugin.restart(id) end

---Base class for all QuickApp devices
---@class QuickAppBase
---@field id number The deviceID of the QA
---@field name string The name of the QA
---@field type string The type of the device
---@field enabled boolean Whether the device is enabled
---@field parentId number The deviceID of the parent device
---@field roomID number The room ID where the device is located
---@field properties table Device properties table
---@field interfaces table<string> Device interfaces
---@field uiCallbacks table<string, table<string, function>> UI callback functions
QuickAppBase = {}

---Main QuickApp class that can have child devices
---@class QuickApp : QuickAppBase
---@field childDevices table<number, QuickAppChild> Mapping of childDeviceIDs to QuickAppChild objects
---@field childsInitialized boolean Whether child devices have been initialized
QuickApp = {}

---Child device class for QuickApp instances
---@class QuickAppChild : QuickAppBase
---@field parent QuickApp Reference to the parent QuickApp
QuickAppChild = {}

---Constructor for QuickAppBase class
---@param dev table Device object containing device properties and metadata
---@return nil
function QuickAppBase:__init(dev) end

---Called when QuickApp starts.
---Override this method in your QuickApp to perform initialization.
---@return nil
function QuickAppBase:onInit() end

---Logs a debug message with the device tag
---@param ... any Arguments to be logged
---@return nil
function QuickAppBase:debug(...) end

---Logs a trace message with the device tag
---@param ... any Arguments to be logged
---@return nil
function QuickAppBase:trace(...) end

---Logs a warning message with the device tag
---@param ... any Arguments to be logged
---@return nil
function QuickAppBase:warning(...) end

---Logs an error message with the device tag
---@param ... any Arguments to be logged
---@return nil
function QuickAppBase:error(...) end

---Registers a UI callback function for a specific element and event type
---@param elm string The UI element name
---@param typ string The event type (e.g., "onReleased", "onChanged")
---@param fun function The callback function to register
---@return nil
function QuickAppBase:registerUICallback(elm, typ, fun) end

---Sets up UI callbacks based on device properties.
---Reads uiCallbacks from device properties and registers them.
---@return nil
function QuickAppBase:setupUICallbacks() end

---Alias for setupUICallbacks
---@return nil
function QuickAppBase:registerUICallbacks() end

---Calls an action method on the QuickApp if it exists
---@param name string The name of the action/method to call
---@param ... any Arguments to pass to the action method
---@return any|nil result Result of the action method or nil if method doesn't exist
function QuickAppBase:callAction(name, ...) end

---Updates a device property and sends the update to the HC3 system
---@param name string The name of the property to update
---@param value any The new value for the property
---@return nil
function QuickAppBase:updateProperty(name, value) end

---Updates a UI view element property
---@param elm string The UI element name
---@param prop string The property name to update
---@param value any The new value for the property
---@return nil
function QuickAppBase:updateView(elm, prop, value) end

---Checks if the device has a specific interface
---@param name string The interface name to check for
---@return boolean hasInterface True if the device has the interface, false otherwise
function QuickAppBase:hasInterface(name) end

---Adds new interfaces to the device
---@param values table<string> Table of interface names to add
---@return nil
function QuickAppBase:addInterfaces(values) end

---Removes interfaces from the device
---@param values table<string> Table of interface names to remove
---@return nil
function QuickAppBase:deleteInterfaces(values) end

---Updates device interfaces via API call
---@param action string The action to perform ("add" or "delete")
---@param interfaces table<string> Table of interfaces to add or remove
---@return nil
function QuickAppBase:updateInterfaces(action, interfaces) end

---Sets the device name
---@param name string The new name for the device
---@return nil
function QuickAppBase:setName(name) end

---Sets the device enabled state
---@param enabled boolean Boolean indicating if device should be enabled
---@return nil
function QuickAppBase:setEnabled(enabled) end

---Sets the device visibility
---@param visible boolean Boolean indicating if device should be visible
---@return nil
function QuickAppBase:setVisible(visible) end

---Sets a QuickApp variable value.
---The variable is created if it's not already defined. The variable can be used in the device configuration or in the code of the device.
---@param name string The variable name
---@param value any The variable value
---@return nil
function QuickAppBase:setVariable(name, value) end

---Gets a QuickApp variable value.
---The method is used to get the Quick App variables. Variables can be added from the device configuration or the method QuickApp:setVariable.
---@param name string The variable name
---@return any value The variable value or empty string if not found
function QuickAppBase:getVariable(name) end

---Sets a value in internal storage
---@param key string The storage key
---@param val any The value to store
---@param hidden? boolean Boolean indicating if the variable should be hidden
---@return number status HTTP status code
function QuickAppBase:internalStorageSet(key, val, hidden) end

---Gets a value from internal storage
---@param key? string The storage key (optional, if nil returns all variables)
---@return any|nil value The stored value or nil if not found
function QuickAppBase:internalStorageGet(key) end

---Removes a variable from internal storage
---@param key string The storage key to remove
---@return any result Result of the delete operation
function QuickAppBase:internalStorageRemove(key) end

---Clears all variables from internal storage
---@return any result Result of the delete operation
function QuickAppBase:internalStorageClear() end

---Programmatically triggers a UI action for testing purposes
---@param eventType string The type of UI event to trigger
---@param elementName string The name of the UI element
---@param arg? any Optional argument value for the event
---@return nil
function QuickAppBase:UIAction(eventType, elementName, arg) end

---Constructor for QuickApp class (main QuickApp instance)
---@param dev table Device object containing device properties and metadata
---@return nil
function QuickApp:__init(dev) end

---Initializes child devices for this QuickApp
---@param map? table<string, function> Optional mapping table of device types to constructor functions
---@return nil
function QuickApp:initChildDevices(map) end

---Creates a new child device for this QuickApp
---@param options table Options table containing device configuration
---@param classRepresentation? function Optional class constructor for the child device
---@return QuickAppChild child The created child device instance
function QuickApp:createChildDevice(options, classRepresentation) end

---Removes a child device of this QuickApp (own children only; returns
---nothing for unknown/foreign ids)
---@param id number The device id of the child to remove
---@return any data
---@return number|nil status
function QuickApp:removeChildDevice(id) end

---Constructor for QuickAppChild class (child device of a QuickApp)
---@param dev table Device object containing device properties and metadata
---@return nil
function QuickAppChild:__init(dev) end

---@class RefreshStateSubscriber
RefreshStateSubscriber = {}

---Constructor for RefreshStateSubscriber class
---Initializes the subscriber for refresh state events
---@return nil
function RefreshStateSubscriber:__init() end

---Subscribes to refresh state events with a filter and handler
---@param filter function Function to filter events (return true to handle)
---@param handler function Function to handle matching events
---@return table subscription Subscription object
function RefreshStateSubscriber:subscribe(filter, handler) end

---Unsubscribes from refresh state events
---@param subscription table The subscription object to remove
---@return nil
function RefreshStateSubscriber:unsubscribe(subscription) end

---Starts the refresh state subscriber
---@return nil
function RefreshStateSubscriber:run() end

---Stops the refresh state subscriber
---@return nil
function RefreshStateSubscriber:stop() end

---Global handler for device actions.
---Routes actions to the appropriate QuickApp or child device.
---@param id number Device ID where the action was called
---@param event table Event object containing action details
---@return any|nil result Result of the action call
function onAction(id, event) end

---Global handler for UI events.
---Routes UI events to the appropriate QuickApp callbacks.
---@param id number Device ID where the UI event occurred
---@param event table Event object containing UI event details
---@return nil
function onUIEvent(id, event) end