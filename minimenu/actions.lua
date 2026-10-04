--[[--
One Dispatcher action per menu, kept in sync with the store. Action names
use the menu's id, never its title, so renaming keeps existing bindings.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Actions = {
    PREFIX = "minimenu_open_",
    EVENT = "MiniMenuOpen",
}

local injected

--- Specs inject { dispatcher = …, broadcast = function(name, payload) }.
function Actions.inject(deps)
    injected = deps
end

local function dispatcher()
    return injected and injected.dispatcher or require("dispatcher")
end

local function broadcast(name, payload)
    if injected and injected.broadcast then return injected.broadcast(name, payload) end
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new(name, payload))
end

function Actions.name(menu_id)
    return Actions.PREFIX .. menu_id
end

function Actions.spec(menu)
    return {
        category = "none",
        event = Actions.EVENT,
        arg = menu.id,
        title = T(_("MiniMenu: %1"), menu.title),
        -- Not reader = filemanager = true: that disables it in both.
        general = true,
    }
end

function Actions.wanted(menu)
    return menu and menu.register_action ~= false
end

function Actions.register(menu)
    if not Actions.wanted(menu) then return end
    dispatcher():registerAction(Actions.name(menu.id), Actions.spec(menu))
end

--- registerAction won't overwrite an existing action.
function Actions.refresh(menu)
    local D = dispatcher()
    D:removeAction(Actions.name(menu.id))
    Actions.register(menu)
end

--- Also tells Gestures, Profiles and others to drop their bindings.
function Actions.unregister(menu_id)
    local name = Actions.name(menu_id)
    dispatcher():removeAction(name)
    broadcast("DispatcherActionNameChanged", { old_name = name, new_name = nil })
end

function Actions.registerAll(store)
    for _i, menu in ipairs(store.menus()) do
        Actions.register(menu)
    end
end

function Actions.onStoreEvent(store, ev)
    local t = ev.type
    if t == "menu_created" then
        Actions.register(store.menu(ev.menu_id))
    elseif t == "menu_renamed" then
        local menu = store.menu(ev.menu_id)
        if Actions.wanted(menu) then Actions.refresh(menu) end
    elseif t == "menu_deleted" then
        Actions.unregister(ev.menu_id)
    elseif t == "menu_action_changed" then
        local menu = store.menu(ev.menu_id)
        if Actions.wanted(menu) then
            Actions.register(menu)
        else
            Actions.unregister(ev.menu_id)
        end
    end
end

--- Subscribes once, however many plugin instances call it.
function Actions.attach(store)
    if Actions.detach then return end
    Actions.detach = store.subscribe(function(ev)
        Actions.onStoreEvent(store, ev)
    end)
end

return Actions
