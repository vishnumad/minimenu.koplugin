-- The item sheet, opened by long-pressing a popup row or from the editor: the
-- item, its main and second actions, and commands that change its place in
-- the menu. It stays open while edits land. Move… turns it into the move
-- controls, and Done turns it back.

local _ = require("gettext")
local T = require("ffi/util").template

local Context = require("minimenu/context")
local ItemEdits = require("minimenu/ui/item_edits")
local Kinds = require("minimenu/kinds/init")
local Resolve = require("minimenu/resolve")
local Sheet = require("minimenu/ui/sheet")
local Store = require("minimenu/store")
local model = require("minimenu/model")

local ItemSheet = {}

local UP = "\u{25B2}  " .. _("Up")
local DOWN = "\u{25BC}  " .. _("Down")

--- The name an action shows by default. `info` is its Resolve.inspect without a label.
local function actionName(kind, info)
    local provider = Kinds.get(kind)
    return (info.label ~= kind and info.label) or (provider and provider.title) or kind
end

local function append(rows, more)
    for _i, row in ipairs(more) do
        table.insert(rows, row)
    end
end

local function subtitle(item, info)
    if info.orphan then return T(_("Needs plugin: %1 · kept until you delete it"), item.kind) end
    return ItemEdits.problem(item, info)
end

