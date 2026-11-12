--https://github.com/LuaLS/lua-language-server/wiki/Annotations

---@meta

---Global fibaro API table
---@class fibaro
fibaro = {}

---Global hub reference (alias for fibaro)
---@type fibaro
hub = fibaro

---Global _emu reference
---@type table
_emu = {}

---Global api reference
---@type table
api = {}

---Call the hc3 API endpoint with a GET request
---@param path string The API endpoint path to call
---@return any|nil result The result of the API call, or nil if the call fails
---@return number status The HTTP status code
function api.get(path) end

---Call the hc3 API endpoint with a POST request
---@param path string The API endpoint path to call
---@param data table The data to send in the POST request
---@return any|nil result The result of the API call, or nil if the call fails
---@return number status The HTTP status code
function api.post(path, data) end

---Call the hc3 API endpoint with a PUT request
---@param path string The API endpoint path to called
---@param data table The data to send in the PUT request
---@return any|nil result The result of the API call, or nil if the call fails
---@return number status The HTTP status code
function api.put(path, data) end

---Call the hc3 API endpoint with a DELETE request
---@param path string The API endpoint path to call
---@return nil
---@return number status The HTTP status code
function api.delete(path) end

---Global __TAG variable for QuickApp identification used in log output
---@type string
__TAG = ""

---A simple ternary operator implementation.
---@param c any The condition
---@param t any The value to return if the condition is true
---@param f any The value to return if the condition is false
---@return any result t or f based on the condition
function __ternary(c, t, f) end

---Retrieves all devices from the system.
---@return table devices A table containing all device objects
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_devices() end

---Retrieves a specific device by its ID.
---@param deviceId number The ID of the device
---@return table|nil device The device object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_device(deviceId) end

---Retrieves a specific room by its ID.
---@param roomId number The ID of the room
---@return table|nil room The room object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_room(roomId) end

---Retrieves a specific scene by its ID.
---@param sceneId number The ID of the scene
---@return table|nil scene The scene object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_scene(sceneId) end

---Retrieves a global variable by its name.
---@param varName string The name of the global variable
---@return table|nil variable The global variable object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_global_variable(varName) end

---Retrieves a specific property of a device.
---@param deviceId number The ID of the device
---@param propertyName string The name of the property
---@return table|nil property The property object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_device_property(deviceId, propertyName) end

---Retrieves all devices of a specific type.
---@param type string The type of devices to retrieve
---@return table devices A table containing device objects of the specified type
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_devices_by_type(type) end

---Adds a debug message to the emulator's debug output.
---@param tag string The tag for the debug message
---@param msg string The message string
---@param typ string The type of message (e.g., "DEBUG", "ERROR")
---@return nil
function __fibaro_add_debug_message(tag, msg, typ) end

---Retrieves a specific alarm partition by its ID.
---@param id number The ID of the alarm partition
---@return table|nil partition The alarm partition object, or nil if not found
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_partition(id) end

---Retrieves all alarm partitions.
---@return table partitions A table containing all alarm partition objects
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_partitions() end

---Retrieves all breached alarm partitions.
---@return table partitions A table containing breached alarm partition objects
---@return number|nil status The HTTP status code, or nil if the call fails
function __fibaro_get_breached_partitions() end

---Pauses execution for a specified number of milliseconds.
---@param ms number The duration to sleep in milliseconds
---@return nil
function __fibaroSleep(ms) end

---Placeholder function, seems to indicate async handler usage.
---@param value boolean Unused parameter
---@return boolean result Always true
function __fibaroUseAsyncHandler(value) end

---Asserts that a parameter is of a specific type.
---Throws an error if the type does not match.
---@param param any The parameter to check
---@param typ string The expected type string (e.g., "number", "string")
---@return nil
function __assert_type(param, typ) end

---Sets a function to be called repeatedly at a specified delay.
---@param fun function The function to call
---@param delay number The delay in milliseconds between calls
---@return any ref A timer reference that can be used with clearInterval
function setInterval(fun, delay) end

---Sets a function to be called once after a specified delay.
---@param fun function The function to call
---@param delay number The delay in milliseconds
---@return any ref A timer reference that can be used with clearTimeout
function setTimeout(fun, delay) end

---Clears a timeout previously set with setTimeout.
---@param ref any The timer reference returned by setTimeout
---@return nil
function clearTimeout(ref) end

---Clears an interval previously set with setInterval.
---@param ref any The timer reference returned by setInterval
---@return nil
function clearInterval(ref) end

