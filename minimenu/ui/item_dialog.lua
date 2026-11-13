-- The item dialog, opened from the editor or by long-pressing a popup row.

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Context = require("minimenu/context")
local Kinds = require("minimenu/kinds/init")
local Resolve = require("minimenu/resolve")
local Store = require("minimenu/store")
local Util = require("minimenu/util")
local model = require("minimenu/model")

local ItemDialog = {}

ItemDialog.SCOPES = {
    { value = nil, text = _("Reader and File browser") },
    { value = "reader", text = _("Reader") },
    { value = "filemanager", text = _("File browser") },
}

--- Calls fn(item) and saves, unless the item is gone or fn returns false.
local function update(menu_id, item_id, fn)
    local menu, item = Store.findItem(item_id, menu_id)
    if not menu or fn(item) == false then return end
    Store.itemChanged(menu.id)
end

--- Why an item can't run in `ctx`, or nil. `info` is its Resolve.inspect.
local function problem(item, info)
    if info.orphan then return T(_("Needs plugin: %1"), item.kind) end
    if info.missing then return _("Not found in menu") end
    if not info.available then return _("Not available here") end
end

--- Why an item may not show here, or nil. `info` is its Resolve.inspect.
function ItemDialog.marker(item, info)
    if info.orphan then return problem(item, info) end
    if item.scope == "reader" then return _("Reader only") end
    if item.scope == "filemanager" then return _("File browser only") end
    return problem(item, info)
end

function ItemDialog.rename(menu_id, item_id, ctx)
    local Dialogs = require("minimenu/ui/dialogs")
    local _menu, item = Store.findItem(item_id, menu_id)
    if not item then return end
    -- Without the custom label, to hint the default name.
    local info = Resolve.inspect({ kind = item.kind, data = item.data, id = item.id }, ctx, Kinds.get)
    Dialogs.input({
        title = _("Rename"),
        input = item.label or "",
        hint = info.label,
        description = _("Leave empty to use the default name."),
    }, function(text)
        update(menu_id, item_id, function(it)
            text = Util.trim(text)
            it.label = text ~= "" and text or nil
        end)
    end)
end

--- With `secondary`, changes the second action's icon instead.
function ItemDialog.changeIcon(menu_id, item_id, secondary)
    require("minimenu/ui/pickers/icons").pick(function(icon)
        if icon == nil then return end
        update(menu_id, item_id, function(it)
            local target = secondary and it.secondary or it
            if not target then return false end
            target.icon = icon or nil
        end)
    end)
end

local function pickAction(title, menu_id, item_id, ctx, apply)
    require("minimenu/ui/pickers/kinds").pickAction(title, { menu_id = menu_id, ctx = ctx }, function(kind, data)
        update(menu_id, item_id, function(it)
            apply(it, kind, data)
        end)
    end)
end

--- Replaces the item's action, keeping its label, icon and second action.
function ItemDialog.changeAction(menu_id, item_id, ctx)
    pickAction(_("Change action"), menu_id, item_id, ctx, function(it, kind, data)
        it.kind, it.data = kind, data
    end)
end

--- Sets the second action, keeping its icon and whether it keeps the menu open.
function ItemDialog.pickSecondary(menu_id, item_id, ctx)
    pickAction(_("Second action"), menu_id, item_id, ctx, function(it, kind, data)
        local old = it.secondary or {}
        it.secondary = { kind = kind, data = data, icon = old.icon, keep_open = old.keep_open }
    end)
end

function ItemDialog.removeSecondary(menu_id, item_id)
    update(menu_id, item_id, function(it)
        it.secondary = nil
    end)
end

--- With `secondary`, toggles it for the second action instead.
function ItemDialog.toggleKeepOpen(menu_id, item_id, secondary)
    update(menu_id, item_id, function(it)
        local target = secondary and it.secondary or it
        if not target then return false end
        target.keep_open = not target.keep_open or nil
    end)
end

local function keepOpenButton(menu_id, item_id, target, secondary)
    return {
        (target.keep_open and "\u{2713} " or "") .. _("Keep menu open"),
        function()
            ItemDialog.toggleKeepOpen(menu_id, item_id, secondary)
        end,
    }
