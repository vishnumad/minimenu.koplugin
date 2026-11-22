-- "Add item": choose a kind, run its pick, then insert the new item.

local _ = require("gettext")

local KindPicker = {}

local function chooseKind(title, filter, callback)
    local Kinds = require("minimenu/kinds/init")
    local choices = {}
    for _i, provider in ipairs(Kinds.list(filter)) do
        table.insert(choices, { text = provider.title or provider.name, value = provider })
    end
    require("minimenu/ui/sheet").choose { title = title, choices = choices, on_choice = callback }
end

--[[--
target:
    menu_id
    folder_id   folder to add into (nil = top level)
    after_id    insert right after this item instead
    ctx         popup or editor context
    current     the { kind, data } being replaced, if any
]]
function KindPicker.add(target)
    chooseKind(_("Add item"), nil, function(provider)
        KindPicker.runPick(provider, target)
    end)
end

--- Choose and pick an action kind. callback(kind, data), with data false when
-- `target.current` was cleared; `target` as for add.
function KindPicker.pickAction(title, target, callback)
    chooseKind(title, function(p)
        return p.action
    end, function(provider)
        KindPicker.pick(provider, target, function(data)
            callback(provider.name, data)
        end)
    end)
end

local function contextFor(target, provider)
    local Context = require("minimenu/context")
    local ctx = target.ctx or Context.current()
    local current = target.current
    return {
        ui = ctx.ui,
        name = ctx.name,
        menu_id = target.menu_id,
        data = current and current.kind == provider.name and current.data or nil,
    }
end

--- Runs the provider's pick. on_data(data, label, icon, opts) once, unless
-- canceled; `data` is false when the action being changed was cleared.
function KindPicker.pick(provider, target, on_data)
    local finished = false
    local ok, err = pcall(provider.pick, contextFor(target, provider), function(data, label, icon, opts)
        if finished then return end
        finished = true
        if data ~= nil then on_data(data, label, icon, opts) end
    end)
    if not ok then
        require("logger").err("MiniMenu: picking", provider.name, "failed:", err)
        require("minimenu/ui/dialogs").info(_("Could not add this item."))
    end
end

function KindPicker.runPick(provider, target)
    local Store = require("minimenu/store")
    local model = require("minimenu/model")
    local function insert(item)
        Store.editItems(target.menu_id, function(items)
            if target.after_id then
                local _it, list, index = model.find(items, target.after_id)
                if list then
                    table.insert(list, index + 1, item)
                    return true
                end
            end
            local list = model.listFor(items, target.folder_id) or items
            table.insert(list, item)
            return true
        end)
    end
    KindPicker.pick(provider, target, function(data, label, icon, opts)
        if not data then return end
        local item = { id = Store.issueItemId(), kind = provider.name, data = data }
        if label and label ~= "" then item.label = label end
        if icon and icon ~= "" then item.icon = icon end
        if opts and opts.ask_label then
            local Dialogs = require("minimenu/ui/dialogs")
            Dialogs.input(
                { title = _("Folder name"), input = "", hint = _("Folder"), ok_text = _("Add") },
                function(text)
                    local Util = require("minimenu/util")
                    text = Util.trim(text)
                    item.label = text ~= "" and text or _("Folder")
                    insert(item)
                end
            )
            return
        end
        insert(item)
    end)
end

return KindPicker