---Logs a debug message to the console with DEBUG prefix.
---@param tag string Name of tag, usually __TAG for QuickApps and _sceneId for Scenes
---@param ... any Arguments to be included in the message
---@return nil
function fibaro.debug(tag, ...) end

---Logs a trace message to the console with TRACE prefix.
---@param tag string Name of tag, usually __TAG for QuickApps and _sceneId for Scenes
---@param ... any Arguments to be included in the message
---@return nil
function fibaro.trace(tag, ...) end

---Logs a warning message to the console with WARNING prefix.
---@param tag string Name of tag, usually __TAG for QuickApps and _sceneId for Scenes
---@param ... any Arguments to be included in the message
---@return nil
function fibaro.warning(tag, ...) end

---Logs an error message to the console with ERROR prefix.
---@param tag string Name of tag, usually __TAG for QuickApps and _sceneId for Scenes
---@param ... any Arguments to be included in the message
---@return nil
function fibaro.error(tag, ...) end

---Retrieves all alarm partitions.
---@return table partitions A table of alarm partition objects
function fibaro.getPartitions() end

---Manages alarm partitions or the main house alarm.
---If arg1 is a string, it controls the house alarm ("arm" or "disarm").
---If arg1 is a number (partition ID), it controls that specific partition.
---@param arg1 number|string Either a partition ID (number) or an action string ("arm", "disarm") for the house alarm
---@param action? string The action to perform ("arm" or "disarm") if arg1 is a partition ID
---@return nil
function fibaro.alarm(arg1, action) end

---Sends an alert notification.
---@param alertType string The type of alert ("email", "push", "simplePush")
---@param ids table A table of user IDs or device IDs (for push) to send the notification to
---@param notification string The notification message string
---@return nil
function fibaro.alert(alertType, ids, notification) end

---Emits a custom event.
---@param name string The name of the custom event
---@return nil
function fibaro.emitCustomEvent(name) end

---Calls an action on a device or a table of devices.
---@param deviceId number|table A device ID (number) or a table of device IDs
---@param action string The name of the action to call
---@param ... any Arguments to pass to the action
---@return any|nil result The result of the API call for a single device, or nil for multiple devices
function fibaro.call(deviceId, action, ...) end

---Calls an action on a device or a table of devices using the hc3 API endpoint.
---@param deviceId number|table A device ID (number) or a table of device IDs
---@param action string The name of the action to call
---@param ... any Arguments to pass to the action
---@return any|nil result The result of the API call for a single device, or nil for multiple devices
function fibaro.callhc3(deviceId, action, ...) end

---Calls a group action.
---@param actionName string The name of the group action
---@param actionData table A table containing data for the group action
---@return table|nil devices A table of devices affected by the action if successful (status 202), otherwise nil
function fibaro.callGroupAction(actionName, actionData) end

---Gets a property value and its last modification time for a device.
---@param deviceId number The ID of the device
---@param prop string The name of the property
---@return any|nil value The property value, or nil if not found
---@return number|nil modified The last modified timestamp, or nil if not found
function fibaro.get(deviceId, prop) end

---Gets a property value for a device.
---@param deviceId number The ID of the device
---@param propertyName string The name of the property
---@return any|nil value The property value, or nil if not found
function fibaro.getValue(deviceId, propertyName) end

---Gets the type of a device.
---@param deviceId number The ID of the device
---@return string|nil type The device type string, or nil if not found
function fibaro.getType(deviceId) end

---Gets the name of a device.
---@param deviceId number The ID of the device
---@return string|nil name The device name string, or nil if not found
function fibaro.getName(deviceId) end

---Gets the room ID for a device.
---@param deviceId number The ID of the device
---@return number|nil roomId The room ID, or nil if not found or device has no room
function fibaro.getRoomID(deviceId) end

---Gets the section ID for a device.
---It first finds the device's room ID, then the section ID of that room.
---@param deviceId number The ID of the device
---@return number|nil sectionId The section ID, or nil if device or room not found
function fibaro.getSectionID(deviceId) end

---Gets the name of a room by its ID.
---@param roomId number The ID of the room
---@return string|nil name The room name string, or nil if not found
function fibaro.getRoomName(roomId) end

---Gets the name of the room a device is in.
---@param deviceId number The ID of the device
---@param propertyName? any Unused parameter (likely a typo or leftover)
---@return string|nil name The room name string, or nil if device or room not found
function fibaro.getRoomNameByDeviceID(deviceId, propertyName) end

