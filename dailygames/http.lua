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

--- KOReader's json module decodes JSON null to a sentinel (a function), not
-- nil. Remove those (recursively) so `field or default` and type checks work.
function Http.clean(v)
    if type(v) == "table" then
        for k, x in pairs(v) do
            if type(x) == "function" or (JSON.null ~= nil and x == JSON.null) then
                v[k] = nil
            else
                Http.clean(x)
            end
        end
    end
    return v
end

--- json.decode + clean; returns nil on error.
function Http.decode(raw)
    local ok, data = pcall(JSON.decode, raw)
    if not ok then return nil end
    return Http.clean(data)
end

--- Performs a request.
-- opts: url, method ("GET"), headers (table), body (table, sent as JSON), timeout (seconds),
--       raw (return the body text instead of decoded JSON)
-- Returns decoded JSON (or nil), HTTP status code (nil on network failure), error message.
function Http.request(opts)
    local sink = {}
    local headers = {
        ["Accept"] = opts.raw and "*/*" or "application/json",
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
    if opts.raw then
        return raw, code -- caller wants the body as text (e.g. HTML)
    end
    if raw ~= "" then
        local decoded = Http.decode(raw)
        if type(decoded) == "table" then
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

--- Streams a large response through on_chunk(text) without keeping it in
-- memory. on_chunk returns false to stop early (counts as success).
-- Returns the HTTP status code (200 when stopped early), or nil + error.
function Http.stream(url, on_chunk, block_timeout, total_timeout)
    local stopped = false
    local function sink(chunk, err)
        if chunk == nil then return 1 end
        if on_chunk(chunk) == false then
            stopped = true
            return nil, "stopped"
        end
        return 1
    end
    if has_socketutil then socketutil:set_timeout(block_timeout or 15, total_timeout or 300) end
    local ok, code = pcall(function()
        return socket.skip(1, http.request {
            url = url,
            headers = { ["User-Agent"] = Http.user_agent, ["Accept"] = "application/json" },
            sink = sink,
        })
    end)
    if has_socketutil then socketutil:reset_timeout() end
    if stopped then return 200 end
    if not ok then return nil, tostring(code) end
    if type(code) ~= "number" then return nil, tostring(code or "network error") end
    return code
end

--- Downloads a URL to a file (e.g. a product photo). Returns true or nil + error.
function Http.download(url, path)
    local f, open_err = io.open(path .. ".part", "wb")
    if not f then return nil, open_err end
    if has_socketutil then socketutil:set_timeout(15, 30) end
    local ok, code = pcall(function()
        return socket.skip(1, http.request {
            url = url,
            headers = { ["User-Agent"] = Http.user_agent },
            sink = ltn12.sink.file(f), -- closes f when done
        })
    end)
    if has_socketutil then socketutil:reset_timeout() end
    if not ok or code ~= 200 then
        os.remove(path .. ".part")
        return nil, ok and ("HTTP " .. tostring(code)) or tostring(code)
    end
    os.rename(path .. ".part", path)
    return true
end

return Http
