-- Sizes shared by every panel, from the appearance settings.

local Device = require("device")
local Font = require("ui/font")
local FontList = require("fontlist")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local Store = require("minimenu/store")
local Screen = Device.screen

local Metrics = {}

function Metrics.iconPoints(setting)
    setting = setting or Store.setting
    return math.floor(setting("font_size") * 1.1 * setting("icon_scale") / 100 + 0.5)
end

local function textFont(setting)
    local font = setting("font")
    if font and FontList.fontinfo[font] then return font end
    return "cfont"
end

--- Half the height of a capital "H": where icons center, above the label's baseline.
local function capMiddle(face)
    return RenderText:getGlyph(face, 0x48).t / 2
end

function Metrics.get(setting)
    setting = setting or Store.setting
    local font_size = setting("font_size")
    local icon_pt = Metrics.iconPoints(setting)
    local icon_size = Screen:scaleBySize(icon_pt)
    -- Rows are at least 1.25x the icon height so scaled-up icons keep a margin.
    local row_h =
        math.max(Screen:scaleBySize(math.floor(font_size * setting("row_spacing") + 0.5)), math.ceil(icon_size * 1.25))
    local pad = Screen:scaleBySize(setting("padding"))
    local gap = math.max(pad, Screen:scaleBySize(8))
    local shadow = setting("shadow") and Screen:scaleBySize(3) or 0
    local font = textFont(setting)
    local face = Font:getFace(font, font_size)
    return {
        row_h = row_h,
        sep_h = Screen:scaleBySize(9),
        header_h = math.floor(row_h * 0.75),
        pager_h = math.floor(row_h * 0.9),
        border = Size.border.window,
        -- Keeps the top and bottom corners of a one-row panel apart (Panel:uninvertCorners).
        radius = math.min(Screen:scaleBySize(setting("radius")), math.floor(row_h / 2)),
        line = Size.line.medium,
        focus_border = Size.border.thick * 2,
        pad = pad,
        gap = gap,
        icon_size = icon_size,
        icon_col = icon_size + pad,
        -- The second action's tap target: wider than the icon, even without padding.
        side_col = icon_size + 2 * gap,
        shadow = shadow,
        margin = math.max(Screen:scaleBySize(setting("edge_margin")), shadow),
        offset = Screen:scaleBySize(12),
        face = face,
        cap_mid = capMiddle(face),
        small_face = Font:getFace(font, math.floor(font_size * 0.8 + 0.5)),
        icon_face = Font:getFace("cfont", icon_pt),
    }
end

function Metrics.defaults()
    return Metrics.get(function(key)
        return Store.DEFAULT_SETTINGS[key]
    end)
end

--- Panel width limits on a screen `screen_w` pixels wide.
function Metrics.widthBounds(screen_w)
    return { min_w = math.floor(screen_w * 0.3), max_w = math.floor(screen_w * 0.8) }
end

return Metrics
