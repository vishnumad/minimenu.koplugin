-- "Move to…": the menu's top level and folder tree, without the moved
-- item's own subtree. The item's current place is checked and disabled.

local _ = require("gettext")

local MoveTo = {}

function MoveTo.pick(menu_id, item_id)
    local Folder = require("minimenu/kinds/folder")
    local MenuLink = require("minimenu/kinds/menu_link")
    local Store = require("minimenu/store")
    local model = require("minimenu/model")
    local menu = Store.menu(menu_id)
    if not menu then return end
    local _item, _list, _index, ancestors = model.find(menu.items, item_id)
    local current = ancestors and ancestors[#ancestors]
    local choices = {
        { text = _("Top level"), icon = MenuLink.ICON, value = false, checked = not current, enabled = current ~= nil },
    }
    for _i, entry in ipairs(model.folders(menu.items, item_id)) do
        local here = current ~= nil and current.id == entry.item.id
        table.insert(choices, {
            text = entry.item.label or _("Folder"),
            icon = Folder.ICON,
            indent = entry.depth - 1,
            value = entry.item.id,
            checked = here,
            enabled = not here,
        })
    end
    require("minimenu/ui/sheet").choose {
        title = _("Move to"),
        choices = choices,
        on_choice = function(folder_id)
            Store.editItems(menu_id, function(items)
                return model.moveTo(items, item_id, folder_id or nil)
            end)
        end,
    }
end

return MoveTo
