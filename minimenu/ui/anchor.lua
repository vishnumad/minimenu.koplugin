--[[--
Placement of the popup's root panel and its flyouts. Rects are plain
{ x, y, w, h } tables; screens are { w, h }.
]]

local Anchor = {}

local floor = math.floor
local max, min = math.max, math.min

local function clamp(v, lo, hi)
    if hi < lo then return lo end
    return max(lo, min(v, hi))
end

--- Keep a panel inside the screen margins. Oversized panels are pinned to
-- the top/left margin (callers cap sizes beforehand).
function Anchor.clampRect(r, screen, margin)
    return {
        x = clamp(r.x, margin, screen.w - margin - r.w),
        y = clamp(r.y, margin, screen.h - margin - r.h),
        w = r.w,
        h = r.h,
    }
end

--- Anything other than a corner, "top" or "bottom" is centred.
function Anchor.fixed(position, size, screen, margin)
    local w, h = size.w, size.h
    local cx = floor((screen.w - w) / 2)
    local cy = floor((screen.h - h) / 2)
    local left, right = margin, screen.w - margin - w
    local top, bottom = margin, screen.h - margin - h
    local x, y
    if position == "top_left" then
        x, y = left, top
    elseif position == "top_right" then
        x, y = right, top
    elseif position == "bottom_left" then
        x, y = left, bottom
    elseif position == "bottom_right" then
        x, y = right, bottom
    elseif position == "top" then
        x, y = cx, top
    elseif position == "bottom" then
        x, y = cx, bottom
    else
        x, y = cx, cy
    end
    return Anchor.clampRect({ x = x, y = y, w = w, h = h }, screen, margin)
end

--- Open towards the side of the screen with the most room, offset from the
-- point on both axes so the panel never sits under the finger.
function Anchor.atPoint(point, size, screen, margin, offset)
    offset = offset or 0
    local w, h = size.w, size.h
    local x, y
    if point.x <= screen.w / 2 then
        x = point.x + offset
    else
        x = point.x - offset - w
    end
    if point.y <= screen.h / 2 then
        y = point.y + offset
    else
        y = point.y - offset - h
    end
    return Anchor.clampRect({ x = x, y = y, w = w, h = h }, screen, margin)
end

local OPPOSITE = { above = "below", below = "above", left = "right", right = "left" }

local function sideRect(side, rect, w, h, gap)
    if side == "above" then
        return { x = rect.x, y = rect.y - gap - h, w = w, h = h }
    elseif side == "below" then
        return { x = rect.x, y = rect.y + rect.h + gap, w = w, h = h }
    elseif side == "left" then
        return { x = rect.x - gap - w, y = rect.y, w = w, h = h }
    else -- right
        return { x = rect.x + rect.w + gap, y = rect.y, w = w, h = h }
    end
end

local function fits(r, screen, margin)
    return r.x >= margin and r.y >= margin and r.x + r.w <= screen.w - margin and r.y + r.h <= screen.h - margin
end

local function room(side, rect, screen)
    if side == "above" then
        return rect.y
    elseif side == "below" then
        return screen.h - (rect.y + (rect.h or 0))
    elseif side == "left" then
        return rect.x
    else
        return screen.w - (rect.x + (rect.w or 0))
    end
end

--- Place against a rect (a point is a 0×0 rect) on the `prefer` side, or
-- on the side with the most room when nil. Flips if the side overflows.
function Anchor.atRect(rect, prefer, size, screen, margin, gap)
    gap = gap or 0
    rect = { x = rect.x, y = rect.y, w = rect.w or 0, h = rect.h or 0 }
    local side = prefer
    if not OPPOSITE[side] then
        local best, best_score
        for _, s in ipairs({ "below", "above", "right", "left" }) do
            local need = (s == "above" or s == "below") and size.h or size.w
            local score = room(s, rect, screen) - need - gap
            if best_score == nil or score > best_score then
                best, best_score = s, score
            end
        end
        side = best
    end
    local r = sideRect(side, rect, size.w, size.h, gap)
    if not fits(r, screen, margin) then
        local flipped = sideRect(OPPOSITE[side], rect, size.w, size.h, gap)
        if fits(flipped, screen, margin) then r = flipped end
    end
    return Anchor.clampRect(r, screen, margin)
