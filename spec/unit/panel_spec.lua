local STUBS = { "ffi/blitbuffer", "ui/widget/textwidget", "ui/widget/iconwidget" }

local cfg = {
    border = 2,
    pad = 5,
    row_h = 40,
    sep_h = 10,
    header_h = 30,
    pager_h = 40,
    icon_col = 30,
    side_col = 40,
    gap = 8,
}

describe("panel", function()
    local Panel, created

    before_each(function()
        created = 0
        package.loaded["ffi/blitbuffer"] = { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_DARK_GRAY = 2 }
        package.loaded["ui/widget/textwidget"] = {
            new = function(_, o)
                created = created + 1
                function o.getSize()
                    return { w = #o.text * 10, h = 10 }
                end
                function o.free() end
                return o
            end,
        }
        package.loaded["ui/widget/iconwidget"] = {
            new = function(_, o)
                return o
            end,
        }
        package.loaded["minimenu/ui/row"] = nil
        package.loaded["minimenu/ui/panel"] = nil
        Panel = require("minimenu/ui/panel")
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            package.loaded[name] = nil
        end
        package.loaded["minimenu/ui/row"] = nil
        package.loaded["minimenu/ui/panel"] = nil
    end)

    local function rows(n)
        local t = {}
        for i = 1, n do
            t[i] = { label = ("row %d"):format(i) }
        end
        return t
    end

    it("measures text only once across measure calls", function()
        local list = rows(4)
        list[3] = { separator = true }
        local panel = Panel.new { rows = list, cfg = cfg, title = "Title" }
        local w1 = panel:measure(1000)
        assert.equal(4, created)
        local w2 = panel:measure(500)
        local w3 = panel:measure(120)
        assert.equal(4, created)
        assert.equal(w1, w2)
        assert.equal(w1, w3)
    end)

    it("is as wide as the longest label or title, within bounds", function()
        local list = { { label = "abc", icon = "x" }, { label = "abcdef", checked = true } }
        local chrome = 2 * cfg.pad + 2 * cfg.border
        local panel = Panel.new { rows = list, cfg = cfg }
        assert.equal(60 + 2 * cfg.icon_col + chrome, (panel:measure(1000)))

        panel = Panel.new { rows = list, cfg = cfg, title = "a much longer title" }
        assert.equal(190 + chrome, (panel:measure(1000)))

        panel = Panel.new { rows = list, cfg = cfg, min_w = 500 }
        assert.equal(500, (panel:measure(1000)))
        panel = Panel.new { rows = list, cfg = cfg, max_w = 50 }
        assert.equal(50, (panel:measure(1000)))
    end)

    it("widens for the subtitle, within bounds", function()
        local title_row = { label = "abc" }
        local subtitle = "a long subtitle line"
        local chrome = 2 * cfg.pad + 2 * cfg.border
        local panel = Panel.new { rows = rows(1), cfg = cfg, title_row = title_row, subtitle = subtitle }
        assert.equal(#subtitle * 10 + chrome, (panel:measure(1000)))
        panel = Panel.new { rows = rows(1), cfg = cfg, title_row = title_row, subtitle = subtitle, max_w = 100 }
        assert.equal(100, (panel:measure(1000)))
    end)

    it("still paginates for each height", function()
        local panel = Panel.new { rows = rows(10), cfg = cfg }
        local _, tall = panel:measure(1000)
        assert.equal(1, panel:pageCount())
        local _, short = panel:measure(200)
        assert.is_true(panel:pageCount() > 1)
        assert.is_true(short < tall)
    end)

    it("hits the second action only in its column, on rows that have one", function()
        local panel = Panel.new { rows = { { label = "a", secondary = { icon = "g" } }, { label = "b" } }, cfg = cfg }
        local w, h = panel:measure(1000)
        assert.equal(10 + cfg.side_col + 2 * cfg.pad + 2 * cfg.border, w)
        panel:layout(0, 0, w, h)
        local r1, r2 = panel:rowRect(1), panel:rowRect(2)
        local edge = r1.x + r1.w - cfg.side_col
        assert.same({ "secondary", 1 }, { panel:hit(edge, r1.y + 1) })
        assert.same({ "row", 1 }, { panel:hit(edge - 1, r1.y + 1) })
        assert.same({ "row", 2 }, { panel:hit(edge, r2.y + 1) })
    end)

    it("makes room for a second action only in rows that have one", function()
        local panel = Panel.new { rows = { { label = "a", secondary = { icon = "g" } }, { label = "b" } }, cfg = cfg }
        panel:layout(0, 0, panel:measure(1000))
        assert.equal(panel.views[1].label.max_width + cfg.side_col, panel.views[2].label.max_width)
    end)

    it("hits each cell of a cells row", function()
        local cells = { { label = "a" }, { label = "b" }, { label = "c" } }
        local panel = Panel.new { rows = { { cells = cells } }, cfg = cfg }
        local _, h = panel:measure(1000)
        panel:layout(0, 0, 300 + 2 * cfg.border, h)
        local r = panel:rowRect(1)
        assert.same({ "cell", 1, 1 }, { panel:hit(r.x, r.y + 1) })
        assert.same({ "cell", 1, 2 }, { panel:hit(r.x + 150, r.y + 1) })
        assert.same({ "cell", 1, 3 }, { panel:hit(r.x + r.w - 1, r.y + 1) })
    end)

    it("hits the close button at the right end of a closable title line", function()
        local panel = Panel.new { rows = rows(1), cfg = cfg, title = "Title", closable = true }
        panel:layout(0, 0, panel:measure(1000))
        local t = panel.title_rect
        local right = t.x + t.w - 1
        assert.equal("close", panel:hit(right, t.y))
        assert.equal("close", panel:hit(right - cfg.side_col + 1, t.y + t.h - 1))
        assert.equal("title", panel:hit(right - cfg.side_col, t.y))
    end)

    it("does not hit a header as a row", function()
        local panel = Panel.new { rows = { { label = "Section", section = true }, { label = "a" } }, cfg = cfg }
        panel:layout(0, 0, panel:measure(1000))
        local r = panel:rowRect(1)
        assert.equal(cfg.header_h, r.h)
        assert.equal("frame", panel:hit(r.x + 1, r.y + 1))
    end)

    it("skips headers and separators when moving focus", function()
        local list = { { label = "Section", section = true }, { label = "a" }, { separator = true }, { label = "b" } }
        local panel = Panel.new { rows = list, cfg = cfg }
        assert.equal(2, panel:nextActionable(0, 1))
        assert.equal(4, panel:nextActionable(2, 1))
        assert.equal(2, panel:nextActionable(4, 1))
        assert.equal(4, panel:nextActionable(2, -1))
    end)

    it("ignores the header for width", function()
        local panel = Panel.new { rows = rows(2), cfg = cfg }
        local w = panel:measure(1000)
        panel.header = "a very long breadcrumb that would be much wider than any row"
        assert.equal(w, (panel:measure(1000)))
    end)
end)
