local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Dialogs = {}

--- callback(text) on Save; nothing on Cancel.
function Dialogs.input(args, callback)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = args.title,
        input = args.input or "",
        input_hint = args.hint,
        description = args.description,
        buttons = { {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = args.ok_text or _("Save"),
                is_enter_default = true,
                callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    callback(text)
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

function Dialogs.confirm(text, ok_text, callback)
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = callback,
    })
end

function Dialogs.info(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

--[[--
A ButtonDialog of choices, `per_row` per row (default 1).
choices: { { text, value, enabled? }, … }
callback(value) on choice; on_cancel() when dismissed.
]]
function Dialogs.choose(args, callback)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons, row = {}, {}
    local per_row = args.per_row or 1
    for _, choice in ipairs(args.choices) do
        table.insert(row, {
            text = choice.text,
            enabled = choice.enabled ~= false,
            align = per_row == 1 and "left" or nil,
            callback = function()
                UIManager:close(dialog)
                callback(choice.value)
            end,
        })
        if #row == per_row then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    for _, extra in ipairs(args.extra_rows or {}) do
        local r = {}
        for _, b in ipairs(extra) do
            table.insert(r, {
                text = b.text,
                callback = function()
                    UIManager:close(dialog)
                    b.callback()
                end,
            })
        end
        table.insert(buttons, r)
    end
    dialog = ButtonDialog:new{
        title = args.title,
        title_align = "center",
        buttons = buttons,
        rows_per_page = args.rows_per_page,
        tap_close_callback = args.on_cancel,
    }
    UIManager:show(dialog)
    return dialog
end

--[[--
A full-screen Menu. Replace its items with Dialogs.relist.

args:
    title
    items        { { text, mandatory?, dim?, bold?, callback?, hold_callback? }, … }
    left_icon, on_left  title bar button
    on_return    called by the back arrow
    on_close     called once when the list closes
]]
function Dialogs.list(args)
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local menu
    menu = Menu:new{
        title = args.title,
        item_table = args.items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        title_bar_left_icon = args.left_icon,
        onLeftButtonTap = args.on_left,
        single_line = true,
    }
    menu.paths = menu.paths or {}
    if args.on_return then
        menu.onReturn = function() args.on_return(menu) end
    end
    menu.onMenuChoice = function(_, item)
        if item.callback then item.callback(menu) end
        return true
    end
    menu.onMenuHold = function(_, item)
        if item.hold_callback then item.hold_callback(menu) end
        return true
    end
    -- Menu calls close_callback after every leaf choice; we close explicitly.
    menu.close_callback = nil
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(self)
        if args.on_close then
            local cb = args.on_close
            args.on_close = nil
            cb()
        end
        if orig_close then return orig_close(self) end
    end
    UIManager:show(menu)
    return menu
end

--- `depth` > 0 shows the back arrow; keep_page stays on the current page.
function Dialogs.relist(menu, title, items, depth, keep_page)
    menu.paths = {}
    for i = 1, depth or 0 do menu.paths[i] = true end
    menu:switchItemTable(title, items, keep_page and -1 or nil)
end

return Dialogs
