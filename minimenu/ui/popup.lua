--[[--
A single full-screen, transparent InputContainer, so there is one key scope
and taps outside every panel close it. It paints a chain of panels: the
root, then one flyout per open folder or link.
]]

local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local Anchor = require("minimenu/ui/anchor")
local Context = require("minimenu/context")
local Kinds = require("minimenu/kinds/init")
local Panel = require("minimenu/ui/panel")
local Resolve = require("minimenu/resolve")
local Store = require("minimenu/store")

local Popup = InputContainer:extend {
    name = "MiniMenuPopup",
    menu_id = nil,
    open_opts = nil, -- { gesture, anchor, prefer, on_close }
    stop_events_propagation = true,
}

--- Point size of row icons at the current text size.
function Popup.iconPoints()
    return math.floor(Store.setting("font_size") * 1.1 + 0.5)
end

local function textFont()
    local font = Store.setting("font")
    if font and FontList.fontinfo[font] then return font end
    return "cfont"
end

--- Metrics shared by all panels, from the appearance settings.
function Popup.metrics()
    local font_size = Store.setting("font_size")
    local icon_pt = Popup.iconPoints()
    local row_h = Screen:scaleBySize(math.floor(font_size * Store.setting("row_spacing") + 0.5))
    local icon_size = Screen:scaleBySize(icon_pt)
    local pad = Screen:scaleBySize(Store.setting("padding"))
    local face = Font:getFace(textFont(), font_size)
    local shadow = Store.setting("shadow") and Screen:scaleBySize(3) or 0
    return {
        row_h = row_h,
        sep_h = Screen:scaleBySize(9),
        title_h = row_h,
        pager_h = math.floor(row_h * 0.9),
        border = Size.border.window,
        -- Keeps the top and bottom corners of a one-row panel apart (Panel:uninvertCorners).
        radius = math.min(Screen:scaleBySize(Store.setting("radius")), math.floor(row_h / 2)),
        line = Size.line.medium,
        focus_border = Size.border.thick * 2,
        pad = pad,
        icon_size = icon_size,
        icon_col = icon_size + pad,
        trail_col = icon_size + pad,
        shadow = shadow,
        margin = math.max(Screen:scaleBySize(Store.setting("edge_margin")), shadow),
        offset = Screen:scaleBySize(12),
        face = face,
        title_face = face,
        icon_face = Font:getFace("cfont", icon_pt),
    }
end

local function union(a, b)
    if not a then return b end
    if not b then return a end
    local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
    return {
        x = x,
        y = y,
        w = math.max(a.x + a.w, b.x + b.w) - x,
        h = math.max(a.y + a.h, b.y + b.h) - y,
    }
end

local function toGeom(r)
    return r and Geom:new { x = r.x, y = r.y, w = r.w, h = r.h }
end

function Popup:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.screen = { w = sw, h = sh }
    self.dimen = Geom:new { x = 0, y = 0, w = sw, h = sh }
    self.open_opts = self.open_opts or {}
    self.ctx = Context.current()
    self.ctx.menu_id = self.menu_id
    self.cfg = Popup.metrics()
    self.chain = {}
    self.menu = Store.menu(self.menu_id)
    self.options = Store.options(self.menu)

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
        self.key_events.CloseAll = { { "Menu" } }
        self.key_events.FocusUp = { { "Up" } }
        self.key_events.FocusDown = { { "Down" } }
        self.key_events.FocusLeft = { { "Left" } }
        self.key_events.FocusRight = { { "Right" } }
        self.key_events.Press = { { "Press" } }
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
    end

    self:buildLevel(1)
    self:placeLevel(1)
    self.unsubscribe = Store.subscribe(function(ev)
        self:onStoreEvent(ev)
    end)
end

function Popup:placeholderText()
    if self.ctx.name == "reader" then return _("Nothing here in the reader") end
    return _("Nothing here in the file browser")
end

function Popup:resolveRows(items)
    return Resolve.rows(items, self.ctx, Kinds.get, {
        hide_unavailable = self.options.hide_unavailable,
        placeholder = self:placeholderText(),
    })
end

function Popup:widthBounds()
    local sw = self.screen.w
    return {
        min_w = math.floor(sw * 0.3),
        max_w = math.floor(sw * 0.8),
    }
end

