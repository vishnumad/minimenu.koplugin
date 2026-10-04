local _ = require("gettext")

local FOLDER_ICON = "\u{F07B}"

return {
    name = "folder",
    title = _("Folder"),
    order = 40,

    pick = function(_ctx, done)
        done({ items = {} }, nil, nil, { ask_label = true })
    end,

    validate = function(data)
        return type(data) == "table" and type(data.items) == "table"
    end,

    resolve = function(item)
        return {
            label = _("Folder"),
            icon = FOLDER_ICON,
            available = true,
            title = item.label,
            children = function() return item.data.items end,
        }
    end,

    describe = function(item)
        local n = #item.data.items
        return n == 1 and _("1 item") or require("ffi/util").template(_("%1 items"), n)
    end,
}
