-- Row views: icon, label, a trailing chevron, checkbox or value and the
-- second action's icon, built for a given width and painted by their panel.
-- Only rows with a second action make room for it, so the others keep their
-- trailing icons at the edge. Section rows are a caption with a rule; cells
-- rows split the row into equal buttons; `indent` shifts a row right by that
-- many icon columns.

local Blitbuffer = require("ffi/blitbuffer")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local Util = require("minimenu/util")

local RowView = {}

RowView.CHEVRON = "\u{E841}" -- chevron-right
RowView.CHECKED = "\u{E834}" -- checkbox-marked-outline
RowView.UNCHECKED = "\u{E830}" -- checkbox-blank-outline
RowView.CHECK = "\u{E82B}" -- check

local COLOR_DIM = Blitbuffer.COLOR_DARK_GRAY

local function textWidget(text, face, opts)
    opts = opts or {}
    return TextWidget:new {
        text = text,
        face = face,
        bold = opts.bold,
        fgcolor = opts.fgcolor or Blitbuffer.COLOR_BLACK,
        max_width = opts.max_width,
        truncate_left = opts.truncate_left,
        padding = 0,
    }
end
RowView.textWidget = textWidget

local function indentWidth(row, cfg)
    return (row.indent or 0) * cfg.icon_col
end

local function widgetWidth(widget)
    local w = widget:getSize().w
    widget:free()
    return w
end

function RowView.textWidth(text, face, opts)
    return widgetWidth(textWidget(text, face, opts))
end

--- `icon` is a glyph or "[icon=NAME]".
function RowView.iconWidget(icon, cfg, fgcolor)
    if not icon or icon == "" then return nil end
    local name = Util.iconName(icon)
    if name then return IconWidget:new { icon = name, width = cfg.icon_size, height = cfg.icon_size, alpha = true } end
    return textWidget(icon, cfg.icon_face, { fgcolor = fgcolor })
end

local function isIcon(value)
    return Util.isGlyph(value) or Util.iconName(value)
end

local function valueWidget(value, cfg, fgcolor, max_width)
    if isIcon(value) then return RowView.iconWidget(value, cfg, fgcolor) end
    return textWidget(value, cfg.face, { fgcolor = fgcolor, max_width = max_width })
end

function RowView.trailingText(row)
    if row.children then return RowView.CHEVRON end
    if row.checked ~= nil then return row.checked and RowView.CHECKED or RowView.UNCHECKED end
end

function RowView.cellRect(r, n, j)
    local left = r.x + math.floor((j - 1) * r.w / n)
    local right = r.x + math.floor(j * r.w / n)
    return { x = left, y = r.y, w = right - left, h = r.h }
end

--- Content width, without panel padding.
function RowView.naturalWidth(row, cfg, cols)
    if row.separator then return 0 end
    if row.section then return RowView.textWidth(row.label or "", cfg.small_face, { bold = true }) end
    if row.cells then
        local widest = 0
        for _, cell in ipairs(row.cells) do
            widest = math.max(widest, RowView.textWidth(cell.label, cfg.face))
        end
        -- Cells span the panel padding too.
        return #row.cells * (widest + 2 * cfg.pad) - 2 * cfg.pad
    end
    local w = indentWidth(row, cfg) + RowView.textWidth(row.label or "", cfg.face)
    if cols.icon then w = w + cfg.icon_col end
    if row.value then
        w = w + cfg.gap + widgetWidth(valueWidget(row.value, cfg))
    elseif cols.trail then
        w = w + cfg.icon_col
    end
    if row.secondary then w = w + cfg.side_col end
    return w
end

