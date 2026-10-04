local Anchor = require("minimenu/ui/anchor")

local function inside(r, screen, margin)
    return r.x >= margin and r.y >= margin and r.x + r.w <= screen.w - margin and r.y + r.h <= screen.h - margin
end

describe("anchor", function()
    local screen = { w = 600, h = 800 }
    local size = { w = 200, h = 300 }

    it("places fixed positions inside the margins", function()
        for _, pos in ipairs({ "center", "top_left", "top_right", "bottom_left", "bottom_right", "top", "bottom" }) do
            local r = Anchor.fixed(pos, size, screen, 10)
            assert(inside(r, screen, 10), pos)
        end
        assert.same({ x = 200, y = 250, w = 200, h = 300 }, Anchor.fixed("center", size, screen, 10))
        assert.same({ x = 10, y = 10, w = 200, h = 300 }, Anchor.fixed("top_left", size, screen, 10))
        assert.same({ x = 390, y = 490, w = 200, h = 300 }, Anchor.fixed("bottom_right", size, screen, 10))
    end)

    it("opens away from the finger at a gesture point", function()
        local tl = Anchor.atPoint({ x = 20, y = 20 }, size, screen, 10, 8)
        assert.same({ x = 28, y = 28, w = 200, h = 300 }, tl)
        local br = Anchor.atPoint({ x = 590, y = 790 }, size, screen, 10, 8)
        assert.same({ x = 382, y = 482, w = 200, h = 300 }, br)
        -- never under the finger
        for _, p in ipairs({ { x = 300, y = 400 }, { x = 100, y = 700 }, { x = 500, y = 50 } }) do
            local r = Anchor.atPoint(p, size, screen, 10, 8)
            local covers = p.x >= r.x and p.x <= r.x + r.w and p.y >= r.y and p.y <= r.y + r.h
            assert.is_false(covers)
            assert.is_true(inside(r, screen, 10))
        end
    end)

    it("opens centred without a gesture, and ignores the point for fixed positions", function()
        local r, how = Anchor.placeRoot { size = size, screen = screen, margin = 10, position = "gesture" }
        assert.equal("fixed", how)
        assert.same({ x = 200, y = 250, w = 200, h = 300 }, r)
        r, how = Anchor.placeRoot {
            size = size,
            screen = screen,
            margin = 10,
            position = "bottom",
            point = { x = 1, y = 1 },
        }
        assert.equal("fixed", how)
        assert.equal(490, r.y)
    end)

    it("places against an API anchor rect, flipping when needed", function()
        local button = { x = 50, y = 700, w = 80, h = 40 }
        local r = Anchor.atRect(button, "below", size, screen, 10, 4)
        assert.equal(700 - 4 - 300, r.y) -- flipped above
        r = Anchor.atRect(button, "above", size, screen, 10, 4)
        assert.equal(396, r.y)
        assert.equal(50, r.x)
        -- no preference: most room (above here)
        r = Anchor.atRect(button, nil, size, screen, 10, 4)
        assert.is_true(r.y + r.h <= 700)
    end)

    it("chooses a cascade direction away from the nearest edge", function()
        assert.equal("right", Anchor.cascadeDirection({ x = 10, y = 0, w = 200, h = 1 }, screen))
        assert.equal("left", Anchor.cascadeDirection({ x = 390, y = 0, w = 200, h = 1 }, screen))
    end)

    it("puts a flyout side by side, flips, then stacks", function()
        local parent = { x = 10, y = 100, w = 200, h = 300 }
        local x, w, mode, side = Anchor.flyoutX {
            parent = parent,
            width = 200,
            screen = screen,
            margin = 10,
            direction = "right",
            overlap = 2,
            indent = 30,
            min_w = 150,
        }
        assert.same({ 208, 200, "side", "right" }, { x, w, mode, side })
        parent = { x = 300, y = 100, w = 200, h = 300 }
        x, w, mode, side = Anchor.flyoutX {
            parent = parent,
            width = 200,
            screen = screen,
            margin = 10,
            direction = "right",
            overlap = 2,
            indent = 30,
            min_w = 150,
        }
        assert.same({ 102, 200, "side", "left" }, { x, w, mode, side })
        parent = { x = 150, y = 100, w = 300, h = 300 }
        x, w, mode = Anchor.flyoutX {
            parent = parent,
            width = 300,
            screen = screen,
            margin = 10,
            direction = "right",
            overlap = 2,
            indent = 30,
            min_w = 150,
        }
        assert.same({ 180, 300, "stacked" }, { x, w, mode })
    end)

    it("never flips onto an ancestor: stacks instead", function()
        -- root at 200..380; level 1 went left (20..200); level 2 can't go left,
        -- and going right would bury the root.
        local root = { x = 200, y = 100, w = 180, h = 300 }
        local parent = { x = 22, y = 150, w = 180, h = 300 }
        local x, w, mode = Anchor.flyoutX {
            parent = parent,
            width = 180,
            screen = screen,
            margin = 10,
            direction = "left",
            overlap = 2,
            indent = 30,
            min_w = 150,
            avoid = { root },
        }
        assert.equal("stacked", mode)
        -- without the ancestor it would have flipped right
        local _, _, mode2, side2 = Anchor.flyoutX {
            parent = parent,
            width = 180,
            screen = screen,
            margin = 10,
            direction = "left",
            overlap = 2,
            indent = 30,
            min_w = 150,
        }
        assert.same({ "side", "right" }, { mode2, side2 })
        assert.is_true(x + w <= parent.x + parent.w - 30 + 0.5 or w < 180)
    end)

    it("shifts a flyout up to fit and caps its height", function()
        local y, h = Anchor.flyoutY(700, 300, screen, 10)
        assert.same({ 490, 300 }, { y, h })
        y, h = Anchor.flyoutY(100, 2000, screen, 10)
        assert.same({ 10, 780 }, { y, h })
    end)

    -- An 8-level cascade of wide panels: every panel stays on screen and
    -- each ancestor keeps a visible strip of at least one indent.
    it("cascades 8 levels in either direction", function()
        for _, dir in ipairs({ "right", "left" }) do
            local margin = math.floor(screen.w * 0.02)
            local indent = math.floor(screen.w * 0.06)
            local min_w = math.floor(screen.w * 0.3)
            local width = math.floor(screen.w * 0.55)
            local row_h = math.floor(screen.h * 0.05)
            local root =
                Anchor.fixed(dir == "right" and "top_left" or "top_right", { w = width, h = row_h * 8 }, screen, margin)
            local chain = { root }
            local direction = Anchor.cascadeDirection(root, screen)
            assert.equal(dir, direction)
            for level = 1, 8 do
                local parent = chain[#chain]
                local row = { y = parent.y + row_h * 3 }
                local x, w, mode = Anchor.flyoutX {
                    parent = parent,
                    width = width,
                    screen = screen,
                    margin = margin,
                    direction = direction,
                    overlap = 2,
                    indent = indent,
                    min_w = min_w,
                }
                local y, h = Anchor.flyoutY(row.y, row_h * 8, screen, margin)
                local r = { x = x, y = y, w = w, h = h }
                assert(inside(r, screen, margin), "level " .. level)
                assert.is_true(r.w >= min_w)
                if mode == "stacked" then
                    local strip = direction == "right" and (r.x - parent.x) or ((parent.x + parent.w) - (r.x + r.w))
                    assert(strip >= indent, ("level %d strip %d"):format(level, strip))
                end
                table.insert(chain, r)
            end
        end
    end)

    it("stops growing the indent at the screen edge", function()
        local parent = { x = 400, y = 0, w = 190, h = 100 }
        -- too wide for either side
        local x, w, mode = Anchor.flyoutX {
            parent = parent,
            width = 400,
            screen = screen,
            margin = 10,
            direction = "right",
            overlap = 2,
            indent = 30,
            min_w = 190,
        }
        assert.equal("stacked", mode)
        assert.equal(400, x) -- exactly on top of its parent
        assert.equal(190, w)
    end)
end)
