--[[
Small JSON-over-HTTP(S) helper built on KOReader's bundled LuaSocket/LuaSec.
Replaces shelling out to `curl -k`, which skipped TLS verification and built
shell commands from strings.
]]

local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local has_socketutil, socketutil = pcall(require, "socketutil")

local Http = {
    user_agent = "KOReader-DailyGames/1.0",
}

--- Performs a request.
-- opts: url, method ("GET"), headers (table), body (table, sent as JSON), timeout (seconds)
-- Returns decoded JSON (or nil), HTTP status code (nil on network failure), error message.
function Http.request(opts)
    local sink = {}
    local headers = {
        ["Accept"] = "application/json",
        ["User-Agent"] = Http.user_agent,
    }
    for k, v in pairs(opts.headers or {}) do
        headers[k] = v
    end

    local req = {
        url = opts.url,
        method = opts.method or "GET",
        headers = headers,
        sink = ltn12.sink.table(sink),
    }
    if opts.body ~= nil then
        local body = JSON.encode(opts.body)
        req.source = ltn12.source.string(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#body)
    end

    local timeout = opts.timeout or 10
    if has_socketutil then
        socketutil:set_timeout(timeout, timeout * 2)
    end
    local ok, code = pcall(function()
        return socket.skip(1, http.request(req))
    end)
    if has_socketutil then
        socketutil:reset_timeout()
    end

    if not ok then
        return nil, nil, tostring(code)
    end
    if type(code) ~= "number" then
        return nil, nil, tostring(code or "network error")
    end

    local data
    local raw = table.concat(sink)
    if raw ~= "" then
        local decoded_ok, decoded = pcall(JSON.decode, raw)
        if decoded_ok and type(decoded) == "table" then
            data = decoded
        end
    end
    return data, code
end

--- GETs a JSON document. Returns the table, or nil + error message.
function Http.getJson(url, headers)
    local data, code, err = Http.request { url = url, headers = headers }
    if not code then
        return nil, err
    end
    if code ~= 200 or not data then
        return nil, "HTTP " .. tostring(code)
    end
    return data
end

return Http
