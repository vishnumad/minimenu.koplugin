-- "Move to…": the menu's top level and folder tree, without the moved
-- item's own subtree.

local _ = require("gettext")

local MoveTo = {}

function MoveTo.pick(menu_id, item_id)
    local Dialogs = require("minimenu/ui/dialogs")
    local Store = require("minimenu/store")
    local model = require("minimenu/model")
    local menu = Store.menu(menu_id)
    if not menu then return end
    local _item, _list, _index, ancestors = model.find(menu.items, item_id)
    local current = ancestors and ancestors[#ancestors]
    local choices = { { text = "\u{F0C9}  " .. _("Top level"), value = false, enabled = current ~= nil } }
    for _i, entry in ipairs(model.folders(menu.items, item_id)) do
        local indent = string.rep("    ", entry.depth - 1)
        table.insert(choices, {
            text = indent .. "\u{F07B}  " .. (entry.item.label or _("Folder")),
            value = entry.item.id,
            enabled = not (current and current.id == entry.item.id),
        })
    end
    Dialogs.choose({ title = _("Move to"), choices = choices }, function(folder_id)
        Store.editItems(menu_id, function(items)
            return model.moveTo(items, item_id, folder_id or nil)
        end)
    end)
end

return MoveTo
