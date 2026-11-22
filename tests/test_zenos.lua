dofile(STUBS)
-- Fake ZenOS launcher model with the same API as zenos.koplugin/modules/menu/app_launcher/model.lua
local cfg = { entries = { { id = "al_1", type = "plugin", label = "ZenPM", plugin = { key = "zenpm", method = "open" } } }, next_id = 1 }
local saves = 0
package.loaded["modules/menu/app_launcher/model"] = {
    ensure = function() return cfg end,
    save = function(c) saves = saves + 1; cfg = c; return c end,
    next_id = function(c) c.next_id = c.next_id + 1; return "al_" .. c.next_id end,
}
package.loaded["common/utils"] = { suggestIcon = function(_, label, fallback, _, preferred) return preferred or fallback end }

local P = dofile(PLUGDIR .. "/main.lua")
local plug = P:new { ui = { menu = { registerToMainMenu = function() end } } }
runq()
assert(#cfg.entries == 2, "entry added")
local e = cfg.entries[2]
assert(e.type == "plugin" and e.label == "Daily Games" and e.plugin.key == "dailygames" and e.plugin.method == "open" and e.icon == "quick_puzzle" and e.id == "al_2")
assert(STORE.zenos_launcher_added == true)

-- Second start: no duplicate. After the user removes it, it stays removed.
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
table.remove(cfg.entries, 2)
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
assert(#cfg.entries == 1 and saves == 1)

-- Existing entry (e.g. ZenOS added it after a ZenPM install) is not duplicated.
STORE.zenos_launcher_added = nil
cfg.entries[2] = { id = "al_9", type = "folder", label = "Games", children = { { id = "al_10", type = "plugin", label = "DG", plugin = { key = "dailygames", method = "open" } } } }
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
assert(#cfg.entries == 2 and saves == 1)

-- ZenOS picks the first callable of these as the plugin's entry point (plugin_scan.lua).
for _, m in ipairs { "onShow", "show", "open", "launch", "onOpen" } do
    if type(plug[m]) == "function" then
        assert(m == "open", "ZenOS would call " .. m)
        break
    end
end
plug:open(); assert(top()._name == "ButtonDialog", "open shows hub")

-- Without ZenOS nothing happens and it retries next start.
package.loaded["modules/menu/app_launcher/model"] = nil
STORE.zenos_launcher_added = nil
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
assert(STORE.zenos_launcher_added == nil)
-- Stale entry from an older version (method that no longer exists) is repaired.
package.loaded["modules/menu/app_launcher/model"] = {
    ensure = function() return cfg end,
    save = function(c) saves = saves + 1; cfg = c; return c end,
    next_id = function(c) c.next_id = c.next_id + 1; return "al_" .. c.next_id end,
}
cfg.entries = { { id = "al_1", type = "plugin", label = "Daily Games", plugin = { key = "dailygames", method = "onGone" } } }
local before = saves
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
assert(cfg.entries[1].plugin.method == "open" and #cfg.entries == 1 and saves > before, "stale entry repaired")
-- v1.0.0 entries used "launch": still works and is left alone.
cfg.entries[1].plugin.method = "launch"; before = saves
P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
assert(cfg.entries[1].plugin.method == "launch" and saves == before)
local p2 = P:new { ui = { menu = { registerToMainMenu = function() end } } }; runq()
p2:launch(); assert(top()._name == "ButtonDialog", "launch alias shows hub")
print("ZENOS PASSED")
