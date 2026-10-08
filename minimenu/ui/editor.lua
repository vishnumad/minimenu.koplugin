--[[--
Tools › MiniMenu. Menus and their options are main-menu entries; items are
edited one folder level at a time in a full-screen list.
]]

local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Store = require("minimenu/store")
local Util = require("minimenu/util")

local Editor = {}

Editor.POSITION_NAMES = {
    gesture = _("At the gesture"),
    center = _("Center"),
    top_left = _("Top left"),
    top_right = _("Top right"),
    bottom_left = _("Bottom left"),
    bottom_right = _("Bottom right"),
    top = _("Top"),
    bottom = _("Bottom"),
}

local function radioList(values, names, get, set)
    local items = {}
    for _i, v in ipairs(values) do
        table.insert(items, {
            text = names[v] or tostring(v),
            radio = true,
            checked_func = function()
                return get() == v
            end,
            callback = function()
                set(v)
            end,
        })
    end
    return items
end

local function optionItems(menu_id)
    local function get(key)
        return Store.option(Store.menu(menu_id), key)
    end
    local function set(key, v)
        Store.setOption(menu_id, key, v)
    end
    local function toggle(key, text, help_text)
        return {
            text = text,
            help_text = help_text,
            checked_func = function()
                return get(key)
            end,
            callback = function()
                set(key, not get(key))
            end,
        }
    end
    return {
        {
            text_func = function()
                return T(_("Position: %1"), Editor.POSITION_NAMES[get("position")] or "")
            end,
            help_text = _(
                "With “At the gesture”, a menu opened without a tap position (from a profile, a key or another plugin) opens in the center."
            ),
            sub_item_table = radioList(Store.POSITIONS, Editor.POSITION_NAMES, function()
                return get("position")
            end, function(v)
                set("position", v)
            end),
        },
        toggle("show_title", _("Show title")),
        toggle(
            "hide_unavailable",
            _("Hide unavailable items"),
            _(
                "Hide items that can't run here (for example reader actions in the file browser). When off, they are shown dimmed."
            )
        ),
    }
end

--- Fills `items` in place, so it can refresh itself.
function Editor.mainMenu(items)
    items = items or {}
    for i = #items, 1, -1 do
        items[i] = nil
    end
    table.insert(items, {
        text = _("New menu…"),
        keep_menu_open = true,
        callback = function(tm)
            Editor.newMenu(function()
                Editor.mainMenu(items)
                tm:updateItems()
            end)
        end,
        separator = true,
    })
    for _i, menu in ipairs(Store.menus()) do
        local id = menu.id
        table.insert(items, {
            text_func = function()
                local m = Store.menu(id)
                return m and m.title or _("Deleted menu")
            end,
            enabled_func = function()
                return Store.menu(id) ~= nil
            end,
            sub_item_table_func = function()
                return Editor.menuSettings(id)
            end,
        })
    end
    if #items > 1 then items[#items].separator = true end
    local appearance = Editor.appearanceItem()
    appearance.separator = true
    table.insert(items, appearance)
    table.insert(items, {
        text = _("Check for updates"),
        keep_menu_open = true,
        callback = function()
            require("minimenu/ui/update").check()
        end,
    })
    -- Rebuild when coming back up from a menu's page, which may have renamed
    -- or deleted it.
    items.needs_refresh = true
    items.refresh_func = function()
        return Editor.mainMenu(items)
    end
    return items
end

function Editor.newMenu(on_created)
    local Dialogs = require("minimenu/ui/dialogs")
    Dialogs.input({ title = _("New menu"), hint = _("Menu name"), ok_text = _("Create") }, function(text)
        text = Util.trim(text)
        if text == "" then return end
        local menu = Store.createMenu(text, require("minimenu/defaults").items())
        if on_created then on_created(menu) end
    end)
end

