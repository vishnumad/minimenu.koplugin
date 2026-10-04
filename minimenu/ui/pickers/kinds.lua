-- "Add item": choose a kind, run its pick, then insert the new item.

local _ = require("gettext")

local KindPicker = {}

--[[--
target:
    menu_id
    folder_id   folder to add into (nil = top level)
    after_id    insert right after this item instead
    ctx         popup or editor context
]]
function KindPicker.add(target)
    local Dialogs = require("minimenu/ui/dialogs")
    local Kinds = require("minimenu/kinds/init")
    local choices = {}
    for _i, provider in ipairs(Kinds.list()) do
        table.insert(choices, { text = provider.title or provider.name, value = provider })
    end
    Dialogs.choose({ title = _("Add item"), choices = choices }, function(provider)
        KindPicker.runPick(provider, target)
    end)
end

local function contextFor(target)
    local Context = require("minimenu/context")
    local ctx = target.ctx or Context.current()
    return {
        ui = ctx.ui,
        context = ctx,
        name = ctx.name,
        menu_id = target.menu_id,
    }
end

function KindPicker.runPick(provider, target)
    local Store = require("minimenu/store")
    local model = require("minimenu/model")
    local finished = false
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
    local ok, err = pcall(provider.pick, contextFor(target), function(data, label, icon, opts)
        if finished then return end
        finished = true
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
    if not ok then
        require("logger").err("MiniMenu: picking", provider.name, "failed:", err)
        require("minimenu/ui/dialogs").info(_("Could not add this item."))
    end
end

return KindPicker
