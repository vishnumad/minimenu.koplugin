--[[--
A sample menu in the bottom-left corner while the Appearance page is open,
redrawn on every settings change. A toast, so taps reach the settings below;
it closes itself once its TouchMenu leaves the page.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local Anchor = require("minimenu/ui/anchor")
local Panel = require("minimenu/ui/panel")
local Popup = require("minimenu/ui/popup")
local Store = require("minimenu/store")

local Preview = WidgetContainer:extend {
    name = "MiniMenuPreview",
    toast = true,
    menu = nil, -- the TouchMenu
    page = nil, -- its item table this preview belongs to
}

local function rows()
    return {
        { label = _("Wi-Fi connection"), icon = "\u{ECA8}", checked = true },
        { label = _("Night mode"), icon = "\u{EC93}", checked = false },
        { separator = true },
        {
            label = _("Device"),
            icon = "\u{F07B}",
            children = function()
                return {}
            end,
        },
    }
end

function Preview.show(page)
    local top = UIManager:getTopmostVisibleWidget()
    local menu = top and top[1]
    if not (menu and menu.item_table) then return end
    local preview = Preview:new { menu = menu, page = page }
    UIManager:show(preview, "ui", preview.dimen)
    return preview
end

function Preview:init()
    self:build()
    self.unsubscribe = Store.subscribe(function(ev)
        if ev.type == "settings_changed" then self:rebuild() end
    end)
end

function Preview:build()
    local cfg = Popup.metrics()
    local screen = { w = Screen:getWidth(), h = Screen:getHeight() }
    self.panel = Panel.new {
        rows = rows(),
        cfg = cfg,
        title = _("Preview"),
        min_w = math.floor(screen.w * 0.3),
        max_w = math.floor(screen.w * 0.8),
    }
    local w, h = self.panel:measure(screen.h)
    local r = Anchor.fixed("bottom_left", { w = w, h = h }, screen, cfg.margin)
    self.panel:layout(r.x, r.y, r.w, r.h)
    local d = self.panel:dirtyRect()
    self.dimen = Geom:new { x = d.x, y = d.y, w = d.w, h = d.h }
end

function Preview:rebuild()
    local before = self.dimen
    self.panel:free()
    self:build()
    UIManager:setDirty("all", "ui", before:combine(self.dimen))
end

function Preview:paintTo(bb)
    self.panel:paintTo(bb)
end

function Preview:handleEvent(event)
    if not self.check_pending then
        self.check_pending = true
        UIManager:nextTick(function()
            self.check_pending = false
            if self.closed then return end
            if UIManager:isWidgetShown(self.menu.show_parent) and self.menu.item_table == self.page then return end
            self.closed = true
            UIManager:close(self, "ui", self.dimen)
        end)
    end
    return WidgetContainer.handleEvent(self, event)
end

function Preview:onCloseWidget()
    self.closed = true
    self.panel:free()
    self.unsubscribe()
end

return Preview
