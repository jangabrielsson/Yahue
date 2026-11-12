--https://github.com/LuaLS/lua-language-server/wiki/Annotations

---@meta

---The HC3 REST API surface (hybrid sim/HC3 dispatch in flua).
---Each call returns (data, status); data is nil on failures.
---@class api
---@field get fun(url: string, body?: any): any, number
---@field post fun(url: string, body?: any): any, number
---@field put fun(url: string, body?: any): any, number
---@field delete fun(url: string, body?: any): any, number
---@field hc3 api_hc3 Direct calls to the real HC3 (bypasses the hybrid dispatch)
---@field registerEndpoint fun(method: string, pattern: string, handler: (fun(req: EndpointRequest): any, number), override?: boolean): number Emulate (or, with override=true, REPLACE) a REST endpoint — offline sim only
api = {}

---The request a registered endpoint handler receives.
---@class EndpointRequest
---@field method string
---@field path string The path without the query string
---@field params table<string, string> {name} segments captured from the path
---@field query table<string, string[]> Parsed query values
---@field body any

---@class api_hc3
---@field get fun(url: string, body?: any): any, number
---@field post fun(url: string, body?: any): any, number
---@field put fun(url: string, body?: any): any, number
---@field delete fun(url: string, body?: any): any, number
api_hc3 = {}

---@class json.util
---@field InitArray fun(value: any): any

---@class json
---@field encode fun(value: any): string
---@field decode fun(text: string): any
---@field util json.util
---@field array fun(): any
json = {}
