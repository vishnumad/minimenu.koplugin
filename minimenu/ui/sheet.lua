--[[--
A single panel, centered on the screen, in a full-screen transparent
InputContainer, like a popup without the chain. `build` describes the panel
and, with `watch`, runs again on every Store event. Rows and cells act
through run(sheet) and hold(sheet); a row tap never closes the sheet by
itself.
]]

local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Anchor = require("minimenu/ui/anchor")
local Metrics = require("minimenu/ui/metrics")
local Panel = require("minimenu/ui/panel")
local RowView = require("minimenu/ui/row")
local Store = require("minimenu/store")

local Sheet = InputContainer:extend {
    name = "MiniMenuSheet",
    build = nil, -- returns { title, rows, title_row?, subtitle? }, or nil to close
    watch = false, -- whether Store events rebuild
    on_close = nil,
    stop_events_propagation = true,
}

local function toGeom(r)
    return Geom:new { x = r.x, y = r.y, w = r.w, h = r.h }
end

local function enabledCell(cells, from, step)
    for j = from, step > 0 and #cells or 1, step do
        if not cells[j].disabled then return j end
    end
end

local function indexOf(rows, id)
    if id == nil then return nil end
    for i, row in ipairs(rows) do
        if row.id == id then return i end
    end
end

function Sheet.show(args)
    local sheet = Sheet:new(args)
    if not sheet:layout() then return nil end
    if sheet.watch then sheet.unsubscribe = Store.subscribe(function()
        sheet:rebuild()
    end) end
    UIManager:show(sheet, "ui", sheet:showRect())
    return sheet
end

--[[--
args:
    title
    choices     { { text, value, icon, checked, enabled, indent }, … }
    on_choice   on_choice(value), after the sheet closes
    on_cancel   called when dismissed, or nil
]]
function Sheet.choose(args)
    local chosen = false
    local rows = {}
    for _, choice in ipairs(args.choices) do
        table.insert(rows, {
            label = choice.text,
            icon = choice.icon,
            indent = choice.indent,
            value = choice.checked and RowView.CHECK or nil,
            dim = choice.enabled == false,
            run = function(sheet)
                chosen = true
                sheet:close()
                args.on_choice(choice.value)
            end,
        })
    end
    return Sheet.show {
        build = function()
            return { title = args.title, rows = rows }
        end,
        on_close = function()
            if not chosen and args.on_cancel then args.on_cancel() end
        end,
    }
end

function Sheet:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.screen = { w = sw, h = sh }
    self.dimen = Geom:new { x = 0, y = 0, w = sw, h = sh }
    self.cfg = Metrics.defaults()
    local range = self.dimen
    self.ges_events = {
        Tap = { GestureRange:new { ges = "tap", range = range } },
        Hold = { GestureRange:new { ges = "hold", range = range } },
        HoldRelease = { GestureRange:new { ges = "hold_release", range = range } },
        Swipe = { GestureRange:new { ges = "swipe", range = range } },
    }
    if Device:hasKeys() then
        local Input = Device.input
        self.key_events.Back = { { Input.group.Back } }
        self.key_events.FocusUp = { { "Up" } }
        self.key_events.FocusDown = { { "Down" } }
        self.key_events.FocusLeft = { { "Left" } }
        self.key_events.FocusRight = { { "Right" } }
        self.key_events.Press = { { "Press" } }
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
    end
end

--- Returns false, keeping the old panel, when `build` returns nil.
function Sheet:layout()
    local args = self.build()
    if not args then return false end
    local old = self.panel
    local focused = old and self.focus and old.rows[self.focus]
    local bounds = Metrics.widthBounds(self.screen.w)
    self.panel = Panel.new {
        rows = args.rows,
        cfg = self.cfg,
        title = args.title,
        closable = true,
        title_row = args.title_row,
        title_cfg = args.title_row and Metrics.get(),
        subtitle = args.subtitle,
        min_w = math.max(bounds.min_w, old and old.w or 0),
        max_w = bounds.max_w,
        page = old and old.page,
    }
    local margin = self.cfg.margin
    local w, h = self.panel:measure(self.screen.h - 2 * margin)
    local r = Anchor.fixed("center", { w = w, h = h }, self.screen, margin)
    -- A rebuild keeps the width and top edge, so rows stay under the finger.
    if old then r = Anchor.clampRect({ x = r.x, y = old.y, w = w, h = h }, self.screen, margin) end
    self.panel:layout(r.x, r.y, r.w, r.h)
    if old then old:free() end
    self:focusRow(focused and indexOf(args.rows, focused.id), self.focus_cell)
    if self.focus_visible then self:ensureFocus() end
    return true
end

function Sheet:rebuild()
    if self.closed then return end
    local before = self.panel:dirtyRect()
    if not self:layout() then return self:close() end
    UIManager:setDirty("all", "ui", toGeom(Anchor.union(before, self.panel:dirtyRect())))
end

function Sheet:setBuild(build)
    self.build = build
    self:rebuild()
end

function Sheet:showRect()
    return toGeom(self.panel:dirtyRect())
end

function Sheet:dirty()
    UIManager:setDirty(self, "ui", self:showRect())
end

