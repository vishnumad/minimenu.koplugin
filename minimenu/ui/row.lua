-- Row views: icon, label and a trailing chevron or checkbox, built for a
-- given width and painted by their panel.

local Blitbuffer = require("ffi/blitbuffer")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local Util = require("minimenu/util")

local RowView = {}

RowView.CHEVRON = "\u{E841}" -- chevron-right
RowView.CHECKED = "\u{F046}" -- check-square-o
RowView.UNCHECKED = "\u{F096}" -- square-o

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

--- `icon` is a glyph or "[icon=NAME]".
function RowView.iconWidget(icon, cfg, fgcolor)
    if not icon or icon == "" then return nil end
    local name = Util.iconName(icon)
    if name then return IconWidget:new { icon = name, width = cfg.icon_size, height = cfg.icon_size, alpha = true } end
    return textWidget(icon, cfg.icon_face, { fgcolor = fgcolor })
end

function RowView.trailingText(row)
    if row.children then return RowView.CHEVRON end
    if row.checked ~= nil then return row.checked and RowView.CHECKED or RowView.UNCHECKED end
end

--- Content width, without panel padding.
function RowView.naturalWidth(row, cfg, cols)
    if row.separator then return 0 end
    local w = 0
    local label = textWidget(row.label or "", cfg.face)
    w = w + label:getSize().w
    label:free()
    if cols.icon then w = w + cfg.icon_col end
    if cols.trail then w = w + cfg.trail_col end
    return w
end

function RowView.build(row, cfg, cols, w)
    local view = { row = row }
    if row.separator then return view end
    local fg = (row.dim or row.placeholder) and COLOR_DIM or Blitbuffer.COLOR_BLACK
    local label_w = w - (cols.icon and cfg.icon_col or 0) - (cols.trail and cfg.trail_col or 0)
    view.label = textWidget(row.label or "", cfg.face, { fgcolor = fg, max_width = math.max(label_w, 1) })
    if cols.icon then view.icon = RowView.iconWidget(row.icon, cfg, fg) end
    local trail = RowView.trailingText(row)
    if trail and cols.trail then view.trail = textWidget(trail, cfg.icon_face, { fgcolor = fg }) end
    view.cols = cols
    return view
end

--- state.open inverts the row. The panel paints the focus ring.
function RowView.paint(bb, view, cfg, x, y, w, h, state)
    local row = view.row
    if row.separator then
        local lh = cfg.line
        bb:paintRect(x + cfg.pad, y + math.floor((h - lh) / 2), w - 2 * cfg.pad, lh, Blitbuffer.COLOR_DARK_GRAY)
        return
    end
    local cx = x + cfg.pad
    local function vcenter(widget)
        return y + math.floor((h - widget:getSize().h) / 2)
    end
    if view.cols.icon then
        if view.icon then
            local iw = view.icon:getSize().w
            view.icon:paintTo(bb, cx + math.floor((cfg.icon_size - iw) / 2), vcenter(view.icon))
        end
        cx = cx + cfg.icon_col
    end
    view.label:paintTo(bb, cx, vcenter(view.label))
    if view.trail then
        local tw = view.trail:getSize().w
        view.trail:paintTo(bb, x + w - cfg.pad - math.floor((cfg.trail_col + tw) / 2), vcenter(view.trail))
    end
    if state and state.open then bb:invertRect(x, y, w, h) end
end

function RowView.free(view)
    for _, k in ipairs({ "label", "icon", "trail" }) do
        if view[k] and view[k].free then view[k]:free() end
        view[k] = nil
    end
end

return RowView
