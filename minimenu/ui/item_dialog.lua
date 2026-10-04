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
    { value = nil,           text = _("Reader and File browser") },
    { value = "reader",      text = _("Reader") },
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

local function scopeName(scope)
    for _i, s in ipairs(ItemDialog.SCOPES) do
        if s.value == scope then return s.text end
    end
    return ItemDialog.SCOPES[1].text
end

function ItemDialog.chooseScope(menu_id, item_id)
    local Dialogs = require("minimenu/ui/dialogs")
    local _menu, item = locate(menu_id, item_id)
    if not item then return end
    local choices = {}
    for _i, s in ipairs(ItemDialog.SCOPES) do
        -- false stands in for nil, which choose can't pass through.
        table.insert(choices,
            { text = (item.scope == s.value and "\u{2713} " or "    ") .. s.text, value = s.value or false })
    end
    Dialogs.choose({ title = _("Show in"), choices = choices }, function(scope)
        local m, it = locate(menu_id, item_id)
        if not m then return end
        it.scope = scope or nil
        Store.itemChanged(m.id)
    end)
end

local function besidePopup()
    local popup = require("minimenu/api").current
    if not popup or popup.closed or UIManager:getNthTopWidget() ~= popup then return nil end
    return function()
        local r = not popup.closed and popup:chainRect()
        if not r then return nil end
        -- No x: centered horizontally.
        return { y = r.y, h = r.h }
    end
end

local function itemName(item, ctx)
    local info = Resolve.inspect(item, ctx, Kinds.get)
    return info.separator and _("Separator") or info.label or ""
end

local function retitle(dialog, text)
    local box = dialog.title_group and dialog.title_group[1] and dialog.title_group[1][1]
    if box and box.setText then
        local h = box:getSize().h
        dialog.title = text
        box:setText(text)
        if box:getSize().h == h then
            UIManager:setDirty(dialog, function() return "ui", dialog.movable.dimen end)
            return
        end
    end
    -- Not from inside the button callback that is running: it would free that button.
    UIManager:nextTick(function()
        if not dialog.closed then dialog:setTitle(text) end
    end)
end

function ItemDialog.showMove(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu = locate(menu_id, item_id)
    if not menu then return end
    menu_id = menu.id
    local dialog, unsubscribe

    local function position()
        local _m, item, list, index, ancestors = locate(menu_id, item_id)
        if not item then return nil end
        return item, list, index, ancestors and ancestors[#ancestors]
    end
    local function title()
        local item, list, index, folder = position()
        if not item then return dialog and dialog.title or "" end
        local where
        if folder then
            where = T(_("%1 of %2 in %3"), index, #list, folder.label or _("Folder"))
        else
            where = T(_("%1 of %2"), index, #list)
        end
        return itemName(item, ctx) .. "\n" .. where
    end
    local function move(delta_fn)
        return function()
            local _item, list, index = position()
            if not index then return end
            Store.editItems(menu_id, function(items) return model.move(items, item_id, delta_fn(index, #list)) end)
        end
    end
    local function canMove(dir)
        return function()
            local _item, list, index = position()
            if not index then return false end
            if dir < 0 then return index > 1 end
            return index < #list
        end
    end

    dialog = ButtonDialog:new {
        title = title(),
        title_align = "center",
        width_factor = 0.66,
        anchor = besidePopup(),
        buttons = {
            {
                {
                    id = "up",
                    text = "\u{25B2}  " .. _("Up"),
                    enabled_func = canMove(-1),
                    callback = move(function() return -1 end),
                    hold_callback = move(function(index) return 1 - index end),
                },
                {
                    id = "down",
                    text = "\u{25BC}  " .. _("Down"),
                    enabled_func = canMove(1),
                    callback = move(function() return 1 end),
                    hold_callback = move(function(index, n) return n - index end),
                },
            },
            {
                {
                    id = "to_folder",
                    text = _("To folder…"),
                    enabled_func = function()
                        local item, _list, _index, folder = position()
                        if not item then return false end
                        return folder ~= nil or #model.folders(Store.menu(menu_id).items, item_id) > 0
                    end,
                    callback = function()
                        require("minimenu/ui/pickers/move_to").pick(menu_id, item_id)
                    end,
                },
                {
                    id = "out",
                    text = _("Out of folder"),
                    enabled_func = function()
                        local item, _list, _index, folder = position()
                        return item ~= nil and folder ~= nil
                    end,
                    callback = function()
                        Store.editItems(menu_id, function(items) return model.moveOut(items, item_id) end)
                    end,
                },
            },
            {
                {
                    id = "done",
                    text = _("Done"),
                    callback = function() UIManager:close(dialog) end,
                },
            },
        },
    }
    unsubscribe = Store.subscribe(function(ev)
        if ev.menu_id ~= menu_id and ev.type ~= "menu_deleted" then return end
        if not position() then
            UIManager:close(dialog)
            return
        end
        retitle(dialog, title())
    end)
    local orig_close = dialog.onCloseWidget
    dialog.onCloseWidget = function(self)
        self.closed = true
        unsubscribe()
        if ItemDialog.mover == self then ItemDialog.mover = nil end
        return orig_close(self)
    end
    ItemDialog.mover = dialog
    UIManager:show(dialog)
    return dialog
end

--- `ctx` is the popup's context, or nil for the current one.
function ItemDialog.show(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu, item = locate(menu_id, item_id)
    if not (menu and item) then return end
    menu_id = menu.id
    local provider = Kinds.get(item.kind)
    local info = Resolve.inspect(item, ctx, Kinds.get)
    local title = itemName(item, ctx) .. "\n" .. ItemDialog.describe(item)
    if not provider then
        title = title .. "\n" .. _("This item's kind isn't installed. It is kept until you delete it.")
    end
    local dialog
    local buttons = {}
    local function add(text, fn)
        table.insert(buttons, { {
            text = text,
            align = "left",
            callback = function()
                UIManager:close(dialog)
                fn()
            end,
        } })
    end

    if not info.separator then
        add(_("Rename…"), function() ItemDialog.rename(menu_id, item_id, ctx) end)
        add(_("Change icon…"), function() ItemDialog.changeIcon(menu_id, item_id) end)
    end
    add(T(_("Show in: %1"), scopeName(item.scope)), function() ItemDialog.chooseScope(menu_id, item_id) end)
    add(_("Move…"), function() ItemDialog.showMove(menu_id, item_id, ctx) end)
    if model.children(item) then
        add(_("Add item inside…"), function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = item_id, ctx = ctx })
        end)
    elseif item.kind == "menu_link" and Store.menu(item.data.menu) then
        add(_("Edit linked menu…"), function()
            require("minimenu/ui/editor").showItems(item.data.menu)
        end)
    end
    add(_("Add item after…"), function()
        require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, after_id = item_id, ctx = ctx })
    end)
    add(_("Duplicate"), function() ItemDialog.duplicate(menu_id, item_id) end)
    add(_("Delete"), function() ItemDialog.delete(menu_id, item_id) end)

    dialog = ButtonDialog:new {
        title = title,
        title_align = "center",
        width_factor = 0.66,
        anchor = besidePopup(),
        buttons = buttons,
    }
    ItemDialog.current = dialog
    UIManager:show(dialog)
    return dialog
end

return ItemDialog
