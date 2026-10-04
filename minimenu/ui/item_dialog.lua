-- The item dialog, opened from the editor or by long-pressing a popup row.

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Context = require("minimenu/context")
local Kinds = require("minimenu/kinds/init")
local Resolve = require("minimenu/resolve")
local Store = require("minimenu/store")
local model = require("minimenu/model")

local ItemDialog = {}

ItemDialog.SCOPES = {
    { value = nil, text = _("Both") },
    { value = "reader", text = _("Reader") },
    { value = "filemanager", text = _("File browser") },
}

--- Looks in `menu_id` first, then in every menu.
local function locate(menu_id, item_id)
    local menu, item, list, index, ancestors = Store.findItem(item_id, menu_id)
    if not item then
        menu, item, list, index, ancestors = Store.findItem(item_id)
    end
    return menu, item, list, index, ancestors
end

function ItemDialog.describe(item)
    local provider = Kinds.get(item.kind)
    if not provider then return T(_("Needs plugin: %1"), item.kind) end
    if provider.describe then
        local ok, text = pcall(provider.describe, item)
        if ok and text then return text end
    end
    return provider.title or item.kind
end

--- Why an item may not show in `ctx`, or nil.
function ItemDialog.marker(item, ctx)
    local info = Resolve.inspect(item, ctx, Kinds.get)
    if info.orphan then return T(_("Needs plugin: %1"), item.kind) end
    if item.scope == "reader" then return _("Reader only") end
    if item.scope == "filemanager" then return _("File browser only") end
    if not info.available then return _("Not available here") end
end

function ItemDialog.rename(menu_id, item_id, ctx)
    local Dialogs = require("minimenu/ui/dialogs")
    local Util = require("minimenu/util")
    local _menu, item = locate(menu_id, item_id)
    if not item then return end
    -- Without the custom label, to hint the default name.
    local info = Resolve.inspect({ kind = item.kind, data = item.data, id = item.id }, ctx, Kinds.get)
    Dialogs.input({
        title = _("Rename"),
        input = item.label or "",
        hint = info.label,
        description = _("Leave empty to use the default name."),
    }, function(text)
        local m, it = locate(menu_id, item_id)
        if not m then return end
        text = Util.trim(text)
        it.label = text ~= "" and text or nil
        Store.itemChanged(m.id)
    end)
end

function ItemDialog.changeIcon(menu_id, item_id)
    require("minimenu/ui/pickers/icons").pick(function(icon)
        if icon == nil then return end
        local m, it = locate(menu_id, item_id)
        if not m then return end
        it.icon = icon or nil
        Store.itemChanged(m.id)
    end)
end

function ItemDialog.delete(menu_id, item_id)
    local m, item = locate(menu_id, item_id)
    if not m then return end
    local function doit()
        Store.editItems(m.id, function(items) return model.remove(items, item_id) ~= nil end)
    end
    local kids = model.children(item)
    if kids and #kids > 0 then
        local Dialogs = require("minimenu/ui/dialogs")
        Dialogs.confirm(T(_("Delete this folder and the %1 items in it?"), #kids), _("Delete"), doit)
    else
        doit()
    end
end

function ItemDialog.duplicate(menu_id, item_id)
    local m = locate(menu_id, item_id)
    if not m then return end
    Store.editItems(m.id, function(items)
        local item, list, index = model.find(items, item_id)
        if not item then return false end
        table.insert(list, index + 1, model.cloneItem(item, Store.issueItemId))
        return true
    end)
end

--- `ctx` is the popup's context, or nil for the current one.
function ItemDialog.show(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu, item, _list, _index, ancestors = locate(menu_id, item_id)
    if not (menu and item) then return end
    menu_id = menu.id
    local provider = Kinds.get(item.kind)
    local info = Resolve.inspect(item, ctx, Kinds.get)
    local title = (info.separator and _("Separator") or info.label) .. "\n" .. ItemDialog.describe(item)
    local dialog
    local function act(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local scope_row = {}
    for _i, s in ipairs(ItemDialog.SCOPES) do
        table.insert(scope_row, {
            text = (item.scope == s.value and "\u{2713} " or "") .. s.text,
            callback = act(function()
                local m, it = locate(menu_id, item_id)
                if not m then return end
                it.scope = s.value
                Store.itemChanged(m.id)
            end),
        })
    end
    local in_folder = ancestors and #ancestors > 0
    local buttons = {
        {
            { text = _("Rename…"), enabled = not info.separator, callback = act(function() ItemDialog.rename(menu_id, item_id, ctx) end) },
            { text = _("Change icon…"), enabled = not info.separator, callback = act(function() ItemDialog.changeIcon(menu_id, item_id) end) },
        },
        scope_row,
        {
            { text = _("Move up"), callback = act(function() Store.editItems(menu_id, function(items) return model.move(items, item_id, -1) end) end) },
            { text = _("Move down"), callback = act(function() Store.editItems(menu_id, function(items) return model.move(items, item_id, 1) end) end) },
        },
        {
            { text = _("Move to…"), callback = act(function() require("minimenu/ui/pickers/move_to").pick(menu_id, item_id) end) },
            { text = _("Move out of folder"), enabled = in_folder, callback = act(function()
                Store.editItems(menu_id, function(items) return model.moveOut(items, item_id) end)
            end) },
        },
    }
    local add_row = {
        { text = _("Add item after…"), callback = act(function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, after_id = item_id, ctx = ctx })
        end) },
    }
    if model.children(item) then
        table.insert(add_row, { text = _("Add item inside…"), callback = act(function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = item_id, ctx = ctx })
        end) })
    elseif item.kind == "menu_link" and Store.menu(item.data.menu) then
        table.insert(add_row, { text = _("Edit linked menu…"), callback = act(function()
            require("minimenu/ui/editor").showItems(item.data.menu)
        end) })
    end
    table.insert(buttons, add_row)
    table.insert(buttons, {
        { text = _("Duplicate"), callback = act(function() ItemDialog.duplicate(menu_id, item_id) end) },
        { text = _("Delete"), callback = act(function() ItemDialog.delete(menu_id, item_id) end) },
    })
    if not provider then
        title = title .. "\n" .. _("This item's kind isn't installed. It is kept until you delete it.")
    end
    dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    ItemDialog.current = dialog
    UIManager:show(dialog)
    return dialog
end

return ItemDialog