function Popup:maxPanelHeight()
    return math.floor(self.screen.h * 0.7)
end

function Popup:levelItems(k)
    if k == 1 then return self.menu.items end
    local entry = self.chain[k]
    local ok, items = pcall(entry.row.children)
    if not ok then
        logger.err("MiniMenu: could not open folder:", items)
        return {}
    end
    return items or {}
end

--- (Re)build the panel at level k, keeping its page.
function Popup:buildLevel(k)
    local entry = self.chain[k] or {}
    self.chain[k] = entry
    local old = entry.panel
    local bounds = self:widthBounds()
    entry.panel = Panel.new {
        rows = self:resolveRows(self:levelItems(k)),
        cfg = self.cfg,
        title = k == 1 and self.options.show_title and self.menu.title or nil,
        min_w = bounds.min_w,
        max_w = bounds.max_w,
        page = old and old.page or 1,
    }
    if old then old:free() end
end

function Popup:breadcrumb(k)
    local parts = {}
    if self.menu.title then table.insert(parts, self.menu.title) end
    for j = 2, k do
        local row = self.chain[j].row
        table.insert(parts, row.title or row.label or "")
    end
    return table.concat(parts, " \u{203A} ")
end

function Popup:anchorArgs()
    local o = self.open_opts
    local args = {}
    if o.anchor then
        local a = o.anchor
        args.rect = { x = a.x, y = a.y, w = a.w or 0, h = a.h or 0 }
        args.prefer = o.prefer
        args.gap = Size.margin.small
    elseif o.gesture and o.gesture.ges ~= "multiswipe" then
        local p = o.gesture.end_pos or o.gesture.pos
        if p and p.x and p.y then args.point = { x = p.x, y = p.y } end
    end
    return args
end

--- The panel's parent must already be placed.
function Popup:placeLevel(k)
    local entry = self.chain[k]
    local panel = entry.panel
    local cfg = self.cfg
    local max_h = self:maxPanelHeight()
    if k == 1 then
        local w, h = panel:measure(max_h)
        local args = self:anchorArgs()
        args.size, args.screen, args.margin, args.offset = { w = w, h = h }, self.screen, cfg.margin, cfg.offset
        args.position = self.options.position
        local r = Anchor.placeRoot(args)
        panel:layout(r.x, r.y, r.w, r.h)
        return
    end
    local parent_entry = self.chain[k - 1]
    local parent = parent_entry.panel
    local row_rect = parent:rowRect(parent_entry.open_index)
    if not self.direction then self.direction = Anchor.cascadeDirection(self.chain[1].panel:rect(), self.screen) end
    panel.header = nil
    local w = panel:measure(max_h)
    local bounds = self:widthBounds()
    local avoid = {}
    for j = 1, k - 2 do
        table.insert(avoid, self.chain[j].panel:rect())
    end
    local x, fw, mode = Anchor.flyoutX {
        parent = parent:rect(),
        width = w,
        screen = self.screen,
        margin = cfg.margin,
        direction = self.direction,
        overlap = cfg.border,
        indent = cfg.icon_col,
        min_w = bounds.min_w,
        avoid = avoid,
    }
    entry.mode = mode
    if mode == "stacked" then
        -- The card covers the row that opened it: give it a back header.
        panel.header = self:breadcrumb(k)
    end
    local _, h = panel:measure(max_h)
    local top = row_rect and (row_rect.y - cfg.border) or parent.y
    local y, fh = Anchor.flyoutY(top, h, self.screen, cfg.margin)
    if fh < h then
        _, h = panel:measure(fh)
        y = Anchor.flyoutY(top, h, self.screen, cfg.margin)
    end
    panel:layout(x, y, fw, h)
end

function Popup:chainRect(from)
    local r
    for k = from or 1, #self.chain do
        r = union(r, self.chain[k].panel:dirtyRect())
    end
    return r
end

function Popup:paintTo(bb)
    for k, entry in ipairs(self.chain) do
        entry.panel:paintTo(bb, {
            open_index = entry.open_index,
            focus_index = self.focus_visible and k == #self.chain and entry.focus or nil,
        })
    end
end

function Popup:showRect()
    return toGeom(self:chainRect(1))
end

