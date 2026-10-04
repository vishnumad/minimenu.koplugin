-- Reads and replays the active UI's main menu.

local Walk = require("minimenu/menupath/walk")

local Live = {}

local function logErr(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.err("MiniMenu:", ...) end
end

local function buildTree(ui)
    local menu = ui and ui.menu
    if not menu then return nil end
    if menu.tab_item_table == nil and menu.setUpdateItemTable then
        -- Never rebuild an existing table: setUpdateItemTable mutates menu_items.
        local ok, err = pcall(menu.setUpdateItemTable, menu)
        if not ok then
            logErr("could not build the main menu:", err)
            return nil
        end
    end
    return menu.tab_item_table
end

--- The active UI's main-menu tab_item_table, or nil. Cached on `ctx`.
function Live.tree(ctx)
    if ctx._tree == nil then ctx._tree = buildTree(ctx.ui) or false end
    return ctx._tree or nil
end

--- Stand-in for the TouchMenu that menu callbacks receive. Fields are
-- explicit: callbacks that probe e.g. `tm.item_table` must not get a function.
function Live.shim(ui)
    local noop = function() end
    return {
        item_table = {},
        item_table_stack = {},
        show_parent = ui,
        updateItems = noop,
        closeMenu = noop,
        backToUpperMenu = noop,
        onClose = noop,
        handleEvent = noop,
    }
end

function Live.runLeaf(node, ui)
    local cb = Walk.callback(node)
    if not cb then return false end
    cb(Live.shim(ui))
    return true
end

--- Show a submenu node, or a whole tab, full screen.
function Live.openPage(node)
    local kids, err = Walk.children(node)
    if not kids and type(node) == "table" and #node > 0 then kids = node end
    if not kids then
        logErr("could not open menu page:", err)
        return false
    end
    require("minimenu/menupath/host").show(kids)
    return true
end

return Live
