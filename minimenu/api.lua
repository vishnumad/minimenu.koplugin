-- Public API, also used by other plugins.

local API = {
    VERSION = "1.0.0",
    current = nil, -- the open popup, if any
}

local function warnReadError(path)
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local T = require("ffi/util").template
    UIManager:nextTick(function()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new {
            text = T(
                _(
                    "MiniMenu could not read its settings file:\n%1\n\nYour menus are not loaded, and changes won't be saved until the file is fixed or removed."
                ),
                path
            ),
        })
    end)
end

--- Idempotent; safe to call before MiniMenu's own plugin instance exists.
function API.ensure()
    local Kinds = require("minimenu/kinds/init")
    local Store = require("minimenu/store")
    Kinds.registerBuiltins()
    if not Store.data then
        Store.load(Kinds.get, function()
            local Defaults = require("minimenu/defaults")
            Store.createMenu(Defaults.TITLE, Defaults.items(), { options = Defaults.options() })
        end)
        if Store.read_error then warnReadError(Store.backend.path) end
    end
    require("minimenu/actions").attach(Store)
    return Store
end

--- { { id, title }, … } in display order.
function API.list()
    local Store = API.ensure()
    local out = {}
    for _, menu in ipairs(Store.menus()) do
        table.insert(out, { id = menu.id, title = menu.title })
    end
    return out
end

function API.exists(menu_id)
    local Store = API.ensure()
    return Store.menu(menu_id) ~= nil
end

--- Is `menu_id` open (any menu when nil)?
function API.isOpen(menu_id)
    local p = API.current
    if not p or p.closed then return false end
    return menu_id == nil or p.menu_id == menu_id
end

--[[--
Open a menu, closing any other open one. Does nothing if it is already open.

opts (all optional):
    anchor   Geom rect or point to place against (overrides the menu's position)
    prefer   "above" | "below" | "left" | "right"
    gesture  where to open when the menu's position is "At the gesture"
    on_close called once the popup has closed
]]
function API.open(menu_id, opts)
    local Store = API.ensure()
    if API.isOpen(menu_id) then return true end
    local menu = Store.menu(menu_id)
    if not menu then
        local Notification = require("ui/widget/notification")
        local _ = require("gettext")
        Notification:notify(_("Menu no longer exists"))
        return false
    end
    if API.isOpen() then API.close() end
    local UIManager = require("ui/uimanager")
    local Popup = require("minimenu/ui/popup")
    local popup = Popup:new { menu_id = menu_id, open_opts = opts or {} }
    API.current = popup
    UIManager:show(popup, "ui", popup:showRect())
    return true
end

--- Open, or close if this menu is already open.
function API.toggle(menu_id, opts)
    if API.isOpen(menu_id) then
        API.close()
        return false
    end
    return API.open(menu_id, opts)
end

function API.close()
    local p = API.current
    API.current = nil
    if p and not p.closed then p:close() end
end

--- Items of that kind already in storage show up from the next render.
function API.registerKind(provider)
    API.ensure()
    return require("minimenu/kinds/init").register(provider)
end

--- callback(menu_id|nil)
function API.pickMenu(callback, opts)
    API.ensure()
    require("minimenu/ui/pickers/menus").pick(opts or {}, callback)
end

return API
