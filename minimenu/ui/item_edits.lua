-- Edits to one item, for the item sheet and the editor.

local _ = require("gettext")
local T = require("ffi/util").template

local Kinds = require("minimenu/kinds/init")
local Resolve = require("minimenu/resolve")
local Sheet = require("minimenu/ui/sheet")
local Store = require("minimenu/store")
local Util = require("minimenu/util")
local model = require("minimenu/model")

local ItemEdits = {}

local SCOPES = {
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
function ItemEdits.problem(item, info)
    if info.orphan then return T(_("Needs plugin: %1"), item.kind) end
    if info.missing then return _("Not found in menu") end
    if not info.available then return _("Not available here") end
end

--- Why an item may not show here, or nil. `info` is its Resolve.inspect.
function ItemEdits.marker(item, info)
    if info.orphan then return ItemEdits.problem(item, info) end
    if item.scope == "reader" then return _("Reader only") end
    if item.scope == "filemanager" then return _("File browser only") end
    return ItemEdits.problem(item, info)
end

function ItemEdits.rename(menu_id, item_id, ctx)
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
function ItemEdits.changeIcon(menu_id, item_id, secondary)
    require("minimenu/ui/pickers/icons").pick(function(icon)
        if icon == nil then return end
        update(menu_id, item_id, function(it)
            local target = secondary and it.secondary or it
            if not target then return false end
            target.icon = icon or nil
        end)
    end)
end

--- `secondary` picks the second action instead of the main one.
local function pickAction(title, menu_id, item_id, ctx, secondary, apply)
    local _menu, item = Store.findItem(item_id, menu_id)
    if not item then return end
    local current = item
    if secondary then current = item.secondary end
    local target = { menu_id = menu_id, ctx = ctx, current = current }
    require("minimenu/ui/pickers/kinds").pickAction(title, target, function(kind, data)
        update(menu_id, item_id, function(it)
            apply(it, kind, data)
        end)
    end)
end

function ItemEdits.changeAction(menu_id, item_id, ctx)
    pickAction(_("Main action"), menu_id, item_id, ctx, false, function(it, kind, data)
        if data then
            it.kind, it.data = kind, data
        else
            it.kind, it.data = "none", {}
        end
    end)
end

function ItemEdits.pickSecondary(menu_id, item_id, ctx)
    pickAction(_("Second action"), menu_id, item_id, ctx, true, function(it, kind, data)
        if not data then
            it.secondary = nil
            return
        end
        local old = it.secondary or {}
        it.secondary = { kind = kind, data = data, icon = old.icon, keep_open = old.keep_open }
    end)
end

function ItemEdits.removeSecondary(menu_id, item_id)
    update(menu_id, item_id, function(it)
        it.secondary = nil
    end)
end

--- With `secondary`, toggles it for the second action instead.
function ItemEdits.toggleKeepOpen(menu_id, item_id, secondary)
    update(menu_id, item_id, function(it)
        local target = secondary and it.secondary or it
        if not target then return false end
        target.keep_open = not target.keep_open or nil
    end)
end

function ItemEdits.secondaryGlyph(secondary)
    return Util.isGlyph(secondary.icon) and secondary.icon or Resolve.GEAR
end

function ItemEdits.delete(menu_id, item_id)
    local m, item = Store.findItem(item_id, menu_id)
    if not m then return end
    local count = 0
    model.walk(model.children(item), function()
        count = count + 1
    end)
    local text = count > 0 and T(_("Delete this folder and the %1 items in it?"), count) or _("Delete this item?")
    require("minimenu/ui/dialogs").confirm(text, _("Delete"), function()
        Store.editItems(m.id, function(items)
            return model.remove(items, item_id) ~= nil
        end)
    end)
end

function ItemEdits.scopeName(scope)
    for _i, s in ipairs(SCOPES) do
        if s.value == scope then return s.text end
    end
    return SCOPES[1].text
end

function ItemEdits.chooseScope(menu_id, item_id)
    local _menu, item = Store.findItem(item_id, menu_id)
    if not item then return end
    local choices = {}
    for _i, s in ipairs(SCOPES) do
        table.insert(choices, { text = s.text, value = s.value, checked = item.scope == s.value })
    end
    return Sheet.choose {
        title = _("Show in"),
        choices = choices,
        on_choice = function(scope)
            update(menu_id, item_id, function(it)
                it.scope = scope
            end)
        end,
    }
end

return ItemEdits
