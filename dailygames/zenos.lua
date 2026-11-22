--[[
ZenOS integration: adds a launcher entry for this plugin.

ZenOS stores its App Launcher in modules/menu/app_launcher/model.lua. Entries of
type "plugin" call plugin[method](plugin) when tapped. ZenOS adds plugins that
were installed through ZenPM by itself; this covers manual installs (ZenFM, USB).

Every call is guarded, so nothing happens when ZenOS isn't installed or its
internals change.
]]

local ZenOS = {}

local MODEL = "modules/menu/app_launcher/model"

local function launcherModel()
    local model = package.loaded[MODEL]
    if not model then
        local ok, loaded = pcall(require, MODEL)
        model = ok and loaded or nil
    end
    if type(model) == "table" and type(model.ensure) == "function"
            and type(model.save) == "function" and type(model.next_id) == "function" then
        return model
    end
end

local function hasEntry(entries, key)
    for _, entry in ipairs(entries or {}) do
        if type(entry) == "table" then
            if entry.type == "plugin" and type(entry.plugin) == "table" and entry.plugin.key == key then
                return true
            end
            if entry.type == "folder" and hasEntry(entry.children, key) then
                return true
            end
        end
    end
    return false
end

local function pickIcon(label, preferred)
    local ok, icon = pcall(function()
        local ok_root, root = pcall(require, "common/plugin_root")
        return require("common/utils").suggestIcon(ok_root and root or nil, label, "lightning", false, preferred)
    end)
    return ok and type(icon) == "string" and icon or "lightning"
end

function ZenOS.isAvailable()
    return launcherModel() ~= nil
end

--- Points launcher entries for `key` whose method no longer exists on `plugin`
-- at `method` instead (e.g. an entry saved by an older version). ZenOS greys
-- out entries whose method it can't find.
-- Returns the number of entries fixed, or nil when ZenOS isn't available.
-- Also gives entries still on ZenOS's fallback icon ("lightning", used when it
-- can't match a name, e.g. for entries it adds after a ZenPM install) `icon`.
function ZenOS.repairLauncherEntries(key, plugin, method, label, icon)
    local model = launcherModel()
    if not model then return nil end
    local ok, fixed = pcall(function()
        local cfg = model.ensure()
        local count = 0
        local function walk(entries)
            for _, entry in ipairs(entries or {}) do
                if type(entry) == "table" then
                    local p = entry.plugin
                    if entry.type == "plugin" and type(p) == "table" and p.key == key then
                        if type(plugin[p.method]) ~= "function" then
                            p.method = method
                            count = count + 1
                        end
                        if icon and (entry.icon == nil or entry.icon == "lightning") then
                            local picked = pickIcon(label or entry.label, icon)
                            if picked ~= entry.icon and picked ~= "lightning" then
                                entry.icon = picked
                                count = count + 1
                            end
                        end
                    elseif entry.type == "folder" then
                        walk(entry.children)
                    end
                end
            end
        end
        walk(cfg.entries)
        if count > 0 then model.save(cfg) end
        return count
    end)
    return ok and fixed or nil
end

--- Adds a launcher entry unless one for `key` already exists.
-- opts: key (plugin name), method (plugin method to call), label, icon (preferred icon name)
-- Returns "added", "exists", or nil when ZenOS isn't available.
function ZenOS.addLauncherEntry(opts)
    local model = launcherModel()
    if not model then return nil end
    local ok, result = pcall(function()
        local cfg = model.ensure()
        if hasEntry(cfg.entries, opts.key) then
            return "exists"
        end
        cfg.entries[#cfg.entries + 1] = {
            id = model.next_id(cfg),
            type = "plugin",
            label = opts.label,
            icon = pickIcon(opts.label, opts.icon),
            plugin = { key = opts.key, method = opts.method },
        }
        model.save(cfg)
        return "added"
    end)
    return ok and result or nil
end

return ZenOS
