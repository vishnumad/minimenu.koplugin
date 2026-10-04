-- Thin adapter: state lives in module-level singletons (minimenu/store,
-- minimenu/api) shared by the FileManager and ReaderUI plugin instances.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local MiniMenu = WidgetContainer:extend{
    name = "minimenu",
    is_doc_only = false,
}

-- v2026.07.1
local MIN_VERSION = 202607010000

function MiniMenu:init()
    local API = require("minimenu/api")
    API.ensure()
    -- DispatcherRegisterActions is broadcast only once, so register here too;
    -- registerAction ignores names that already exist.
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:checkVersion()
end

function MiniMenu:checkVersion()
    if G_reader_settings:isTrue("minimenu_version_warned") then return end
    local ok, Version = pcall(require, "version")
    if not ok then return end
    local current = Version:getNormalizedCurrentVersion()
    if current and current > 0 and current < MIN_VERSION then
        G_reader_settings:makeTrue("minimenu_version_warned")
        local UIManager = require("ui/uimanager")
        UIManager:nextTick(function()
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("MiniMenu is made for KOReader v2026.07.1 or later. Some features may not work on this version."),
            })
        end)
    end
end

function MiniMenu:onDispatcherRegisterActions()
    require("minimenu/actions").registerAll(require("minimenu/store"))
end

function MiniMenu:addToMainMenu(menu_items)
    menu_items.minimenu = {
        text = _("MiniMenu"),
        sorting_hint = "tools",
        sub_item_table_func = function()
            return require("minimenu/ui/editor").mainMenu()
        end,
    }
end

-- Several instances may receive the same event; open is idempotent.
function MiniMenu:onMiniMenuOpen(menu_id, exec_props)
    local gesture = exec_props and exec_props.gesture
    require("minimenu/api").open(menu_id, { gesture = gesture })
    return true
end

function MiniMenu:onFlushSettings()
    local Store = package.loaded["minimenu/store"]
    if Store and Store.dirty then Store.save() end
end

return MiniMenu
