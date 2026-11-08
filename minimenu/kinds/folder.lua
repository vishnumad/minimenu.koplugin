local _ = require("gettext")

local ICON = "\u{F07B}"

return {
    name = "folder",
    title = _("Folder"),
    order = 40,
    ICON = ICON,

    pick = function(_ctx, done)
        done({ items = {} }, nil, nil, { ask_label = true })
    end,

    validate = function(data)
        return type(data) == "table" and type(data.items) == "table"
    end,

    resolve = function(item)
        return {
            label = _("Folder"),
            icon = ICON,
            available = true,
            title = item.label,
            children = function()
                return item.data.items
            end,
        }
    end,
}
