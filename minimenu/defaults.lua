--[[--
The default menu: seeded on first install and used as the starting items of
every "New menu…". Only actions this device supports are included.
]]

local Index = require("minimenu/icons/index")
local Util = require("minimenu/util")
local _ = require("gettext")

local glyph = Index.glyph

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
            entry(
                { NAVI, { "go_to_previous_location", "Go back to previous location" } },
                { icon = glyph("arrow-left") }
            ),
            entry({ NAVI, { "go_to_next_location", "Go forward to next location" } }, { icon = glyph("arrow-right") }),
            sep(),
            entry({ NAVI, { "table_of_contents", "Table of contents" } }, { icon = glyph("table-of-contents") }),
            entry({ NAVI, { "bookmarks", "Bookmarks" } }, { icon = glyph("bookmark") }),
            entry({ NAVI, { "page_browser", "Page browser" } }, { icon = glyph("view-grid") }),
        }, "reader"),
        entry(
            { { "typeset", "Typeset" }, { "change_font", "Font" } },
            { page = true, scope = "reader", icon = glyph("format-font") }
        ),
        act("filemanager", glyph("exit-to-app"), _("Close book"), "reader"),
        sep("reader"),
        entry({ SETTING, { "network", "Network" }, { "network_wifi", "Wi-Fi connection" } }, { icon = glyph("wifi") }),
        entry({ SETTING, { "night_mode", "Night mode" } }, { icon = glyph("weather-night") }),
        entry({ SETTING, { "frontlight", "Frontlight" } }, { icon = glyph("lightbulb-on") }),
        folder(_("Device"), {
            act("poweroff", glyph("power")),
            act("exit", glyph("exit-to-app")),
            act("restart", glyph("restart")),
        }),
        act("suspend", glyph("sleep")),
    }
end

--- The default items with fresh ids. Unsupported actions are dropped, then
-- folders left empty and separators left leading, trailing or doubled.
-- `issue` returns a new item id; `supported` tells whether an action can be used.
function Defaults.build(issue, supported)
    local function isSeparator(item)
        return item.kind == "separator"
    end
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
        kept = Util.tidySeparators(kept, isSeparator)
        for _i, item in ipairs(kept) do
            item.id = issue()
        end
        return kept
    end
    return build(items())
end

function Defaults.items()
    local Store = require("minimenu/store")
    return Defaults.build(Store.issueItemId, require("minimenu/dispatch").supported)
end

return Defaults
