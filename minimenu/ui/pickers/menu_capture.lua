--[[--
Menu action picker: browse the active UI's main menu and capture an entry or
a whole page. Only the active UI's menu exists, so reader entries can only
be captured from inside a book.
]]

local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Capture = {}

Capture.TAB_NAMES = {
    navi = _("Navigation"),
    typeset = _("Typeset"),
    setting = _("Settings"),
    tools = _("Tools"),
    search = _("Search"),
    filemanager = _("File browser"),
    filemanager_settings = _("File browser settings"),
    plus_menu = _("Plus menu"),
    main = _("Main"),
}

local function copyPath(path, extra)
    local out = {}
    for i, seg in ipairs(path) do
        out[i] = { id = seg.id, text = seg.text }
    end
    if extra then table.insert(out, { id = extra.id, text = extra.text }) end
    return out
end

function Capture.pick(ctx, done)
    local Dialogs = require("minimenu/ui/dialogs")
    local Live = require("minimenu/menupath/live")
    local Util = require("minimenu/util")
    local Walk = require("minimenu/menupath/walk")
    local tree = Live.tree({ ui = ctx.ui })
    if not tree then
        Dialogs.info(_("Could not read KOReader's menu right now."))
        return done(nil)
    end
    local captured_in = ctx.name
    local root_title = captured_in == "reader" and _("Reader menu")
        or _("File browser menu: open a book to add reader menu items")
    local chosen = false
    local stack = {} -- levels: { rows, path, title }
    local menu

    local function finish(data, icon)
        chosen = true
        UIManager:close(menu)
        done(data, icon)
    end

    local show
    local function enter(row)
        local depth = #stack
        local kids, err = Walk.childrenAt(row.node, depth)
        if not kids then
            require("logger").warn("MiniMenu: could not open submenu:", err)
            return Dialogs.info(_("This submenu can't be opened right now."))
        end
        local top = stack[#stack]
        table.insert(stack, {
            rows = Walk.captureList(kids),
            path = copyPath(top.path, row.segment),
            title = row.text,
        })
        show()
    end

    show = function()
        local level = stack[#stack]
        local items = {}
        if #level.path > 0 then
            table.insert(items, {
                text = "\u{F067}  " .. _("Add this page"),
                bold = true,
                callback = function()
                    local icon = select(1, Util.splitLeadingIcon(level.title))
                    finish({ path = copyPath(level.path), page = true, captured_in = captured_in }, icon)
                end,
            })
        end
        for _i, row in ipairs(level.rows) do
            local mandatory
            if row.submenu or #level.path == 0 then
                mandatory = "\u{203A}"
            elseif row.toggle then
                mandatory = Walk.checked(row.node) and "\u{F046}" or "\u{F096}"
            end
            table.insert(items, {
                text = row.text,
                mandatory = mandatory,
                dim = not row.submenu and not row.leaf and #level.path > 0,
                callback = function()
                    if row.submenu or #level.path == 0 then
                        enter(row)
                    elseif row.leaf then
                        local icon = select(1, Util.splitLeadingIcon(row.text))
                        finish(
                            { path = copyPath(level.path, row.segment), page = false, captured_in = captured_in },
                            icon
                        )
                    else
                        Dialogs.info(_("This entry can't be added."))
                    end
                end,
            })
        end
        local crumbs = {}
        for i = 2, #stack do
            table.insert(crumbs, stack[i].title)
        end
        local title = #crumbs > 0 and table.concat(crumbs, " \u{203A} ") or root_title
        if not menu then
            menu = Dialogs.list({
                title = title,
                items = items,
                on_return = function()
                    if #stack > 1 then
                        table.remove(stack)
                        show()
                    end
                end,
                on_close = function()
                    if not chosen then done(nil) end
                end,
            })
        end
        Dialogs.relist(menu, title, items, #stack - 1)
    end

    table.insert(stack, { rows = Walk.tabList(tree, Capture.TAB_NAMES), path = {}, title = root_title })
    show()
end

return Capture
