local STUBS = { "ffi/blitbuffer", "ui/widget/textwidget", "ui/widget/iconwidget" }

local cfg = {
    border = 2,
    pad = 5,
    row_h = 40,
    sep_h = 10,
    title_h = 40,
    pager_h = 40,
    icon_col = 30,
    trail_col = 30,
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
        assert.equal(60 + cfg.icon_col + cfg.trail_col + chrome, (panel:measure(1000)))

        panel = Panel.new { rows = list, cfg = cfg, title = "a much longer title" }
        assert.equal(190 + chrome, (panel:measure(1000)))

        panel = Panel.new { rows = list, cfg = cfg, min_w = 500 }
        assert.equal(500, (panel:measure(1000)))
        panel = Panel.new { rows = list, cfg = cfg, max_w = 50 }
        assert.equal(50, (panel:measure(1000)))
    end)

    it("still paginates for each height", function()
        local panel = Panel.new { rows = rows(10), cfg = cfg }
        local _, tall = panel:measure(1000)
        assert.equal(1, panel:pageCount())
        local _, short = panel:measure(200)
        assert.is_true(panel:pageCount() > 1)
        assert.is_true(short < tall)
    end)

    it("ignores the header for width", function()
        local panel = Panel.new { rows = rows(2), cfg = cfg }
        local w = panel:measure(1000)
        panel.header = "a very long breadcrumb that would be much wider than any row"
        assert.equal(w, (panel:measure(1000)))
    end)
end)