end

function ItemDialog.secondaryGlyph(secondary)
    return Util.isGlyph(secondary.icon) and secondary.icon or Resolve.GEAR
end

function ItemDialog.delete(menu_id, item_id)
    local m, item = Store.findItem(item_id, menu_id)
    if not m then return end
    local function doit()
        Store.editItems(m.id, function(items)
            return model.remove(items, item_id) ~= nil
        end)
    end
    local count = 0
    model.walk(model.children(item), function()
        count = count + 1
    end)
    if count > 0 then
        local Dialogs = require("minimenu/ui/dialogs")
        Dialogs.confirm(T(_("Delete this folder and the %1 items in it?"), count), _("Delete"), doit)
    else
        doit()
    end
end

function ItemDialog.duplicate(menu_id, item_id)
    local m = Store.findItem(item_id, menu_id)
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
    local _menu, item = Store.findItem(item_id, menu_id)
    if not item then return end
    local choices = {}
    for _i, s in ipairs(ItemDialog.SCOPES) do
        -- false stands in for nil, which choose can't pass through.
        table.insert(
            choices,
            { text = (item.scope == s.value and "\u{2713} " or "    ") .. s.text, value = s.value or false }
        )
    end
    Dialogs.choose({ title = _("Show in"), choices = choices }, function(scope)
        update(menu_id, item_id, function(it)
            it.scope = scope or nil
        end)
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
            UIManager:setDirty(dialog, function()
                return "ui", dialog.movable.dimen
            end)
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
    local menu = Store.findItem(item_id, menu_id)
    if not menu then return end
    menu_id = menu.id
    local dialog, unsubscribe

    local function position()
        local _m, item, list, index, ancestors = Store.findItem(item_id, menu_id)
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
            Store.editItems(menu_id, function(items)
                return model.move(items, item_id, delta_fn(index, #list))
            end)
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
                    callback = move(function()
                        return -1
                    end),
                    hold_callback = move(function(index)
                        return 1 - index
                    end),
                },
                {
                    id = "down",
                    text = "\u{25BC}  " .. _("Down"),
                    enabled_func = canMove(1),
                    callback = move(function()
                        return 1
                    end),
                    hold_callback = move(function(index, n)
                        return n - index
                    end),
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
                        Store.editItems(menu_id, function(items)
                            return model.moveOut(items, item_id)
                        end)
                    end,
                },
            },
            {
                {
                    id = "done",
                    text = _("Done"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
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

--- `groups` is a list of groups of button rows, each row { { text, fn }, … }.
-- Empty groups are skipped and the rest drawn with a line between them. Each
-- button closes the dialog before running. Tracked as ItemDialog.current.
local function groupedDialog(title, groups)
    local dialog
    local buttons = {}
    for _i, group in ipairs(groups) do
        if #group > 0 then
            if #buttons > 0 then table.insert(buttons, {}) end
            for _j, row in ipairs(group) do
                local line = {}
                for _k, b in ipairs(row) do
                    table.insert(line, {
                        text = b[1],
                        callback = function()
                            UIManager:close(dialog)
                            b[2]()
                        end,
                    })
                end
                table.insert(buttons, line)
            end
        end
    end
    dialog = ButtonDialog:new {
        title = title,
        title_align = "center",
        width_factor = 0.66,
        anchor = besidePopup(),
        buttons = buttons,
    }
    local orig_close = dialog.onCloseWidget
    dialog.onCloseWidget = function(self)
        if ItemDialog.current == self then ItemDialog.current = nil end
        return orig_close(self)
    end
    ItemDialog.current = dialog
    UIManager:show(dialog)
    return dialog
end

--- The name an action shows by default, without the item's custom label.
local function actionName(kind, data, ctx)
    local info = Resolve.inspect({ kind = kind, data = data }, ctx, Kinds.get)
    local provider = Kinds.get(kind)
    return (info.label ~= kind and info.label) or (provider and provider.title) or kind
end

--- `ctx` is the popup's context, or nil for the current one.
function ItemDialog.show(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu, item = Store.findItem(item_id, menu_id)
    if not (menu and item) then return end
    menu_id = menu.id
    local provider = Kinds.get(item.kind)
    local info = Resolve.inspect(item, ctx, Kinds.get)
    local title = itemName(item, ctx)
    local why = problem(item, info)
    if why then title = title .. "\n" .. why end
    if not provider then title = title .. "\n" .. _("It is kept until you delete it.") end

    local looks, behaviour = {}, {}
    if not info.separator then
        looks = {
            {
                {
                    _("Rename…"),
                    function()
                        ItemDialog.rename(menu_id, item_id, ctx)
                    end,
                },
                {
                    _("Change icon…"),
                    function()
                        ItemDialog.changeIcon(menu_id, item_id)
                    end,
                },
            },
        }
        if provider and provider.action then
            table.insert(behaviour, {
                {
                    T(_("Action: %1"), actionName(item.kind, item.data, ctx)),
                    function()
                        ItemDialog.changeAction(menu_id, item_id, ctx)
                    end,
                },
            })
            if not info.opens_menu then table.insert(behaviour, { keepOpenButton(menu_id, item_id, item) }) end
        end
        if item.kind == "menu_link" and Store.menu(item.data.menu) then
            table.insert(behaviour, {
                {
                    _("Edit linked menu…"),
                    function()
                        require("minimenu/ui/editor").showItems(item.data.menu)
                    end,
                },
            })
        end
        local s = item.secondary
        if s then
            local text = T(_("Second action: %1"), actionName(s.kind, s.data, ctx))
            table.insert(behaviour, {
                {
                    ItemDialog.secondaryGlyph(s) .. "  " .. text,
                    function()
                        ItemDialog.showSecondary(menu_id, item_id, ctx)
                    end,
                },
            })
        else
            table.insert(behaviour, {
                {
                    _("Add second action…"),
                    function()
                        ItemDialog.pickSecondary(menu_id, item_id, ctx)
                    end,
                },
            })
        end
    end
    table.insert(behaviour, {
        {
            T(_("Show in: %1"), scopeName(item.scope)),
            function()
                ItemDialog.chooseScope(menu_id, item_id)
            end,
        },
    })

    local add_row = {}
    if model.children(item) then
        table.insert(add_row, {
            _("Add item inside…"),
            function()
                require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = item_id, ctx = ctx })
            end,
        })
    end
    table.insert(add_row, {
        _("Add item after…"),
        function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, after_id = item_id, ctx = ctx })
        end,
    })
    local structure = {
        add_row,
        {
            {
                _("Move…"),
                function()
                    ItemDialog.showMove(menu_id, item_id, ctx)
                end,
            },
            {
                _("Duplicate"),
                function()
                    ItemDialog.duplicate(menu_id, item_id)
                end,
            },
            {
                _("Delete"),
                function()
                    ItemDialog.delete(menu_id, item_id)
                end,
            },
        },
    }
    return groupedDialog(title, { looks, behaviour, structure })
end

function ItemDialog.showSecondary(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu, item = Store.findItem(item_id, menu_id)
    if not (menu and item and item.secondary) then return end
    menu_id = menu.id
    local title = _("Second action")
    local res = Resolve.secondary(item, ctx, Kinds.get)
    if res and not res.available then title = title .. "\n" .. _("Not available here") end
    local keep_open = {}
    if res and not res.children then keep_open = { keepOpenButton(menu_id, item_id, item.secondary, true) } end
    return groupedDialog(title, {
        {
            {
                {
                    _("Change action…"),
                    function()
                        ItemDialog.pickSecondary(menu_id, item_id, ctx)
                    end,
                },
            },
            {
                {
                    _("Change icon…"),
                    function()
                        ItemDialog.changeIcon(menu_id, item_id, true)
                    end,
                },
            },
            keep_open,
            {
                {
                    _("Remove"),
                    function()
                        ItemDialog.removeSecondary(menu_id, item_id)
                    end,
                },
            },
        },
    })
end

return ItemDialog