function Sheet:paintTo(bb)
    self.panel:paintTo(bb, {
        focus_index = self.focus_visible and self.focus or nil,
        focus_part = self.focus_cell and "cell" or nil,
        focus_cell = self.focus_cell,
        pressed = self.pressed,
    })
end

--- Shows `r` pressed for a moment before its action runs, like KOReader's menus.
function Sheet:flash(r)
    if not r or G_reader_settings:isFalse("flash_ui") then return end
    self.pressed = r
    UIManager:setDirty(self, "fast", toGeom(r))
    UIManager:forceRePaint()
    UIManager:yieldToEPDC()
    self.pressed = nil
    UIManager:setDirty(self, "ui", toGeom(r))
end

function Sheet:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self:showRect())
end

-- Geometry is stale after a rotation or resize: just close.
function Sheet:onSetDimensions()
    self:close()
end

Sheet.onScreenResize = Sheet.onSetDimensions
Sheet.onSetRotationMode = Sheet.onSetDimensions

function Sheet:onCloseWidget()
    self.closed = true
    self.panel:free()
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe = nil
    end
    if self.on_close then self.on_close() end
end

--- The row, or with `j` its cell, when it can act.
function Sheet:target(i, j)
    local row = self.panel.rows[i]
    if not row then return nil end
    if j then
        local cell = row.cells and row.cells[j]
        return cell and not cell.disabled and cell or nil
    end
    return Panel.actionable(row) and row or nil
end

--- `how` is "run" or "hold".
function Sheet:activate(how, i, j)
    local target = self:target(i, j)
    if not (target and target[how]) then return end
    self:flash(j and self.panel:cellRect(i, j) or self.panel:rowRect(i))
    target[how](self)
end

function Sheet:setPage(page)
    local panel = self.panel
    if page < 1 or page > panel:pageCount() or page == panel.page then return end
    panel:showPage(page)
    self:dirty()
end

function Sheet:onTap(_, ges)
    if self.focus_visible then
        self.focus_visible = false
        self:dirty()
    end
    local what, i, j = self.panel:hit(ges.pos.x, ges.pos.y)
    if not what then
        self:close()
    elseif what == "close" then
        self:flash(self.panel.close_rect)
        self:close()
    elseif what == "row" or what == "cell" then
        self:activate("run", i, j)
    elseif what == "prev" then
        self:setPage(self.panel.page - 1)
    elseif what == "next" then
        self:setPage(self.panel.page + 1)
    end
    return true
end

function Sheet:onHold(_, ges)
    local what, i, j = self.panel:hit(ges.pos.x, ges.pos.y)
    if what == "row" or what == "cell" then self:activate("hold", i, j) end
    return true
end

-- A sheet opened by a hold receives that hold's release.
function Sheet:onHoldRelease()
    return true
end

function Sheet:onSwipe(_, ges)
    if not self.panel:hit(ges.pos.x, ges.pos.y) then
        self:close()
        return true
    end
    local dir = ges.direction
    if dir == "west" or dir == "north" then
        self:setPage(self.panel.page + 1)
    elseif dir == "east" or dir == "south" then
        self:setPage(self.panel.page - 1)
    end
    return true
end

--- A cells row keeps the cell `prefer` when it is enabled, else its first enabled one.
function Sheet:focusRow(i, prefer)
    self.focus, self.focus_cell = i, nil
    local cells = i and self.panel.rows[i].cells
    if not cells then return end
    local keep = prefer and cells[prefer] and not cells[prefer].disabled
    self.focus_cell = keep and prefer or enabledCell(cells, 1, 1)
end

function Sheet:ensureFocus()
    local panel = self.panel
    if not (self.focus and Panel.actionable(panel.rows[self.focus])) then
        local page = panel.pages[panel.page]
        self:focusRow(panel:nextActionable(page.first - 1, 1))
    end
    local page = self.focus and panel:pageOf(self.focus)
    if page and page ~= panel.page then panel:showPage(page) end
end

function Sheet:moveFocus(step)
    local had = self.focus_visible
    self.focus_visible = true
    if had and self.focus then self:focusRow(self.panel:nextActionable(self.focus, step)) end
    self:ensureFocus()
    self:dirty()
    return true
end

function Sheet:onFocusUp()
    return self:moveFocus(-1)
end

function Sheet:onFocusDown()
    return self:moveFocus(1)
end

function Sheet:moveCell(step)
    local cells = self.focus_visible and self.focus_cell and self.panel.rows[self.focus].cells
    if not cells then return true end
    self.focus_cell = enabledCell(cells, self.focus_cell + step, step) or self.focus_cell
    self:dirty()
    return true
end

function Sheet:onFocusLeft()
    return self:moveCell(-1)
end

function Sheet:onFocusRight()
    return self:moveCell(1)
end

function Sheet:onPress()
    if not (self.focus_visible and self.focus) then return self:moveFocus(1) end
    self:activate("run", self.focus, self.focus_cell)
    return true
end

function Sheet:onBack()
    self:close()
    return true
end

function Sheet:onNextPage()
    self:setPage(self.panel.page + 1)
    return true
end

function Sheet:onPrevPage()
    self:setPage(self.panel.page - 1)
    return true
end

return Sheet
