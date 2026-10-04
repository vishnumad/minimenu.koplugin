--[[--
The default menu: seeded on first install and used as the starting items of
every "New menu…". Only actions this device supports are included.
]]

local Util = require("minimenu/util")
local _ = require("gettext")

local glyph = Util.utf8char

local Defaults = {}

Defaults.TITLE = _("MiniMenu Default")

function Defaults.options()
    return { show_title = false }
end

local function act(name, icon, label, scope)
    return { kind = "dispatcher", icon = icon, label = label, scope = scope, data = { action = { [name] = true } } }
end
local function sep(scope)
    return { kind = "separator", scope = scope, data = {} }
end
local function folder(label, items, scope)
    return { kind = "folder", label = label, scope = scope, data = { items = items } }
end
local function entry(path, opts)
    opts = opts or {}
    local segs = {}
    for i, seg in ipairs(path) do
        segs[i] = { id = seg[1], text = seg[2] }
    end
    return {
        kind = "menu_item",
        icon = opts.icon,
        scope = opts.scope,
        data = { path = segs, page = opts.page or false, captured_in = "reader" },
    }
end

local NAVI = { "navi", "Navigation" }
local SETTING = { "setting", "Settings" }

local function items()
    return {
        folder(_("Go to ..."), {
            entry({ NAVI, { "go_to_previous_location", "Go back to previous location" } }, { icon = glyph(0xE74C) }), -- arrow-left
            entry({ NAVI, { "go_to_next_location", "Go forward to next location" } }, { icon = glyph(0xE753) }), -- arrow-right
            sep(),
            entry({ NAVI, { "table_of_contents", "Table of contents" } }, { icon = glyph(0xEF34) }), -- table-of-contents
            entry({ NAVI, { "bookmarks", "Bookmarks" } }, { icon = glyph(0xE7BF) }), -- bookmark
            entry({ NAVI, { "page_browser", "Page browser" } }, { icon = glyph(0xEC6F) }), -- view-grid
        }, "reader"),
        entry(
            { { "typeset", "Typeset" }, { "change_font", "Font" } },
            { page = true, scope = "reader", icon = glyph(0xEDD4) } -- format-font
        ),
        act("filemanager", glyph(0xE905), _("Close book"), "reader"), -- exit-to-app
        sep("reader"),
        entry({ SETTING, { "network", "Network" }, { "network_wifi", "Wi-Fi connection" } }, { icon = glyph(0xECA8) }), -- wifi
        entry({ SETTING, { "night_mode", "Night mode" } }, { icon = glyph(0xEC93) }), -- weather-night
        entry({ SETTING, { "frontlight", "Frontlight" } }, { icon = glyph(0xEDE6) }), -- lightbulb-on
        folder(_("Device"), {
            act("poweroff", glyph(0xEB24)), -- power
            act("exit", glyph(0xE905)), -- exit-to-app
            act("restart", glyph(0xEE07)), -- restart
        }),
        act("suspend", glyph(0xEBB1)), -- sleep
    }
end

--- The default items with fresh ids. Unsupported actions are dropped, then
-- folders left empty and separators left leading, trailing or doubled.
-- `issue` returns a new item id; `supported` tells whether an action can be used.
function Defaults.build(issue, supported)
    local function build(list)
        local kept = {}
        for _i, item in ipairs(list) do
            local keep = true
            if item.kind == "dispatcher" then
                keep = supported(next(item.data.action))
            elseif item.kind == "folder" then
                item.data.items = build(item.data.items)
                keep = #item.data.items > 0
            end
            if keep then table.insert(kept, item) end
        end
        local tidy = {}
        for _i, item in ipairs(kept) do
            if item.kind ~= "separator" or (#tidy > 0 and tidy[#tidy].kind ~= "separator") then
                table.insert(tidy, item)
            end
        end
        while #tidy > 0 and tidy[#tidy].kind == "separator" do
            table.remove(tidy)
        end
        local out = {}
        for i, item in ipairs(tidy) do
            out[i] =
                { id = issue(), kind = item.kind, label = item.label, icon = item.icon, scope = item.scope, data = {} }
            for k, v in pairs(item.data) do
                out[i].data[k] = v
            end
        end
        return out
    end
    return build(items())
end

function Defaults.items()
    local Store = require("minimenu/store")
    return Defaults.build(Store.issueItemId, require("minimenu/dispatch").supported)
end

return Defaults
