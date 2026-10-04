local H = require("harness").setup()
local test, eq, tapButton = H.test, H.eq, H.tapButton
local IconPicker = require("minimenu/ui/pickers/icons")
local Util = require("minimenu/util")

H.fm()

local function firstGlyph()
    return H.top().buttontable.buttons_layout[1][1]
end

local picked = "unset"
local function pick()
    picked = "unset"
    IconPicker.pick(function(icon)
        picked = icon
    end)
    H.drain()
end

test("opens on a category, pages through it, and picks a glyph", function()
    pick()
    assert(H.top().title:find("^Reading"), H.top().title)
    H.shot("icons_reading")
    local before = firstGlyph().text
    tapButton("\u{25B7}")
    assert(H.top().title:find("2 /"), H.top().title)
    assert(firstGlyph().text ~= before, "page turned")
    H.shot("icons_reading_p2")
    local b = firstGlyph()
    H.tap(b.dimen.x + 5, b.dimen.y + 5)
    eq(b.text, picked)
    assert(Util.isGlyph(picked), "glyph")
end)

local function onLastPage()
    local page, pages = H.top().title:match("(%d+) / (%d+)$")
    return page == pages
end

-- Heights of the first and last page of every view.
local function heights()
    local out = {}
    local titles = {}
    for _, cat in ipairs(require("minimenu/icons/index").CATEGORIES) do
        table.insert(titles, cat.title)
    end
    table.insert(titles, "Image icons")
    for _, title in ipairs(titles) do
        pick()
        tapButton("Categories")
        tapButton(title)
        table.insert(out, H.top().dimen.h)
        for _ = 1, 50 do
            if onLastPage() then break end
            tapButton("\u{25B7}")
        end
        assert(onLastPage(), H.top().title)
        table.insert(out, H.top().dimen.h)
        local d = H.top().dimen
        assert(d.y >= 0 and d.y + d.h <= H.Screen:getHeight(), title .. " fits")
        tapButton("Default")
    end
    return out
end

local function allSame(list, msg)
    for _, h in ipairs(list) do
        eq(list[1], h, msg)
    end
end

test("every view and page is the same height, at any text size", function()
    for _, size in ipairs({ false, 36 }) do
        H.Store.setSetting("font_size", size or nil)
        allSame(heights(), "portrait, size " .. tostring(size))
        pick()
        H.shot("icons_portrait_" .. tostring(size))
        tapButton("Default")
        H.Screen:setRotationMode(H.Screen.DEVICE_ROTATED_CLOCKWISE)
        allSame(heights(), "landscape, size " .. tostring(size))
        pick()
        H.shot("icons_landscape_" .. tostring(size))
        tapButton("Default")
        H.Screen:setRotationMode(H.Screen.DEVICE_ROTATED_UPRIGHT)
    end
    H.Store.setSetting("font_size", nil)
end)

test("image icons show KOReader's own set", function()
    pick()
    tapButton("Categories")
    tapButton("Image icons")
    assert(H.top().title:find("^Image icons"), H.top().title)
    assert(firstGlyph().icon, "image button")
    H.shot("icons_images")
    local b = firstGlyph()
    H.tap(b.dimen.x + 5, b.dimen.y + 5)
    assert(Util.iconName(picked), tostring(picked))
end)

test("long-press shows the glyph's name", function()
    pick()
    tapButton("Categories")
    tapButton(require("minimenu/icons/index").CATEGORIES[1].title)
    local b = firstGlyph()
    local name
    for _, e in ipairs(require("minimenu/icons/index").all()) do
        if e.icon == b.text then name = e.name end
    end
    local shown
    local show = H.UIManager.show
    H.UIManager.show = function(um, w, ...)
        if w.text == name then shown = true end
        return show(um, w, ...)
    end
    H.hold(b.dimen.x + 5, b.dimen.y + 5)
    H.UIManager.show = show
    assert(shown, "name notification")
    tapButton("Default")
end)

H.finish()
