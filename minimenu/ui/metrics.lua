-- Sizes shared by every panel, from the appearance settings.

local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local Store = require("minimenu/store")
local Screen = Device.screen

local Metrics = {}

function Metrics.iconPoints()
    return math.floor(Store.setting("font_size") * 1.1 * Store.setting("icon_scale") / 100 + 0.5)
end

local function textFont()
    local font = Store.setting("font")
    if font and FontList.fontinfo[font] then return font end
    return "cfont"
end

-- Mixed-case text looks centered lower than its capitals: halfway down to
-- the middle of its lowercase letters. Returns that height above the baseline.
local function textMiddle(face)
    local cap, x = RenderText:getGlyph(face, 0x48).t, RenderText:getGlyph(face, 0x78).t -- "H", "x"
    return (cap + x) / 4
end

function Metrics.get()
    local font_size = Store.setting("font_size")
    local icon_pt = Metrics.iconPoints()
    local icon_size = Screen:scaleBySize(icon_pt)
    -- Rows are at least 1.25x the icon height so scaled-up icons keep a margin.
    local row_h = math.max(
        Screen:scaleBySize(math.floor(font_size * Store.setting("row_spacing") + 0.5)),
        math.ceil(icon_size * 1.25)
    )
    local pad = Screen:scaleBySize(Store.setting("padding"))
    local shadow = Store.setting("shadow") and Screen:scaleBySize(3) or 0
    local face = Font:getFace(textFont(), font_size)
    return {
        row_h = row_h,
        sep_h = Screen:scaleBySize(9),
        pager_h = math.floor(row_h * 0.9),
        border = Size.border.window,
        -- Keeps the top and bottom corners of a one-row panel apart (Panel:uninvertCorners).
        radius = math.min(Screen:scaleBySize(Store.setting("radius")), math.floor(row_h / 2)),
        line = Size.line.medium,
        focus_border = Size.border.thick * 2,
        pad = pad,
        icon_size = icon_size,
        icon_col = icon_size + pad,
        -- The second action's tap target: wider than the icon, even without padding.
        side_col = icon_size + 2 * math.max(pad, Screen:scaleBySize(8)),
        shadow = shadow,
        margin = math.max(Screen:scaleBySize(Store.setting("edge_margin")), shadow),
        offset = Screen:scaleBySize(12),
        face = face,
        text_mid = textMiddle(face),
        icon_face = Font:getFace("cfont", icon_pt),
    }
end

--- Panel width limits on a screen `screen_w` pixels wide.
function Metrics.widthBounds(screen_w)
    return { min_w = math.floor(screen_w * 0.3), max_w = math.floor(screen_w * 0.8) }
end

return Metrics
