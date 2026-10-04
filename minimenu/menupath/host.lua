--[[--
Shows a main-menu item table full screen in a single-tab TouchMenu, the
widget KOReader itself renders these tables with (checked_func, radio items,
SpinWidgets, sub_item_table_func, hold_callback).
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Host = {}

--[[--
opts:
    icon          tab icon (default "appbar.menu")
    on_close      called after the host closed
    on_update     called with the TouchMenu after each updateItems
Returns the TouchMenu
]]
function Host.show(items, opts)
    opts = opts or {}
    local TouchMenu = require("ui/widget/touchmenu")
    local container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = Screen:getSize(),
    }
    local tab = { icon = opts.icon or "appbar.menu" }
    for i, item in ipairs(items) do tab[i] = item end
    tab.max_per_page = items.max_per_page
    local menu = TouchMenu:new{
        width = Screen:getWidth(),
        tab_item_table = { tab },
        show_parent = container,
        last_index = 1,
    }
    menu.close_callback = function()
        UIManager:close(container)
        if opts.on_close then opts.on_close() end
    end
    if opts.on_update then
        local orig = menu.updateItems
        menu.updateItems = function(self, ...)
            local r = orig(self, ...)
            opts.on_update(self)
            return r
        end
    end
    container[1] = menu
    UIManager:show(container)
    return menu
end

return Host
