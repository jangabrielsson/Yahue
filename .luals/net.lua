--https://github.com/LuaLS/lua-language-server/wiki/Annotations

---@meta

---The asynchronous HTTP client (net.HTTPClient). Responses arrive through
---success/error callbacks on the pump; SSE streams fire success per raw
---event block.
---@class HTTPClient
---@field request fun(self: HTTPClient, url: string, params?: HTTPRequestParams): number
---@class HTTPRequestParams
---@field success fun(resp: HTTPResponse) | nil
---@field error fun(err: string) | nil
---@field options HTTPOptions | nil
---@class HTTPOptions
---@field method string | nil
---@field headers table<string, string> | nil
---@field data string | nil
---@field checkCertificate boolean | nil true = verify HTTPS certificates (default)
---@field timeout number | nil per-request timeout in ms (overrides the constructor's)
---@class HTTPResponse
---@field status number
---@field data string
---@field headers table<string, string>

---The asynchronous TCP client (net.TCPSocket). Operations run in worker
---threads; callbacks arrive through the pump.
---@class TCPSocket
---@field connect fun(self: TCPSocket, ip: string, port: number, callbacks?: TCPCallbacks)
---@field send fun(self: TCPSocket, data: string, callbacks?: TCPCallbacks)
---@field read fun(self: TCPSocket, callbacks?: TCPCallbacks) reads one data package
---@field readUntil fun(self: TCPSocket, delimiter: string, callbacks?: TCPCallbacks)
---@field close fun(self: TCPSocket)
---@class TCPCallbacks
---@field success fun(data?: string) | nil
---@field error fun(err: string) | nil

---The asynchronous UDP client (net.UDPSocket).
---@class UDPSocket
---@field sendTo fun(self: UDPSocket, data: string, ip: string, port: number, callbacks?: TCPCallbacks)
---@field receive fun(self: UDPSocket, callbacks?: TCPCallbacks)
---@field close fun(self: UDPSocket)

---WebSocket client (net.WebSocketClient) and its TLS twin
---(net.WebSocketClientTls — certificate verification OFF by default, like
---the HC3). Events: "connected", "disconnected", "error" (message),
---"dataReceived" (data, isBinary).
---@class WebSocketClient
---@field connect fun(self: WebSocketClient, url: string, headers?: table<string, string>, options?: WebSocketOptions)
---@field send fun(self: WebSocketClient, data: string) text frame
---@field sendBinary fun(self: WebSocketClient, data: string) binary frame (latin-1 encoded bytes)
---@field isOpen fun(self: WebSocketClient): boolean
---@field close fun(self: WebSocketClient)
---@field addEventListener fun(self: WebSocketClient, event: "connected"|"disconnected"|"error"|"dataReceived", callback: fun(...: any))
---@class WebSocketOptions
---@field checkCertificate boolean | nil true opts back into TLS verification
---@class WebSocketClientTls: WebSocketClient

---net.HTTPServer / net.TCPServer / net.UDPServer / net.WebSocketServer:
---local in-QA servers for fixtures. The handler's return value is the reply
---(HTTP: a {status=,body=,headers=} table or a string; TCP/UDP: a string;
---WebSocket: a string).
---@class ServerBase
---@field listen fun(self: ServerBase, port: number, handler: fun(...: any): any): ServerBase
---@field close fun(self: ServerBase)

---The HC3-style asynchronous network layer — real network in every flua
---mode (offline simulates only the HC3, not the LAN).
---@class net
---@field HTTPClient fun(options?: { timeout?: number }): HTTPClient
---@field TCPSocket fun(options?: { timeout?: number }): TCPSocket
---@field UDPSocket fun(options?: { broadcast?: boolean, timeout?: number }): UDPSocket
---@field WebSocketClient fun(options?: { timeout?: number }): WebSocketClient
---@field WebSocketClientTls fun(options?: { timeout?: number }): WebSocketClientTls
---@field HTTPServer fun(): ServerBase
---@field TCPServer fun(): ServerBase
---@field UDPServer fun(): ServerBase
---@field WebSocketServer fun(): ServerBase
net = {}