function Popup:dirty(rect, uncovered)
    if not rect then return end
    if uncovered then
        UIManager:setDirty("all", "ui", toGeom(rect))
    else
        UIManager:setDirty(self, "ui", toGeom(rect))
    end
end

--- Close flyouts at level `from` and deeper.
function Popup:closeFrom(from)
    if from < 2 or from > #self.chain then return end
    local r = self:chainRect(from)
    local parent = self.chain[from - 1]
    r = union(r, parent.panel:rowRect(parent.open_index))
    for k = #self.chain, from, -1 do
        self.chain[k].panel:free()
        self.chain[k] = nil
    end
    parent.open_index = nil
    if #self.chain == 1 then self.direction = nil end
    self:dirty(r, true)
end

function Popup:openFlyout(k, index)
    local entry = self.chain[k]
    local row = entry.panel.rows[index]
    self:closeFrom(k + 1)
    entry.open_index = index
    self.chain[k + 1] = { row = row, item_id = row.item and row.item.id }
    self:buildLevel(k + 1)
    self:placeLevel(k + 1)
    self:dirty(union(self.chain[k + 1].panel:dirtyRect(), entry.panel:rowRect(index)))
    return self.chain[k + 1]
end

function Popup:runContext(k)
    local item_id = self.chain[k].item_id
    local host = {
        close = function()
            self:close()
        end,
    }
    -- Entries may refresh long after the tap, e.g. when a dialog they opened applies.
    function host.refresh()
        local entry = self.chain[k]
        if self.closed or not entry or entry.item_id ~= item_id then return end
        self:refreshLevel(k)
        host.refreshed = true
    end
    return { ui = self.ctx.ui, context = self.ctx, menu_id = self.menu_id, host = host }
end

--- Closes the popup before running, so actions that replace the view (opening
-- a book, exiting) never see it. keep_open rows run in place instead.
function Popup:runRow(k, index)
    local row = self.chain[k].panel.rows[index]
    if not row or not row.item then return end
    local fresh = Resolve.item(row.item, self.ctx, Kinds.get)
    if not fresh or not fresh.available or fresh.disabled or type(fresh.run) ~= "function" then return end
    local run_ctx = self:runContext(k)
    if fresh.keep_open then
        local ok, err = pcall(fresh.run, run_ctx)
        if not ok then logger.err("MiniMenu: action failed:", err) end
        if not self.closed and not run_ctx.host.refreshed then self:refreshLevel(k) end
        return
    end
    self:close()
    UIManager:nextTick(function()
        local ok, err = pcall(fresh.run, run_ctx)
        if not ok then logger.err("MiniMenu: action failed:", err) end
    end)
end

function Popup:activate(k, index)
    local row = self.chain[k].panel.rows[index]
    if not Resolve.actionable(row) then return end
    if row.children then
        if self.chain[k].open_index == index then
            self:closeFrom(k + 1)
        else
            self:openFlyout(k, index)
        end
    else
        self:runRow(k, index)
    end
end

function Popup:refreshLevel(k)
    local before = self.chain[k].panel:dirtyRect()
    local x, y = self.chain[k].panel.x, self.chain[k].panel.y
    self:buildLevel(k)
    local panel = self.chain[k].panel
    local w, h = panel:measure(
        k == 1 and self:maxPanelHeight() or math.min(self:maxPanelHeight(), self.screen.h - 2 * self.cfg.margin)
    )
    if k > 1 and self.chain[k].mode == "stacked" then
        panel.header = self:breadcrumb(k)
        w, h = panel:measure(self:maxPanelHeight())
    end
    w = math.min(w, self.screen.w - self.cfg.margin - x)
    y = math.min(y, self.screen.h - self.cfg.margin - h)
    panel:layout(x, y, w, h)
    local after = panel:dirtyRect()
    local same = before.w == after.w and before.h == after.h and before.x == after.x and before.y == after.y
    self:dirty(union(before, after), not same)
end

