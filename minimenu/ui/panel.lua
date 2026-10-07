--[[--
One panel of the popup: the root or a flyout. Not a widget: the popup
paints panels in chain order and routes input to them.
]]

local Blitbuffer = require("ffi/blitbuffer")
local RowView = require("minimenu/ui/row")

local Panel = {}
Panel.__index = Panel

local BACK = "\u{E840}" -- chevron-left

--[[--
args:
    rows        resolved rows
    cfg         shared metrics (see Popup.metrics)
    title       title text (root), or nil
    header      breadcrumb text for a stacked flyout, or nil
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

function Panel:computeColumns()
    local cols = { icon = false, trail = false }
    for _, row in ipairs(self.rows) do
        if row.icon and row.icon ~= "" then cols.icon = true end
        if row.children or row.checked ~= nil then cols.trail = true end
    end
    self.cols = cols
end

function Panel:rowHeight(row)
    return row.separator and self.cfg.sep_h or self.cfg.row_h
end

function Panel:titleHeight()
    if self.header or self.title then return self.cfg.title_h end
    return 0
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

function Panel:naturalWidth()
    if self.natural_w then return self.natural_w end
    local cfg = self.cfg
    local natural = 0
    for _, row in ipairs(self.rows) do
        natural = math.max(natural, RowView.naturalWidth(row, cfg, self.cols))
    end
    if self.title then
        local tw = RowView.textWidget(self.title, cfg.title_face, { bold = true })
        natural = math.max(natural, tw:getSize().w)
        tw:free()
    end
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
    if self.title_view then
        self.title_view:free()
        self.title_view = nil
    end
    if self.back_view then
        self.back_view:free()
        self.back_view = nil
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
    self.title_rect = nil
    if self.header or self.title then
        self.title_rect = { x = inner_x, y = cy, w = inner_w, h = cfg.title_h }
        if self.header then
            self.back_view = RowView.textWidget(BACK, cfg.icon_face)
            local back_w = cfg.icon_col
            self.title_view = RowView.textWidget(self.header, cfg.title_face, {
                bold = true,
                max_width = inner_w - 2 * cfg.pad - back_w,
                truncate_left = true,
            })
        else
            self.title_view = RowView.textWidget(self.title, cfg.title_face, {
                bold = true,
                max_width = inner_w - 2 * cfg.pad,
            })
        end
        cy = cy + cfg.title_h
    end
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

--- Returns "row", index | "back" | "title" | "prev" | "next" | "frame" | nil
function Panel:hit(px, py)
    if not contains(self, px, py) then return nil end
    if self.title_rect and contains(self.title_rect, px, py) then
        if self.header and px < self.title_rect.x + self.cfg.icon_col + self.cfg.pad then return "back" end
        return self.header and "back" or "title"
    end
    if self.pager_rect and contains(self.pager_rect, px, py) then
        local third = self.pager_rect.w / 3
        if px < self.pager_rect.x + third then return "prev" end
        if px >= self.pager_rect.x + 2 * third then return "next" end
        return "frame"
    end
    for i, r in pairs(self.row_rects) do
        if contains(r, px, py) then return "row", i end
    end
    return "frame"
end

--- Returns whether `r` touches the top and the bottom inner edge, where the corners round
function Panel:touchesEdges(r)
    local b = self.cfg.border
    return r.y <= self.y + b, r.y + r.h >= self.y + self.h - b
end

--- Undo the inversion of row rect `r` outside the rounded corners. Popup
-- repaints don't restore what lies outside a panel, so nothing may stay
-- painted there; the border painted afterwards covers the seam.
function Panel:uninvertCorners(bb, r)
    local rad = self.cfg.radius - self.cfg.border
    if rad <= 0 then return end
    local top, bottom = self:touchesEdges(r)
    for i = 0, rad - 1 do
        local dy = rad - i - 0.5
        local cut = rad - math.floor(math.sqrt(rad * rad - dy * dy) + 0.5)
        if cut > 0 then
            if top then
                bb:invertRect(r.x, r.y + i, cut, 1)
                bb:invertRect(r.x + r.w - cut, r.y + i, cut, 1)
            end
            if bottom then
                bb:invertRect(r.x, r.y + r.h - 1 - i, cut, 1)
                bb:invertRect(r.x + r.w - cut, r.y + r.h - 1 - i, cut, 1)
            end
        end
    end
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
        local tx = r.x + cfg.pad
        if self.back_view then
            local bw = self.back_view:getSize()
            self.back_view:paintTo(bb, tx + math.floor((cfg.icon_size - bw.w) / 2), r.y + math.floor((r.h - bw.h) / 2))
            tx = tx + cfg.icon_col
        end
        local ts = self.title_view:getSize()
        self.title_view:paintTo(bb, tx, r.y + math.floor((r.h - ts.h) / 2))
        bb:paintRect(r.x, r.y + r.h - cfg.line, r.w, cfg.line, Blitbuffer.COLOR_BLACK)
    end
    for i, r in pairs(self.row_rects) do
        local open = state and state.open_index == i
        RowView.paint(bb, self.views[i], cfg, r.x, r.y, r.w, r.h, { open = open })
        if open then self:uninvertCorners(bb, r) end
        if state and state.focus_index == i then
            local top, bottom = self:touchesEdges(r)
            local radius = (top or bottom) and math.max(cfg.radius - cfg.border, 0) or nil
            bb:paintBorder(r.x, r.y, r.w, r.h, cfg.focus_border, Blitbuffer.COLOR_BLACK, radius)
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
    -- Last, so it covers the seams left by uninvertCorners.
    bb:paintBorder(x, y, w, h, cfg.border, Blitbuffer.COLOR_BLACK, cfg.radius)
end

function Panel:free()
    self:freeViews()
end

return Panel