end

--[[--
args:
    size, screen, margin
    position     menu option; "gesture" without a point opens centred
    point        gesture position { x, y }
    rect, prefer API anchor, which overrides `position`
    offset       distance from a gesture point
    gap          distance from an anchor rect
Returns rect, "anchor" | "gesture" | "fixed"
]]
function Anchor.placeRoot(args)
    local size, screen, margin = args.size, args.screen, args.margin or 0
    if args.rect then return Anchor.atRect(args.rect, args.prefer, size, screen, margin, args.gap or 0), "anchor" end
    if args.position == "gesture" and args.point then
        return Anchor.atPoint(args.point, size, screen, margin, args.offset), "gesture"
    end
    return Anchor.fixed(args.position, size, screen, margin), "fixed"
end

--- Flyouts cascade away from the screen edge nearest the root panel.
function Anchor.cascadeDirection(root, screen)
    local centre = root.x + root.w / 2
    return centre <= screen.w / 2 and "right" or "left"
end

--[[--
Horizontal placement of a flyout: beside its parent if it fits, else as a
stacked card over it.

args:
    parent      rect of the parent panel
    width       natural width of the flyout
    screen, margin
    direction   chain direction ("right" | "left")
    overlap     how far side-by-side flyouts overlap their parent (a border)
    avoid       rects of the ancestors above the parent (optional)
    indent      stacked-card indent
    min_w       minimum panel width

Returns x, w, mode ("side" | "stacked"), side ("right" | "left")
]]
function Anchor.flyoutX(args)
    local p, screen, margin = args.parent, args.screen, args.margin or 0
    local w = min(args.width, screen.w - 2 * margin)
    local overlap = args.overlap or 0
    -- A side position must not cover an ancestor beyond the parent: on narrow
    -- screens, flipping sides per level would bury the grandparent.
    local function clear(x)
        for _, a in ipairs(args.avoid or {}) do
            if x < a.x + a.w - overlap and x + w > a.x + overlap then return false end
        end
        return true
    end
    local function sideX(dir)
        local x
        if dir == "right" then
            x = p.x + p.w - overlap
            if x + w > screen.w - margin then return nil end
        else
            x = p.x - w + overlap
            if x < margin then return nil end
        end
        if clear(x) then return x end
    end
    local dir = args.direction == "left" and "left" or "right"
    local other = dir == "right" and "left" or "right"
    local x = sideX(dir)
    if x then return x, w, "side", dir end
    x = sideX(other)
    if x then return x, w, "side", other end

    -- Stacked cards: overlap the parent, offset inward from its leading edge.
    local indent = args.indent or 0
    local min_w = min(args.min_w or 0, screen.w - 2 * margin)
    if dir == "right" then
        -- The indent stops growing once it would leave less than min_w.
        x = min(p.x + indent, screen.w - margin - min_w)
        x = max(x, margin)
        w = min(w, screen.w - margin - x)
        return x, w, "stacked", dir
    else
        local right = max(p.x + p.w - indent, margin + min_w)
        right = min(right, screen.w - margin)
        w = min(w, right - margin)
        return right - w, w, "stacked", dir
    end
end

--- Align the top with `top` (the opening row), shifting up until the bottom
-- fits and capping the height to the screen.
-- Returns y, h
function Anchor.flyoutY(top, h, screen, margin)
    margin = margin or 0
    h = min(h, screen.h - 2 * margin)
    local y = top
    if y + h > screen.h - margin then y = screen.h - margin - h end
    if y < margin then y = margin end
    return y, h
end

return Anchor
