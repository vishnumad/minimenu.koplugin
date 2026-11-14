--[[--
One panel of the popup: the root or a flyout. Not a widget: the popup
paints panels in chain order and routes input to them.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Resolve = require("minimenu/resolve")
local RowView = require("minimenu/ui/row")

local Panel = {}
Panel.__index = Panel

local BACK = "\u{E840}" -- chevron-left
local CLOSE = "\u{E855}" -- close

--[[--
args:
    rows        resolved rows
    cfg         shared metrics (see Metrics.get)
    title       title text (root), or nil
    header      breadcrumb text for a stacked flyout, or nil
    closable    whether the title line ends in a close button
    title_row   a resolved row drawn under the title line, or nil
    title_cfg   metrics for title_row, defaulting to cfg
    subtitle    dim text under title_row, or nil
    min_w, max_w, page
]]
function Panel.new(args)
    local self = setmetatable({}, Panel)
    for k, v in pairs(args) do
        self[k] = v
    end
    self.page = self.page or 1
    self.views = {}
    self:computeColumns()
    return self
end

local function columns(rows)
    local cols = { icon = false, trail = false }
    for _, row in ipairs(rows) do
        if row.icon and row.icon ~= "" then cols.icon = true end
        if row.children or row.checked ~= nil then cols.trail = true end
    end
    return cols
end

function Panel:computeColumns()
    self.cols = columns(self.rows)
    self.title_cols = self.title_row and columns({ self.title_row })
end

function Panel:titleCfg()
    return self.title_cfg or self.cfg
end

function Panel:rowHeight(row)
    if row.separator then return self.cfg.sep_h end
    if row.section then return self.cfg.header_h end
    return self.cfg.row_h
end

function Panel:titleLineHeight()
    return (self.header or self.title) and self.cfg.row_h or 0
end

function Panel:titleHeight()
    local h = self:titleLineHeight()
    if self.title_row then h = h + self:titleCfg().row_h + (self.subtitle and self.cfg.header_h or 0) end
    return h
end

function Panel:paginate(content_h)
    local pages = {}
    local first, used = 1, 0
    for i, row in ipairs(self.rows) do
        local h = self:rowHeight(row)
        if used + h > content_h and i > first then
            table.insert(pages, { first = first, last = i - 1, h = used })
            first, used = i, 0
        end
        used = used + h
    end
    table.insert(pages, { first = first, last = #self.rows, h = used })
    return pages
end

function Panel:closeWidth()
    return self.closable and self.cfg.side_col - self.cfg.pad or 0
end

function Panel:naturalWidth()
    if self.natural_w then return self.natural_w end
    local cfg = self.cfg
    local natural = 0
    for _, row in ipairs(self.rows) do
        natural = math.max(natural, RowView.naturalWidth(row, cfg, self.cols))
    end
    if self.title then
        natural = math.max(natural, RowView.textWidth(self.title, cfg.face, { bold = true }) + self:closeWidth())
    end
    if self.title_row then
        local tcfg = self:titleCfg()
        -- The title row pads itself with tcfg.pad instead of the panel's cfg.pad.
        local tw = RowView.naturalWidth(self.title_row, tcfg, self.title_cols) + 2 * (tcfg.pad - cfg.pad)
        natural = math.max(natural, tw)
    end
    if self.subtitle then natural = math.max(natural, RowView.textWidth(self.subtitle, cfg.small_face)) end
    self.natural_w = natural
    return natural
end

--- Returns outer w, h for a maximum outer height
function Panel:measure(max_h)
    local cfg = self.cfg
    local chrome = 2 * cfg.border + self:titleHeight()
    local content = max_h - chrome
    self.pages = self:paginate(content)
    if #self.pages > 1 then
        content = max_h - chrome - cfg.pager_h
        self.pages = self:paginate(content)
    end
    if self.page > #self.pages then self.page = #self.pages end
    local content_h = 0
    for _, p in ipairs(self.pages) do
        content_h = math.max(content_h, p.h)
    end
    local h = chrome + content_h + (#self.pages > 1 and cfg.pager_h or 0)

    local w = self:naturalWidth() + 2 * cfg.pad + 2 * cfg.border
    w = math.max(self.min_w or 0, math.min(w, self.max_w or w))
    self.w, self.h = w, h
    return w, h
end

function Panel:freeViews()
    for _, v in pairs(self.views) do
        RowView.free(v)
    end
    self.views = {}
    for _, k in ipairs({ "title_view", "close_view", "subtitle_view", "back_view" }) do
        if self[k] then
            self[k]:free()
            self[k] = nil
        end
    end
    if self.title_row_view then
        RowView.free(self.title_row_view)
        self.title_row_view = nil
    end
    if self.pager_views then
        for _, v in pairs(self.pager_views) do
            v:free()
        end
        self.pager_views = nil
    end
end

--- Build the views for the current page. `w` may be narrower than measured.
function Panel:layout(x, y, w, h)
    local cfg = self.cfg
    self.x, self.y, self.w, self.h = x, y, w, h
    self:freeViews()
    local inner_x = x + cfg.border
    local inner_w = w - 2 * cfg.border
    local cy = y + cfg.border
    local title_h = self:titleHeight()
    self.title_rect = nil
    if title_h > 0 then self.title_rect = { x = inner_x, y = cy, w = inner_w, h = title_h } end
    self.close_rect = nil
    if self.header then
        self.back_view = RowView.textWidget(BACK, cfg.icon_face)
        local back_w = cfg.icon_col
        self.title_view = RowView.textWidget(self.header, cfg.face, {
            bold = true,
            max_width = inner_w - 2 * cfg.pad - back_w,
            truncate_left = true,
        })
    elseif self.title then
        self.title_view = RowView.textWidget(self.title, cfg.face, {
            bold = true,
            max_width = inner_w - 2 * cfg.pad - self:closeWidth(),
        })
    end
    if self.closable then
        self.close_view = RowView.textWidget(CLOSE, cfg.icon_face)
        self.close_rect = { x = inner_x + inner_w - cfg.side_col, y = cy, w = cfg.side_col, h = cfg.row_h }
    end
    if self.title_row then
        local tcfg = self:titleCfg()
        self.title_row_view = RowView.build(self.title_row, tcfg, self.title_cols, inner_w - 2 * tcfg.pad)
        if self.subtitle then
            self.subtitle_view = RowView.textWidget(self.subtitle, cfg.small_face, {
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                max_width = inner_w - 2 * cfg.pad,
            })
        end
    end
    cy = cy + title_h
    self.row_rects = {}
    local page = self.pages[self.page]
    for i = page.first, page.last do
        local row = self.rows[i]
        local rh = self:rowHeight(row)
        self.row_rects[i] = { x = inner_x, y = cy, w = inner_w, h = rh }
        self.views[i] = RowView.build(row, cfg, self.cols, inner_w - 2 * cfg.pad)
        cy = cy + rh
    end
    self.pager_rect = nil
    if #self.pages > 1 then
        self.pager_rect = { x = inner_x, y = y + h - cfg.border - cfg.pager_h, w = inner_w, h = cfg.pager_h }
        local dim = Blitbuffer.COLOR_DARK_GRAY
        self.pager_views = {
            prev = RowView.textWidget(
                BACK,
                cfg.icon_face,
                { fgcolor = self.page > 1 and Blitbuffer.COLOR_BLACK or dim }
            ),
            next = RowView.textWidget(
                RowView.CHEVRON,
                cfg.icon_face,
                { fgcolor = self.page < #self.pages and Blitbuffer.COLOR_BLACK or dim }
            ),
            label = RowView.textWidget(("%d / %d"):format(self.page, #self.pages), cfg.face),
        }
    end
end

function Panel:showPage(page)
    self.page = page
    self:layout(self.x, self.y, self.w, self.h)
end

function Panel:rect()
    return { x = self.x, y = self.y, w = self.w, h = self.h }
end

--- Rect to repaint for this panel, including its shadow.
function Panel:dirtyRect()
    local s = self.cfg.shadow
    return { x = self.x, y = self.y, w = self.w + s, h = self.h + s }
end

function Panel:rowRect(i)
    return self.row_rects and self.row_rects[i]
end

--- The second action's part of row i, or nil when it has none.
function Panel:sideRect(i)
    local r = self:rowRect(i)
    if not r or not self.rows[i].secondary then return nil end
    local w = self.cfg.side_col
    return { x = r.x + r.w - w, y = r.y, w = w, h = r.h }
end

function Panel:cellRect(i, j)
    local r = self:rowRect(i)
    if not r or not self.rows[i].cells then return nil end
    return RowView.cellRect(r, #self.rows[i].cells, j)
end

function Panel:pageCount()
    return self.pages and #self.pages or 1
end

function Panel:pageOf(i)
    for p, page in ipairs(self.pages) do
        if i >= page.first and i <= page.last then return p end
    end
end

local function contains(r, px, py)
    return r and px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h
end

--- Returns "row", index | "secondary", index | "cell", index, cell | "back" | "title" | "close" | "prev" | "next"
-- | "frame" | nil
function Panel:hit(px, py)
    if not contains(self, px, py) then return nil end
    if contains(self.close_rect, px, py) then return "close" end
    if self.title_rect and contains(self.title_rect, px, py) then return self.header and "back" or "title" end
    if self.pager_rect and contains(self.pager_rect, px, py) then
        local third = self.pager_rect.w / 3
        if px < self.pager_rect.x + third then return "prev" end
        if px >= self.pager_rect.x + 2 * third then return "next" end
        return "frame"
    end
    for i, r in pairs(self.row_rects) do
        if contains(r, px, py) then
            local row = self.rows[i]
            if row.section then return "frame" end
            if row.cells then
                for j = 1, #row.cells do
                    if contains(self:cellRect(i, j), px, py) then return "cell", i, j end
                end
            end
            if contains(self:sideRect(i), px, py) then return "secondary", i end
            return "row", i
        end
    end
    return "frame"
end

function Panel.actionable(row)
    if not row or row.section then return false end
    if row.cells then
        for _, cell in ipairs(row.cells) do
            if not cell.disabled then return true end
        end
        return false
    end
    return Resolve.actionable(row)
end

--- Next actionable row after `from` in direction `step`, across pages, wrapping.
function Panel:nextActionable(from, step)
    local n = #self.rows
    local i = from
    for _ = 1, n do
        i = i + step
        if i > n then
            i = 1
        elseif i < 1 then
            i = n
        end
        if Panel.actionable(self.rows[i]) then return i end
    end
end

--- Returns whether `r` touches the top, bottom, left and right inner edges, where the corners round
function Panel:touchesEdges(r)
    local b = self.cfg.border
    return r.y <= self.y + b, r.y + r.h >= self.y + self.h - b, r.x <= self.x + b, r.x + r.w >= self.x + self.w - b
end

--- Undo the inversion of `r` outside the rounded corners. Popup repaints
-- don't restore what lies outside a panel, so nothing may stay painted
-- there; the border painted afterwards covers the seam.
function Panel:uninvertCorners(bb, r)
    local rad = self.cfg.radius - self.cfg.border
    if rad <= 0 then return end
    local top, bottom, left, right = self:touchesEdges(r)
    for i = 0, rad - 1 do
        local dy = rad - i - 0.5
        local cut = rad - math.floor(math.sqrt(rad * rad - dy * dy) + 0.5)
        local function uninvert(y)
            if left then bb:invertRect(r.x, y, cut, 1) end
            if right then bb:invertRect(r.x + r.w - cut, y, cut, 1) end
        end
        if cut > 0 then
            if top then uninvert(r.y + i) end
            if bottom then uninvert(r.y + r.h - 1 - i) end
        end
    end
end

local function paintCenteredY(bb, widget, x, y, h)
    widget:paintTo(bb, x, y + math.floor((h - widget:getSize().h) / 2))
end

function Panel:paintTitleLine(bb, r)
    local cfg = self.cfg
    local tx = r.x + cfg.pad
    if self.back_view then
        paintCenteredY(
            bb,
            self.back_view,
            tx + math.floor((cfg.icon_size - self.back_view:getSize().w) / 2),
            r.y,
            cfg.row_h
        )
        tx = tx + cfg.icon_col
    end
    paintCenteredY(bb, self.title_view, tx, r.y, cfg.row_h)
    if self.close_view then
        paintCenteredY(bb, self.close_view, r.x + r.w - cfg.pad - self.close_view:getSize().w, r.y, cfg.row_h)
    end
end

function Panel:paintTitleRow(bb, r)
    local cfg, tcfg = self.cfg, self:titleCfg()
    local y = r.y + self:titleLineHeight()
    if y > r.y then bb:paintRect(r.x, y - cfg.line, r.w, cfg.line, Blitbuffer.COLOR_DARK_GRAY) end
    RowView.paint(bb, self.title_row_view, tcfg, r.x, y, r.w, tcfg.row_h)
    if self.subtitle_view then paintCenteredY(bb, self.subtitle_view, r.x + cfg.pad, y + tcfg.row_h, cfg.header_h) end
end

function Panel:paintTo(bb, state)
    local cfg = self.cfg
    local x, y, w, h = self.x, self.y, self.w, self.h
    if cfg.shadow > 0 then
        bb:paintRoundedRect(x + cfg.shadow, y + cfg.shadow, w, h, Blitbuffer.COLOR_DARK_GRAY, cfg.radius)
    end
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, cfg.radius)
    if self.title_rect then
        local r = self.title_rect
        if self.title_view then self:paintTitleLine(bb, r) end
        if self.title_row_view then self:paintTitleRow(bb, r) end
        bb:paintRect(r.x, r.y + r.h - cfg.line, r.w, cfg.line, Blitbuffer.COLOR_BLACK)
    end
    for i, r in pairs(self.row_rects) do
        local open = state and state.open_index == i
        RowView.paint(bb, self.views[i], cfg, r.x, r.y, r.w, r.h, { open = open })
        if open then self:uninvertCorners(bb, r) end
        if state and state.focus_index == i then
            local fr = state.focus_part == "secondary" and self:sideRect(i)
                or state.focus_part == "cell" and self:cellRect(i, state.focus_cell)
                or r
            local top, bottom = self:touchesEdges(fr)
            local radius = (top or bottom) and math.max(cfg.radius - cfg.border, 0) or nil
            bb:paintBorder(fr.x, fr.y, fr.w, fr.h, cfg.focus_border, Blitbuffer.COLOR_BLACK, radius)
        end
    end
    if self.pager_rect then
        local r = self.pager_rect
        bb:paintRect(r.x, r.y, r.w, cfg.line, Blitbuffer.COLOR_DARK_GRAY)
        local pv = self.pager_views
        local function center(widget, cx)
            local s = widget:getSize()
            widget:paintTo(bb, math.floor(cx - s.w / 2), r.y + math.floor((r.h - s.h) / 2))
        end
        center(pv.prev, r.x + r.w / 6)
        center(pv.label, r.x + r.w / 2)
        center(pv.next, r.x + 5 * r.w / 6)
    end
    local pressed = state and state.pressed
    if pressed then
        bb:invertRect(pressed.x, pressed.y, pressed.w, pressed.h)
        self:uninvertCorners(bb, pressed)
    end
    -- Last, so it covers the seams left by uninvertCorners.
    bb:paintBorder(x, y, w, h, cfg.border, Blitbuffer.COLOR_BLACK, cfg.radius)
end

function Panel:free()
    self:freeViews()
end

return Panel