--- Rebuild the whole chain after an edit, keeping the open path where possible.
function Popup:rebuild()
    if self.closed then return end
    self.menu = Store.menu(self.menu_id)
    if not self.menu then return self:close() end
    self.options = Store.options(self.menu)
    local before = self:chainRect(1)
    local depth = #self.chain
    local path = {} -- path[k]: id of the item that opened level k
    for k = 2, depth do
        path[k] = self.chain[k].item_id
    end
    for k = depth, 2, -1 do
        self.chain[k].panel:free()
        self.chain[k] = nil
    end
    self.direction = nil
    self:buildLevel(1)
    self:placeLevel(1)
    for k = 2, depth do
        local id = path[k]
        if not id then break end
        local parent = self.chain[k - 1]
        local found
        for i, row in ipairs(parent.panel.rows) do
            if row.item and row.item.id == id and row.children then
                found = i
                break
            end
        end
        if not found then break end
        local page = parent.panel:pageOf(found)
        if page ~= parent.panel.page then
            parent.panel.page = page
            parent.panel:layout(parent.panel.x, parent.panel.y, parent.panel.w, parent.panel.h)
        end
        parent.open_index = found
        self.chain[k] = { row = parent.panel.rows[found], item_id = id }
        self:buildLevel(k)
        self:placeLevel(k)
    end
    local last = self.chain[#self.chain]
    last.open_index = nil
    if self.focus_visible then self:ensureFocus() end
    self:dirty(union(before, self:chainRect(1)), true)
end

function Popup:onStoreEvent(ev)
    if self.closed then return end
    if ev.type == "menu_deleted" and ev.menu_id == self.menu_id then return self:close() end
    if
        ev.type == "items_changed"
        or ev.type == "menu_changed"
        or ev.type == "menu_renamed"
        or ev.type == "settings_changed"
        or ev.type == "menu_deleted"
    then
        if ev.type == "settings_changed" then self.cfg = Popup.metrics() end
        self:rebuild()
    end
end

function Popup:setPage(k, page)
    local entry = self.chain[k]
    local panel = entry.panel
    if page < 1 or page > panel:pageCount() or page == panel.page then return false end
    self:closeFrom(k + 1)
    panel.page = page
    panel:layout(panel.x, panel.y, panel.w, panel.h)
    self:dirty(panel:dirtyRect())
    return true
end

-- Geometry is stale after a rotation or resize: just close.
function Popup:onSetDimensions()
    self:close()
end

Popup.onScreenResize = Popup.onSetDimensions
Popup.onSetRotationMode = Popup.onSetDimensions

function Popup:close()
    if self.closed then return end
    self.closed = true
    UIManager:close(self, "ui", self:showRect())
end

function Popup:onCloseWidget()
    self.closed = true
    for _, entry in ipairs(self.chain) do
        entry.panel:free()
    end
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe = nil
    end
    local API = package.loaded["minimenu/api"]
    if API and API.current == self then API.current = nil end
    if self.open_opts.on_close then
        local ok, err = pcall(self.open_opts.on_close)
        if not ok then logger.err("MiniMenu: on_close failed:", err) end
    end
end

--- Deepest panel under a point.
-- Returns level, what, index
function Popup:hitTest(px, py)
    for k = #self.chain, 1, -1 do
        local what, index = self.chain[k].panel:hit(px, py)
        if what then return k, what, index end
    end
end

function Popup:onTap(_, ges)
    self.focus_visible = false
    local k, what, index = self:hitTest(ges.pos.x, ges.pos.y)
    if not k then
        self:close()
        return true
    end
    if what == "back" then
        self:closeFrom(k)
        return true
    end
    if what == "row" and self.chain[k].open_index == index then
        self:closeFrom(k + 1)
        return true
    end
    -- A tap in an ancestor (or its visible strip) closes everything deeper.
    self:closeFrom(k + 1)
    if what == "row" then
        self:activate(k, index)
    elseif what == "prev" then
        self:setPage(k, self.chain[k].panel.page - 1)
    elseif what == "next" then
        self:setPage(k, self.chain[k].panel.page + 1)
    end
    return true
end

function Popup:onSwipe(_, ges)
    local k = self:hitTest(ges.pos.x, ges.pos.y)
    if not k then
        self:close()
        return true
    end
    local dir = ges.direction
    local panel = self.chain[k].panel
    if dir == "west" or dir == "north" then
        self:setPage(k, panel.page + 1)
    elseif dir == "east" or dir == "south" then
        self:setPage(k, panel.page - 1)
    end
    return true
end

-- A popup opened by a hold receives that hold's release; rows act on tap
-- and hold only, so releases are swallowed.
function Popup:onHoldRelease()
    return true
end

function Popup:onHold(_, ges)
    local k, what, index = self:hitTest(ges.pos.x, ges.pos.y)
    if not k or what ~= "row" then return true end
    local row = self.chain[k].panel.rows[index]
    local ItemDialog = require("minimenu/ui/item_dialog")
    if row.placeholder then
        local folder_id, menu_id = self:folderIdAt(k)
        require("minimenu/ui/pickers/kinds").add({ menu_id = menu_id, folder_id = folder_id, ctx = self.ctx })
    elseif row.item then
        ItemDialog.show(self.menu_id, row.item.id, self.ctx)
    end
    return true
end

--- Folder and menu whose items level k shows. A linked menu is edited as
-- that menu's top level.
-- Returns folder_id|nil, menu_id
function Popup:folderIdAt(k)
    if k == 1 then return nil, self.menu_id end
    local row = self.chain[k].row
    if row.menu_id then return nil, row.menu_id end
    return row.item and row.item.id, self:menuIdAt(k - 1)
end

function Popup:menuIdAt(k)
    for j = k, 2, -1 do
        local row = self.chain[j].row
        if row.menu_id then return row.menu_id end
    end
    return self.menu_id
end

function Popup:deepest()
    return #self.chain, self.chain[#self.chain]
end

--- Next actionable row after `from` in direction `step`, across pages, wrapping.
local function nextActionable(rows, from, step)
    local n = #rows
    local i = from
    for _ = 1, n do
        i = i + step
        if i > n then
            i = 1
        elseif i < 1 then
            i = n
        end
        if Resolve.actionable(rows[i]) then return i end
    end
end

function Popup:ensureFocus()
    local _, entry = self:deepest()
    local rows = entry.panel.rows
    if not entry.focus or not Resolve.actionable(rows[entry.focus]) then
        local page = entry.panel.pages[entry.panel.page]
        entry.focus = nextActionable(rows, (page and page.first or 1) - 1, 1)
    end
    return entry.focus
end

function Popup:moveFocus(step)
    local k, entry = self:deepest()
    local panel = entry.panel
    local had = self.focus_visible
    self.focus_visible = true
    local before = self:chainRect(k)
    if not had or not entry.focus then
        self:ensureFocus()
    else
        local nxt = nextActionable(panel.rows, entry.focus, step)
        if nxt then entry.focus = nxt end
    end
    if entry.focus then
        local page = panel:pageOf(entry.focus)
        if page and page ~= panel.page then
            panel.page = page
            panel:layout(panel.x, panel.y, panel.w, panel.h)
        end
    end
    self:dirty(union(before, panel:dirtyRect()))
    return true
end

function Popup:onFocusUp()
    return self:moveFocus(-1)
end

function Popup:onFocusDown()
    return self:moveFocus(1)
end

function Popup:pressFocused(open_only)
    local k, entry = self:deepest()
    if not self.focus_visible or not entry.focus then return self:moveFocus(1) end
    local row = entry.panel.rows[entry.focus]
    if not Resolve.actionable(row) then return true end
    if row.children then
        if entry.open_index ~= entry.focus then
            local child = self:openFlyout(k, entry.focus)
            child.focus = nil
            self.focus_visible = true
            self:ensureFocus()
            self:dirty(child.panel:dirtyRect())
        end
    elseif not open_only then
        self:runRow(k, entry.focus)
    end
    return true
end

function Popup:onPress()
    return self:pressFocused(false)
end

function Popup:onFocusRight()
    return self:pressFocused(true)
end

function Popup:closeDeepest()
    local k = #self.chain
    if k <= 1 then return false end
    local parent = self.chain[k - 1]
    local opener = parent.open_index
    self:closeFrom(k)
    -- Focus goes back to the row that opened the closed flyout.
    parent.focus = opener or parent.focus
    return true
end

function Popup:onFocusLeft()
    if self:closeDeepest() then self.focus_visible = true end
    return true
end

function Popup:onBack()
    if not self:closeDeepest() then self:close() end
    return true
end

function Popup:onCloseAll()
    self:close()
    return true
end

function Popup:onNextPage()
    local k, entry = self:deepest()
    self:setPage(k, entry.panel.page + 1)
    return true
end

function Popup:onPrevPage()
    local k, entry = self:deepest()
    self:setPage(k, entry.panel.page - 1)
    return true
end

return Popup