function ItemSheet.show(menu_id, item_id, ctx)
    ctx = ctx or Context.current()
    local menu = Store.findItem(item_id, menu_id)
    if not menu then return end
    menu_id = menu.id
    local itemBuild, moveBuild

    local function actionSection(target, secondary)
        local info = Resolve.inspect({ id = item_id, kind = target.kind, data = target.data }, ctx, Kinds.get)
        local key = secondary and "second" or "main"
        local caption = secondary and _("Second action") or _("Main action")
        -- The main action's problem is the item's, already under the preview.
        local why = secondary and ItemEdits.problem(target, info)
        local rows = {
            { section = true, label = why and T("%1 · %2", caption, why) or caption },
            {
                id = key .. "_runs",
                label = _("Runs"),
                value = actionName(target.kind, info),
                run = function()
                    if secondary then
                        ItemEdits.pickSecondary(menu_id, item_id, ctx)
                    else
                        ItemEdits.changeAction(menu_id, item_id, ctx)
                    end
                end,
            },
        }
        if secondary then
            table.insert(rows, {
                id = "second_icon",
                label = _("Icon"),
                value = ItemEdits.secondaryGlyph(target),
                run = function()
                    ItemEdits.changeIcon(menu_id, item_id, true)
                end,
            })
        end
        if not info.opens_menu then
            table.insert(rows, {
                id = key .. "_keep_open",
                label = _("Keep menu open"),
                checked = target.keep_open == true,
                run = function()
                    ItemEdits.toggleKeepOpen(menu_id, item_id, secondary)
                end,
            })
        end
        if target.kind == "menu_link" and Store.menu(target.data.menu) then
            table.insert(rows, {
                id = key .. "_edit_link",
                label = _("Edit linked menu…"),
                run = function()
                    require("minimenu/ui/editor").showItems(target.data.menu)
                end,
            })
        end
        if secondary then
            table.insert(rows, {
                id = "second_remove",
                label = _("Remove"),
                run = function()
                    ItemEdits.removeSecondary(menu_id, item_id)
                end,
            })
        end
        return rows
    end

    local function addItem(item)
        local Picker = require("minimenu/ui/pickers/kinds")
        local after = { menu_id = menu_id, after_id = item_id, ctx = ctx }
        if not model.children(item) then return Picker.add(after) end
        Sheet.choose {
            title = _("Add item"),
            choices = {
                { text = _("After this item"), value = after },
                { text = _("Inside this folder"), value = { menu_id = menu_id, folder_id = item_id, ctx = ctx } },
            },
            on_choice = Picker.add,
        }
    end

    local function addSecondary()
        return {
            { section = true, label = _("Second action") },
            {
                id = "second_add",
                label = _("Add second action…"),
                run = function()
                    ItemEdits.pickSecondary(menu_id, item_id, ctx)
                end,
            },
        }
    end

    local function itemSection(item, info, plain)
        local scope = {
            id = "scope",
            label = _("Show in"),
            value = ItemEdits.scopeName(item.scope),
            run = function()
                ItemEdits.chooseScope(menu_id, item_id)
            end,
        }
        if plain then return { scope } end
        return {
            {
                id = "name",
                label = _("Name"),
                value = info.label,
                run = function()
                    ItemEdits.rename(menu_id, item_id, ctx)
                end,
            },
            {
                id = "icon",
                label = _("Icon"),
                value = info.icon or _("None"),
                run = function()
                    ItemEdits.changeIcon(menu_id, item_id)
                end,
            },
            scope,
        }
    end

    local function commands(item)
        return {
            { separator = true },
            {
                id = "commands",
                cells = {
                    {
                        label = _("Add…"),
                        run = function(sheet)
                            sheet:close()
                            addItem(item)
                        end,
                    },
                    {
                        label = _("Move…"),
                        run = function(sheet)
                            sheet:setBuild(moveBuild)
                        end,
                    },
                    {
                        label = _("Duplicate"),
                        run = function()
                            ItemEdits.duplicate(menu_id, item_id)
                        end,
                    },
                    {
                        label = _("Delete"),
                        run = function()
                            ItemEdits.delete(menu_id, item_id)
                        end,
                    },
                },
            },
        }
    end

    local function preview(item, info)
        return Resolve.preview(item, ctx, Kinds.get) or { label = info.label, icon = info.icon, dim = true }
    end

    itemBuild = function()
        local _m, item = Store.findItem(item_id, menu_id)
        if not item then return nil end
        local info = Resolve.inspect(item, ctx, Kinds.get)
        local provider = Kinds.get(item.kind)
        local plain = info.separator or info.orphan
        local rows = itemSection(item, info, plain)
        if provider and provider.action then append(rows, actionSection(item, false)) end
        if not plain then append(rows, item.secondary and actionSection(item.secondary, true) or addSecondary()) end
        append(rows, commands(item))
        local args = { title = _("Edit item"), rows = rows }
        if not info.separator then
            args.title_row = preview(item, info)
            args.subtitle = subtitle(item, info)
        end
        return args
    end

    local function moveBy(delta)
        return function()
            Store.editItems(menu_id, function(items)
                return model.move(items, item_id, delta)
            end)
        end
    end

    local function moveRows(list, index, folder)
        local can_enter = #model.folders(Store.menu(menu_id).items, item_id) > 0
        return {
            {
                id = "up_down",
                cells = {
                    { label = UP, disabled = index == 1, run = moveBy(-1), hold = moveBy(1 - index) },
                    { label = DOWN, disabled = index == #list, run = moveBy(1), hold = moveBy(#list - index) },
                },
            },
            {
                id = "folders",
                cells = {
                    {
                        label = _("To folder…"),
                        disabled = not (folder or can_enter),
                        run = function()
                            require("minimenu/ui/pickers/move_to").pick(menu_id, item_id)
                        end,
                    },
                    {
                        label = _("Out of folder"),
                        disabled = not folder,
                        run = function()
                            Store.editItems(menu_id, function(items)
                                return model.moveOut(items, item_id)
                            end)
                        end,
                    },
                },
            },
            { separator = true },
            {
                id = "done",
                cells = {
                    {
                        label = _("Done"),
                        run = function(sheet)
                            sheet:setBuild(itemBuild)
                        end,
                    },
                },
            },
        }
    end

    moveBuild = function()
        local _m, item, list, index, ancestors = Store.findItem(item_id, menu_id)
        if not item then return nil end
        local info = Resolve.inspect(item, ctx, Kinds.get)
        local folder = ancestors[#ancestors]
        local where = folder and T(_("%1 of %2 in %3"), index, #list, folder.label or _("Folder"))
            or T(_("%1 of %2"), index, #list)
        return {
            title = _("Move item"),
            title_row = info.separator and { label = _("Separator") } or preview(item, info),
            subtitle = where,
            rows = moveRows(list, index, folder),
        }
    end

    return Sheet.show {
        build = itemBuild,
        -- Any change can show here: a linked menu's name, the appearance of the preview.
        watch = true,
    }
end

return ItemSheet
