local H = require("harness").setup()
local Store, test, eq = H.Store, H.test, H.eq
local DispatchUtil = require("minimenu/dispatch")
local Actions = require("minimenu/actions")

H.firstInstall()
H.fm()

local function unknown(items)
    local out = {}
    require("minimenu/model").walk(items, function(item)
        if item.kind == "dispatcher" and not DispatchUtil.exists(next(item.data.action)) then
            table.insert(out, next(item.data.action))
        end
    end)
    return out
end

test("first install: one ready-made menu, bound to an action", function()
    local menus = Store.menus()
    eq(1, #menus)
    eq("MiniMenu Default", menus[1].title)
    eq({ show_title = false }, menus[1].options)
    assert(#menus[1].items > 0, "has items")
    eq({}, unknown(menus[1].items))
    assert(DispatchUtil.exists(Actions.name(menus[1].id)), "Dispatcher action registered")
    -- Saved straight away, so it isn't seeded again.
    assert(require("libs/libkoreader-lfs").attributes(H.settings_file, "mode") == "file", "written")
end)

test("default menu opens in the file browser without reader-only rows", function()
    local id = Store.menus()[1].id
    H.API.open(id)
    H.drain()
    local labels = H.rowLabels(1)
    for _, label in ipairs(labels) do
        assert(label ~= "Go to ..." and label ~= "Close book", "reader-only row shown: " .. label)
    end
    assert(H.rowIndex(1, "Night mode"), "Night mode row")
    H.shot("defaults_fm")
end)

test("default menu fits on one page in the reader", function()
    H.reader("juliet.epub")
    H.API.open(Store.menus()[1].id)
    H.drain()
    assert(H.rowIndex(1, "Go to ..."), "Go to folder")
    assert(H.rowIndex(1, "Close book"), "Close book row")
    H.shot("defaults_reader")
    eq(1, #H.popup().chain[1].panel.pages)
    H.API.close()
    H.closeReader()
end)

-- Vertical centre of the dark pixels in columns x0..x1 of rect r.
local function inkCenter(r, x0, x1)
    local bb = H.Screen.bb
    local top, bot
    for y = r.y, r.y + r.h - 1 do
        for x = x0, x1 do
            if bb:getPixel(x, y):getColor8().a < 128 then
                top = top or y
                bot = y
                break
            end
        end
    end
    assert(top, "no ink")
    return (top + bot) / 2
end

test("folder chevrons are vertically centred, at any text size", function()
    H.fm()
    for _, size in ipairs({ false, 36 }) do
        Store.setSetting("font_size", size or nil)
        H.API.open(Store.menus()[1].id)
        H.drain()
        H.shot("chevron_" .. tostring(size))
        local panel = H.popup().chain[1].panel
        local r = panel:rowRect(H.rowIndex(1, "Device"))
        local center = r.y + (r.h - 1) / 2
        local chevron = inkCenter(r, r.x + r.w - panel.cfg.trail_col - panel.cfg.pad, r.x + r.w - 1)
        assert(
            math.abs(chevron - center) <= 1,
            ("size %s: chevron at %.1f, row centre %.1f"):format(size, chevron, center)
        )
        H.tap(H.rowCenter(1, H.rowIndex(1, "Device")))
        local sub = H.popup().chain[2].panel
        local t = sub.title_rect
        -- Leave out the line under the title.
        local above_line = { x = t.x, y = t.y, w = t.w, h = t.h - 3 * sub.cfg.line }
        local back = inkCenter(above_line, t.x + sub.cfg.pad, t.x + sub.cfg.pad + sub.cfg.icon_size)
        H.shot("chevron_sub_" .. tostring(size))
        assert(math.abs(back - (t.y + (t.h - 1) / 2)) <= 1, ("size %s: back arrow off centre"):format(size))
        H.API.close()
        H.drain()
    end
    Store.setSetting("font_size", nil)
end)

test("deleting every menu does not bring the default back", function()
    Store.deleteMenu(Store.menus()[1].id)
    Store.setBackend(Store.fileBackend(H.settings_file))
    H.API.ensure()
    eq(0, #Store.menus())
end)

test("New menu… starts from the default items", function()
    local Dialogs = require("minimenu/ui/dialogs")
    local input = Dialogs.input
    ---@diagnostic disable-next-line: duplicate-set-field
    Dialogs.input = function(_args, callback)
        callback("  Mine ")
    end
    local created
    require("minimenu/ui/editor").newMenu(function(menu)
        created = menu
    end)
    Dialogs.input = input
    eq("Mine", created.title)
    local first_install = require("minimenu/defaults").items()
    eq(#first_install, #created.items)
    eq({}, unknown(created.items))
end)

H.finish()
