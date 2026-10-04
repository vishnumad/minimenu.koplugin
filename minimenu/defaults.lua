--[[--
The default menu: seeded on first install and used as the starting items of
every "New menu…". Only actions this device supports are included.
]]

local _ = require("gettext")

local Defaults = {}

Defaults.TITLE = _("Quick menu")

local function act(name)
    return { kind = "dispatcher", data = { action = { [name] = true } } }
end
local function sep()
    return { kind = "separator", data = {} }
end
local function folder(label, items, scope)
    return { kind = "folder", label = label, scope = scope, data = { items = items } }
end

-- Kept short enough to fit one page on a 6" screen in the reader.
local function items()
    return {
        act("toc"),
        act("bookmarks"),
        act("fulltext_search"),
        -- Reader only, so the file browser doesn't show an empty folder.
        folder(_("Go to"), {
            act("go_to"),
            act("skim"),
            act("book_map"),
            act("previous_location"),
            act("first_page"),
            act("last_page"),
        }, "reader"),
        sep(),
        act("history"),
        act("favorites"),
        sep(),
        act("night_mode"),
        act("show_frontlight_dialog"),
        sep(),
        folder(_("Device"), {
            act("toggle_wifi"),
            act("full_refresh"),
            sep(),
            act("suspend"),
            act("restart"),
            act("exit"),
            sep(),
            act("reboot"),
            act("poweroff"),
        }),
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
            out[i] = { id = issue(), kind = item.kind, label = item.label, scope = item.scope, data = {} }
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