---Gets IDs of devices based on a filter.
---If no filter is provided, returns IDs of all devices.
---The filter can specify properties, interfaces, and other device attributes.
---@param filter? table A table specifying filter criteria
---@return table deviceIds A table of device IDs matching the filter
function fibaro.getDevicesID(filter) end

---Extracts IDs from a table of device objects.
---Filters out devices with ID <= 3.
---@param devices table A table of device objects
---@return table deviceIds A table containing the IDs of the valid devices
function fibaro.getIds(devices) end

---Gets the value and last modification time of a global variable.
---@param name string The name of the global variable
---@return string|nil value The variable's value, or nil if not found
---@return number|nil modified The last modified timestamp, or nil if not found
function fibaro.getGlobalVariable(name) end

---Sets the value of a global variable.
---This will also invoke scenes that depend on this variable.
---@param name string The name of the global variable
---@param value string The new value for the variable
---@return any result The result of the API call
function fibaro.setGlobalVariable(name, value) end

---Executes or kills scenes.
---@param action string The action to perform ("execute" or "kill")
---@param ids table A table of scene IDs
---@return nil
function fibaro.scene(action, ids) end

---Activates a user profile.
---@param action string Should be "activeProfile"
---@param id number The ID of the profile to activate
---@return any result The result of the API call
function fibaro.profile(action, id) end

---Sets a timeout to execute an action, with an optional error handler.
---This is a wrapper around the global setTimeout, ensuring type checks.
---@param timeout number The delay in milliseconds
---@param action function The function to execute after the timeout
---@param errorHandler? function An optional function to call if the action errors
---@return any ref A timer reference
function fibaro.setTimeout(timeout, action, errorHandler) end

---Clears a timeout previously set with fibaro.setTimeout or the global setTimeout.
---@param ref any The timer reference
---@return nil
function fibaro.clearTimeout(ref) end

---Wakes up a dead Z-Wave device.
---This typically calls an action on the Z-Wave controller (device ID 1).
---@param deviceID number The ID of the dead device to wake up
---@return nil
function fibaro.wakeUpDeadDevice(deviceID) end

---Pauses execution for a specified number of milliseconds.
---@param ms number The duration to sleep in milliseconds
---@return nil
function fibaro.sleep(ms) end

---Set async call mode for fibaro.call
---@param value boolean Whether to use async handler
---@return nil
function fibaro.useAsyncHandler(value) end

---Checks if any partition is breached.
---@return boolean breached True if any partition is breached
function fibaro.isHomeBreached() end

---Checks if a specific partition is breached.
---@param partitionId number The ID of the partition to check
---@return boolean|nil breached True if partition is breached, nil if partition not found
function fibaro.isPartitionBreached(partitionId) end

---Gets the armed state of a specific alarm partition.
---@param partitionId number The ID of the partition
---@return string|nil state The partition state ("armed" or "disarmed"), or nil if not found
function fibaro.getPartitionArmState(partitionId) end

---Returns the armed state of the home.
---@return string state The home armed state ("armed", "disarmed", or "partially_armed")
function fibaro.getHomeArmState() end

---Retrieves a scene variable (only available in scenes).
---@param name string The name of the scene variable
---@return any|nil value The variable value, or nil if not found
function fibaro.getSceneVariable(name) end

---Sets a scene variable (only available in scenes).
---@param name string The name of the scene variable
---@param value any The value to set
---@return nil
function fibaro.setSceneVariable(name, value) end

---Calls QuickApp UI element, button or slider
---@param id number QA deviceId
---@param action string Action to perform, "onReleased" or "onChanged"
---@param element string Name of UI element
---@param value table {value={<value>}}
---@return nil
function fibaro.callUI(id, action, element, value) end

-------------------------------
-- Network API
-------------------------------

---@class net
net = {}

---@class HTTPClient
---@field request fun(self: HTTPClient, address: string, params?: table): nil
HTTPClient = {}

---Creates an HTTP client object
---@param options? table Options for HTTP request. The only option that can be set is a timeout expressed in milliseconds
---@return HTTPClient client
function net.HTTPClient(options) end

---Method to execute HTTP/HTTPS queries.
---@param address string The address to which the query is to be executed. e.g. http://127.0.0.1/api/users, https://google.com
---@param params? table The argument of the table type. The argument may contain options for the query and/or feedback functions
---@return nil
function HTTPClient:request(address, params) end