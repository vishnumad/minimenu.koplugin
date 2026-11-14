local H = require("harness").setup()
local Store, test, eq = H.Store, H.test, H.eq
local Sheet = require("minimenu/ui/sheet")

H.fm()

test("a tap outside closes the sheet and cancels a choice", function()
    local canceled = false
    Sheet.choose {
        title = "Pick",
        choices = { { text = "A", value = 1 } },
        on_choice = function()
            error("chose")
        end,
        on_cancel = function()
            canceled = true
        end,
    }
    H.drain()
    H.tap(1, 1)
    eq(nil, H.sheet())
    eq(true, canceled)
end)

test("the close button closes the sheet", function()
    Sheet.show {
        build = function()
            return { title = "Closable", rows = { { label = "Row" } } }
        end,
    }
    H.drain()
    local r = H.sheet().panel.close_rect
    H.tap(r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2))
    eq(nil, H.sheet())
end)

test("a watched Store event rebuilds; a nil build closes", function()
    local m = Store.createMenu("Before")
    Sheet.show {
        build = function()
            local menu = Store.menu(m.id)
            return menu and { title = menu.title, rows = { { label = "Row" } } }
        end,
        watch = true,
    }
    H.drain()
    Store.renameMenu(m.id, "After")
    H.drain()
    eq("After", H.sheet().panel.title)
    Store.deleteMenu(m.id)
    H.drain()
    eq(nil, H.sheet())
end)

test("Up, Down and Press run the focused row; Back closes", function()
    local ran
    local function row(label)
        return {
            label = label,
            run = function()
                ran = label
            end,
        }
    end
    Sheet.show {
        build = function()
            return { title = "Keys", rows = { row("One"), { label = "Section", section = true }, row("Two") } }
        end,
    }
    H.drain()
    H.key("Down")
    H.key("Down")
    H.key("Down")
    H.key("Up")
    H.key("Press")
    eq("Two", ran)
    assert(H.sheet(), "a row does not close the sheet")
    H.key("Back")
    eq(nil, H.sheet())
end)

test("a tapped cell shows pressed before it runs, square away from the panel's corners", function()
    local ran = false
    local function cell(label)
        return {
            label = label,
            run = function()
                ran = true
            end,
        }
    end
    Sheet.show {
        build = function()
            return { title = "Press", rows = { { label = "Row" }, { cells = { cell("A"), cell("B") } } } }
        end,
    }
    H.drain()
    local r = H.sheet().panel:cellRect(2, 1)
    local function pixel(x, y)
        return H.Screen.bb:getPixel(x, y):getColor8().a
    end
    -- The cell's bottom right corner is inside the panel, so it inverts with the cell.
    local x, y = r.x + r.w - 1, r.y + r.h - 1
    local forceRePaint = H.UIManager.forceRePaint
    local seen
    H.UIManager.forceRePaint = function(...)
        forceRePaint(...)
        seen = seen or { ran = ran, corner = pixel(x, y) }
    end
    H.tap(r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2))
    H.UIManager.forceRePaint = forceRePaint
    eq({ ran = false, corner = 0 }, seen)
    eq(true, ran)
    eq(255, pixel(x, y), "released once the action ran")
end)

test("a rebuild keeps the left, top and width; only the bottom moves", function()
    local m = Store.createMenu("A long value that makes the sheet wider than its minimum")
    local count = 1
    Sheet.show {
        build = function()
            local menu = Store.menu(m.id)
            if not menu then return nil end
            local rows = { { label = "Name", value = menu.title } }
            for i = 2, count do
                table.insert(rows, { label = "Row " .. i })
            end
            return { title = "Stable", rows = rows }
        end,
        watch = true,
    }
    H.drain()
    local before = H.sheet().panel:rect()
    count = 4
    Store.renameMenu(m.id, "Short")
    H.drain()
    local after = H.sheet().panel:rect()
    eq({ before.x, before.y, before.w }, { after.x, after.y, after.w })
    assert(after.h > before.h, "rows added at the bottom")
    Store.deleteMenu(m.id)
end)

H.finish()