function RowView.build(row, cfg, cols, w)
    local view = { row = row }
    if row.separator then return view end
    if row.section then
        view.label = textWidget(row.label or "", cfg.small_face, { bold = true, max_width = math.max(w, 1) })
        return view
    end
    if row.cells then
        local cell_w = math.floor((w + 2 * cfg.pad) / #row.cells) - 2 * cfg.pad
        view.cells = {}
        for j, cell in ipairs(row.cells) do
            view.cells[j] = textWidget(cell.label, cfg.face, {
                fgcolor = cell.disabled and COLOR_DIM or Blitbuffer.COLOR_BLACK,
                max_width = math.max(cell_w, 1),
            })
        end
        return view
    end
    local fg = (row.dim or row.placeholder) and COLOR_DIM or Blitbuffer.COLOR_BLACK
    local label_w = w
        - indentWidth(row, cfg)
        - (cols.icon and cfg.icon_col or 0)
        - (row.secondary and cfg.side_col or 0)
    if row.value then
        local label_need = RowView.textWidth(row.label or "", cfg.face) + cfg.gap
        view.value = valueWidget(row.value, cfg, fg, math.max(label_w - label_need, math.floor(label_w / 2), 1))
        view.value_is_icon = isIcon(row.value)
        label_w = label_w - view.value:getSize().w - cfg.gap
    elseif cols.trail then
        label_w = label_w - cfg.icon_col
    end
    view.label = textWidget(row.label or "", cfg.face, { fgcolor = fg, max_width = math.max(label_w, 1) })
    if cols.icon then view.icon = RowView.iconWidget(row.icon, cfg, fg) end
    local trail = RowView.trailingText(row)
    if trail and cols.trail then view.trail = textWidget(trail, cfg.icon_face, { fgcolor = fg }) end
    local side = row.secondary
    if side then view.side = RowView.iconWidget(side.icon, cfg, side.dim and COLOR_DIM or Blitbuffer.COLOR_BLACK) end
    view.cols = cols
    return view
end

local function centerY(widget, y, h)
    return y + math.floor((h - widget:getSize().h) / 2)
end

local function paintDivider(bb, cfg, x, y, h)
    local divider_h = math.floor(h / 2)
    bb:paintRect(x, y + math.floor((h - divider_h) / 2), cfg.line, divider_h, COLOR_DIM)
end

local function paintSection(bb, view, cfg, x, y, w, h)
    local label = view.label
    local lx = x + cfg.pad
    label:paintTo(bb, lx, centerY(label, y, h))
    local rule_x = lx + label:getSize().w + cfg.gap
    local rule_w = x + w - cfg.pad - rule_x
    if rule_w > 0 then bb:paintRect(rule_x, y + math.floor((h - cfg.line) / 2), rule_w, cfg.line, COLOR_DIM) end
end

local function paintCells(bb, view, cfg, x, y, w, h)
    local r = { x = x, y = y, w = w, h = h }
    for j, label in ipairs(view.cells) do
        local c = RowView.cellRect(r, #view.cells, j)
        if j > 1 then paintDivider(bb, cfg, c.x, y, h) end
        label:paintTo(bb, c.x + math.floor((c.w - label:getSize().w) / 2), centerY(label, y, h))
    end
end

--- state.open inverts the row. The panel paints the focus ring.
function RowView.paint(bb, view, cfg, x, y, w, h, state)
    local row = view.row
    if row.separator then
        local lh = cfg.line
        bb:paintRect(x + cfg.pad, y + math.floor((h - lh) / 2), w - 2 * cfg.pad, lh, Blitbuffer.COLOR_DARK_GRAY)
        return
    end
    if row.section then return paintSection(bb, view, cfg, x, y, w, h) end
    if row.cells then return paintCells(bb, view, cfg, x, y, w, h) end
    local label_y = centerY(view.label, y, h)
    -- Icons center on the label's capitals, not on the row: fonts differ in
    -- where their text sits within their line height.
    local mid = label_y + view.label:getBaseline() - cfg.cap_mid
    local function iconY(widget)
        return math.floor(mid - widget:getSize().h / 2 + 0.5)
    end
    local cx = x + cfg.pad + indentWidth(row, cfg)
    if view.cols.icon then
        if view.icon then
            local iw = view.icon:getSize().w
            view.icon:paintTo(bb, cx + math.floor((cfg.icon_size - iw) / 2), iconY(view.icon))
        end
        cx = cx + cfg.icon_col
    end
    view.label:paintTo(bb, cx, label_y)
    local right = x + w - (view.side and cfg.side_col or 0)
    if view.value then
        local vy = view.value_is_icon and iconY(view.value) or label_y
        view.value:paintTo(bb, right - cfg.pad - view.value:getSize().w, vy)
    elseif view.trail then
        local tw = view.trail:getSize().w
        view.trail:paintTo(bb, right - cfg.pad - math.floor((cfg.icon_size + tw) / 2), iconY(view.trail))
    end
    if view.side then
        paintDivider(bb, cfg, right, y, h)
        local sw = view.side:getSize().w
        view.side:paintTo(bb, right + math.floor((cfg.side_col - sw) / 2), iconY(view.side))
    end
    if state and state.open then bb:invertRect(x, y, w, h) end
end

function RowView.free(view)
    for _, k in ipairs({ "label", "icon", "value", "trail", "side" }) do
        if view[k] and view[k].free then view[k]:free() end
        view[k] = nil
    end
    for _, cell in ipairs(view.cells or {}) do
        cell:free()
    end
    view.cells = nil
end

return RowView
