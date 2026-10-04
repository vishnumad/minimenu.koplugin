local _ = require("gettext")
local Util = require("minimenu/util")
local Walk = require("minimenu/menupath/walk")

local PAGE_ICON = "\u{F0CA}"

local function lastText(path)
    local seg = path[#path]
    return seg and (seg.text or seg.id) or "?"
end

return {
    name = "menu_item",
    title = _("Menu action"),
    order = 20,

    pick = function(ctx, done)
        require("minimenu/ui/pickers/menu_capture").pick(ctx, function(data, icon)
            done(data, nil, icon)
        end)
    end,

    validate = function(data)
        if type(data) ~= "table" or type(data.path) ~= "table" or #data.path == 0 then
            return false, "no path"
        end
        for _i, seg in ipairs(data.path) do
            if type(seg) ~= "table" or (type(seg.id) ~= "string" and type(seg.text) ~= "string") then
                return false, "bad path segment"
            end
        end
        return true
    end,

    resolve = function(item, ctx)
        local Live = require("minimenu/menupath/live")
        local data = item.data
        local tree = Live.tree(ctx)
        local fallback_icon, fallback_label = Util.splitLeadingIcon(lastText(data.path))
        local row = { label = fallback_label, icon = fallback_icon or (data.page and PAGE_ICON or nil) }
        if not tree then
            -- The menu can't be built right now: let the tap try again.
            row.available = true
            row.run = function()
                local node = Walk.resolve(Live.tree({ ui = ctx.ui }), data.path)
                if not node then return end
                if data.page then Live.openPage(node) else Live.runLeaf(node, ctx.ui) end
            end
            return row
        end
        local node, why = Walk.resolve(tree, data.path)
        if not node then
            -- A submenu that failed to build may work later.
            row.available = why == "error"
            return row
        end
        local icon, label = Util.splitLeadingIcon(Walk.text(node) or fallback_label)
        row.label = label
        if icon then row.icon = icon end
        if data.page then
            row.available = Walk.isSubmenu(node) or #data.path == 1
            row.disabled = row.available and not Walk.enabled(node)
            row.run = function() Live.openPage(node) end
            return row
        end
        row.available = Walk.isLeaf(node)
        row.disabled = row.available and not Walk.enabled(node)
        row.checked = Walk.checked(node)
        row.keep_open = row.checked ~= nil
        row.run = function() Live.runLeaf(node, ctx.ui) end
        return row
    end,

    describe = function(item)
        local where = item.data.captured_in == "reader" and _("Reader menu") or _("File browser menu")
        local text = where .. ": " .. Walk.describe(item.data.path)
        if item.data.page then text = text .. " " .. _("(page)") end
        return text
    end,
}