function Editor.menuSettings(menu_id)
    local Dialogs = require("minimenu/ui/dialogs")
    local function menu()
        return Store.menu(menu_id)
    end
    local items = {
        {
            text = _("Open now"),
            callback = function(tm)
                tm:closeMenu()
                UIManager:nextTick(function()
                    require("minimenu/api").open(menu_id)
                end)
            end,
        },
        {
            text = _("Edit items…"),
            keep_menu_open = true,
            callback = function()
                Editor.showItems(menu_id)
            end,
        },
        {
            text = _("Rename…"),
            keep_menu_open = true,
            callback = function(tm)
                local m = menu()
                if not m then return end
                Dialogs.input({ title = _("Rename menu"), input = m.title }, function(text)
                    text = Util.trim(text)
                    if text ~= "" then Store.renameMenu(menu_id, text) end
                    tm:updateItems()
                end)
            end,
        },
        {
            text = _("Show in action list"),
            help_text = _("Lists this menu as a KOReader action, so gestures, profiles and other plugins can open it."),
            checked_func = function()
                local m = menu()
                return m and m.register_action ~= false
            end,
            callback = function()
                local m = menu()
                if m then Store.setRegisterAction(menu_id, m.register_action == false) end
            end,
        },
    }
    items[#items].separator = true
    for _i, item in ipairs(optionItems(menu_id)) do
        table.insert(items, item)
    end
    items[#items].separator = true
    table.insert(items, {
        text = _("Duplicate"),
        keep_menu_open = true,
        callback = function(tm)
            local m = menu()
            if not m then return end
            Store.duplicateMenu(menu_id, T(_("%1 (copy)"), m.title))
            Dialogs.info(T(_("Created “%1”."), T(_("%1 (copy)"), m.title)), 2)
            tm:backToUpperMenu()
        end,
    })
    table.insert(items, {
        text = _("Delete…"),
        keep_menu_open = true,
        callback = function(tm)
            local m = menu()
            if not m then return end
            Dialogs.confirm(
                T(_("Delete the menu “%1”?\n\nGestures and profiles that open it will be unbound."), m.title),
                _("Delete"),
                function()
                    Store.deleteMenu(menu_id)
                    tm:backToUpperMenu()
                end
            )
        end,
    })
    return items
end

local function spinItem(key, title, opts)
    local function value()
        local v = Store.setting(key)
        return opts.precision and opts.precision:format(v) or v
    end
    return {
        text_func = function()
            return T(_("%1: %2"), title, value())
        end,
        help_text = opts.help_text,
        keep_menu_open = true,
        callback = function(tm)
            local SpinWidget = require("ui/widget/spinwidget")
            UIManager:show(SpinWidget:new {
                title_text = title,
                value = Store.setting(key),
                value_min = opts.min,
                value_max = opts.max,
                value_step = opts.step or 1,
                value_hold_step = opts.hold_step or 4,
                precision = opts.precision,
                default_value = Store.DEFAULT_SETTINGS[key],
                keep_shown_on_apply = true,
                callback = function(spin)
                    Store.setSetting(key, tonumber(opts.precision and opts.precision:format(spin.value) or spin.value))
                    tm:updateItems()
                end,
            })
        end,
    }
end

local function fontItem()
    local ok, FontChooser = pcall(require, "ui/widget/fontchooser")
    if not ok then return nil end
    local Font = require("ui/font")
    local FontList = require("fontlist")
    local default
    for file in pairs(FontList.fontinfo) do
        if file:match("[^/]+$") == Font.fontmap.cfont then default = file end
    end
    return {
        text_func = function()
            local name = FontChooser.getFontNameText(Store.setting("font"))
            return T(_("Font: %1"), name or _("default"))
        end,
        keep_menu_open = true,
        callback = function(tm)
            UIManager:show(FontChooser:new {
                title = _("Font"),
                font_file = Store.setting("font") or default,
                default_font_file = default,
                callback = function(file)
                    Store.setSetting("font", file ~= default and file or nil)
                    tm:updateItems()
                end,
            })
        end,
    }
end

local function resetAppearanceItem()
    local keys = { "font" }
    for key in pairs(Store.DEFAULT_SETTINGS) do
        table.insert(keys, key)
    end
    return {
        text = _("Reset appearance"),
        keep_menu_open = true,
        enabled_func = function()
            for _i, key in ipairs(keys) do
                if Store.setting(key) ~= Store.DEFAULT_SETTINGS[key] then return true end
            end
            return false
        end,
        callback = function(tm)
            require("minimenu/ui/dialogs").confirm(
                _("Reset all appearance settings to their defaults?"),
                _("Reset"),
                function()
                    for _i, key in ipairs(keys) do
                        Store.setSetting(key, nil)
                    end
                    tm:updateItems()
                end
            )
        end,
    }
end

local function appearanceItems()
    local items = {
        spinItem("font_size", _("Text size"), {
            min = 12,
            max = 36,
            help_text = _("Text size in all menus. Rows and icons grow with it."),
        }),
        spinItem("row_spacing", _("Row spacing"), {
            min = 1.5,
            max = 4,
            step = 0.1,
            hold_step = 0.5,
            precision = "%.1f",
            help_text = _("Row height, relative to the text size."),
        }),
        spinItem("padding", _("Padding"), {
            min = 0,
            max = 40,
            help_text = _("Space at the left and right of each row."),
        }),
        spinItem("edge_margin", _("Screen edge spacing"), {
            min = 0,
            max = 60,
            help_text = _("Smallest space between a menu and the screen's edges."),
        }),
        spinItem("radius", _("Corner radius"), { min = 0, max = 30 }),
        {
            text = _("Shadow"),
            checked_func = function()
                return Store.setting("shadow")
            end,
            callback = function()
                Store.setSetting("shadow", not Store.setting("shadow"))
            end,
        },
    }
    local font = fontItem()
    if font then table.insert(items, 2, font) end
    items[#items].separator = true
    table.insert(items, resetAppearanceItem())
    return items
end

function Editor.appearanceItem()
    return {
        text = _("Appearance"),
        sub_item_table_func = function()
            local items = appearanceItems()
            require("minimenu/ui/preview").show(items)
            return items
        end,
    }
end

function Editor.itemRows(menu_id, folder_id, ctx, nav)
    local ItemDialog = require("minimenu/ui/item_dialog")
    local Kinds = require("minimenu/kinds/init")
    local Resolve = require("minimenu/resolve")
    local model = require("minimenu/model")
    local menu = Store.menu(menu_id)
    if not menu then return {} end
    local list = model.listFor(menu.items, folder_id) or {}
    local rows = {}
    for _i, item in ipairs(list) do
        local info = Resolve.inspect(item, ctx, Kinds.get)
        local provider = Kinds.get(item.kind)
        local marker = ItemDialog.marker(item, ctx)
        local text
        if info.separator then
            text = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}  " .. _("Separator")
        else
            text = (Util.isGlyph(info.icon) and (info.icon .. "  ") or "") .. (info.label or "")
        end
        local is_folder = model.children(item) ~= nil
        local id = item.id
        table.insert(rows, {
            text = text,
            mandatory = is_folder and ((marker and (marker .. "  ") or "") .. "\u{203A}")
                or marker
                or (provider and provider.title)
                or item.kind,
            dim = marker ~= nil,
            callback = function()
                if is_folder then
                    nav.enter(id)
                else
                    ItemDialog.show(menu_id, id, ctx)
                end
            end,
            hold_callback = function()
                ItemDialog.show(menu_id, id, ctx)
            end,
        })
    end
    table.insert(rows, {
        text = "\u{F067}  " .. _("Add item"),
        bold = true,
        callback = function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = folder_id, ctx = ctx })
        end,
    })
    return rows
