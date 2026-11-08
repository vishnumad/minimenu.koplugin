-- Builds KOReader's main menu while the user is idle, when a menu in use has
-- menu actions in this scope, so the first popup open doesn't pay for it.

local Actions = require("minimenu/actions")
local Store = require("minimenu/store")
local logger = require("logger")
local model = require("minimenu/model")

local Warm = {
    IDLE = 3,
    opened = { reader = {}, filemanager = {} },
}

-- The KOReader plugins that store dispatcher bindings, as `ui[plugin][field]`:
-- a map of action tables. Hotkeys is nil on devices without keys.
local SOURCES = {
    { plugin = "gestures", field = "gestures" },
    { plugin = "hotkeys", field = "hotkeys", optional = true },
    { plugin = "profiles", field = "data" },
}

local pending

local function boundIds(out, actions)
    if type(actions) ~= "table" then return out end
    for name in pairs(actions) do
        local id = type(name) == "string" and name:match("^" .. Actions.PREFIX .. "(.+)$")
        if id and Actions.wanted(Store.menu(id)) then out[id] = true end
    end
    return out
end

local function allWithActions(out)
    for _, menu in ipairs(Store.menus()) do
        if Actions.wanted(menu) then out[menu.id] = true end
    end
end

function Warm.roots(ui, scope)
    local roots = {}
    for _, src in ipairs(SOURCES) do
        local plugin = ui[src.plugin]
        if type(plugin) == "table" then
            local bindings = plugin[src.field]
            if type(bindings) == "table" then
                for _, actions in pairs(bindings) do
                    boundIds(roots, actions)
                end
            elseif bindings ~= nil or not src.optional then
                logger.dbg("MiniMenu: can't read", src.plugin .. "." .. src.field .. ", counting every menu as bound")
                allWithActions(roots)
            end
        end
    end
    for id in pairs(Warm.opened[scope]) do
        roots[id] = true
    end
    return roots
end

function Warm.needsTree(roots, scope)
    local seen, queue = {}, {}
    local function enqueue(id)
        if not seen[id] then
            seen[id] = true
            table.insert(queue, id)
        end
    end
    -- Returns true when the action needs the tree.
    local function visit(action)
        if not action then return false end
        local kind, data = action.kind, action.data
        if kind == "menu_item" then return true end
        if kind == "menu_link" and type(data.menu) == "string" then
            enqueue(data.menu)
        elseif kind == "dispatcher" then
            for id in pairs(boundIds({}, data.action)) do
                enqueue(id)
            end
        end
    end
    local function scan(items)
        for _, item in ipairs(items) do
            if not item.scope or item.scope == scope then
                if visit(item) or visit(item.secondary) then return true end
                local kids = model.children(item)
                if kids and scan(kids) then return true end
            end
        end
        return false
    end
    for id in pairs(roots) do
        enqueue(id)
    end
    while #queue > 0 do
        local menu = Store.menu(table.remove(queue))
        if menu and scan(menu.items) then return true end
    end
    return false
end

function Warm.noteOpened(scope, menu_id)
    Warm.opened[scope][menu_id] = true
end

function Warm.run(ui)
    local Live = require("minimenu/menupath/live")
    local scope = ui.document and "reader" or "filemanager"
    if Live.built(ui) then
        logger.dbg("MiniMenu: main menu already built in the", scope)
    elseif not Warm.needsTree(Warm.roots(ui, scope), scope) then
        logger.dbg("MiniMenu: no menu in use needs the main menu in the", scope)
    else
        logger.dbg("MiniMenu:", Live.warm(ui) and "built" or "could not build", "the main menu on idle in the", scope)
    end
end

-- Runs between IDLE and 2 × IDLE seconds after the last input.
function Warm.schedule(ui)
    Warm.cancel()
    local UIManager = require("ui/uimanager")
    local p = { ui = ui, input = false }
    p.hook = function()
        p.input = true
    end
    p.task = function()
        if p.input then
            p.input = false
            UIManager:scheduleIn(Warm.IDLE, p.task)
            return
        end
        Warm.cancel(ui)
        local ok, err = pcall(Warm.run, ui)
        if not ok then logger.err("MiniMenu: warm-up failed:", err) end
    end
    UIManager.event_hook:register("InputEvent", p.hook)
    UIManager:scheduleIn(Warm.IDLE, p.task)
    pending = p
end

-- With a ui, only that UI's warm-up: the file browser closes after the reader
-- has scheduled its own.
function Warm.cancel(ui)
    if not pending or (ui and pending.ui ~= ui) then return end
    local UIManager = require("ui/uimanager")
    UIManager:unschedule(pending.task)
    UIManager.event_hook:unregister("InputEvent", pending.hook)
    pending = nil
end

return Warm