end

function Editor.showItems(menu_id)
    local Context = require("minimenu/context")
    local Dialogs = require("minimenu/ui/dialogs")
    local model = require("minimenu/model")
    local ctx = Context.current()
    local path = {} -- folder ids, outermost first
    local list, unsubscribe
    local nav = {}

    local function title()
        local menu = Store.menu(menu_id)
        local parts = { menu and menu.title or "" }
        for _i, fid in ipairs(path) do
            local f = menu and model.find(menu.items, fid)
            table.insert(parts, f and f.label or _("Folder"))
        end
        return table.concat(parts, " \u{203A} ")
    end

    local function refresh(keep_page)
        if not Store.menu(menu_id) then
            UIManager:close(list)
            return
        end
        -- Leave folders that no longer exist.
        local menu = Store.menu(menu_id)
        for i = #path, 1, -1 do
            if not model.find(menu.items, path[i]) then
                for j = #path, i, -1 do
                    path[j] = nil
                end
            end
        end
        Dialogs.relist(list, title(), Editor.itemRows(menu_id, path[#path], ctx, nav), #path, keep_page)
    end

    nav.enter = function(folder_id)
        table.insert(path, folder_id)
        refresh(false)
    end

    list = Dialogs.list({
        title = title(),
        items = {},
        left_icon = "plus",
        on_left = function()
            require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = path[#path], ctx = ctx })
        end,
        on_return = function()
            if #path > 0 then
                table.remove(path)
                refresh(false)
            end
        end,
        on_close = function()
            if unsubscribe then unsubscribe() end
        end,
    })
    unsubscribe = Store.subscribe(function(ev)
        if ev.menu_id == menu_id or ev.type == "menu_deleted" then refresh(true) end
    end)
    refresh(false)
    return list
end

return Editor
