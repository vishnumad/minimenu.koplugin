-- Repaint behaviour, checked without the forced full repaint that H.shot
-- does: refresh modes and regions, no ghost pixels, and night mode toggled
-- from inside the popup.
local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq

local function act(name) return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } } end
local function folder(label, items) return { id = Store.issueItemId(), kind = "folder", label = label, data = { items = items } } end

local m = Store.createMenu("Repaint")
Store.editItems(m.id, function(items)
    table.insert(items, { id = Store.issueItemId(), kind = "menu_item",
        data = { path = { { id = "setting" }, { id = "night_mode" } }, captured_in = "filemanager" } })
    table.insert(items, folder("A", { act("history"), folder("B", { act("history"), folder("C", { act("favorites") }) }) }))
    for _ = 1, 25 do table.insert(items, act("history")) end
    return true
end)

H.fm()
local Screen, UIManager = H.Screen, H.UIManager

local function pixel(x, y) return Screen.bb:getPixel(x, y):getColor8().a end

local function forceFull()
    UIManager:setDirty("all", "full")
    H.drain(1)
end

test("no full-screen or flashing refreshes; regions stay local", function()
    local refreshes = {}
    local orig = UIManager._refresh
    UIManager._refresh = function(self, mode, region, dither)
        -- A nil mode is dropped by _refresh itself (UIManager:close marks the
        -- widgets below dirty without a mode); only real refreshes count.
        if mode then
            table.insert(refreshes, { mode = mode, region = region, where = region == nil and debug.traceback("", 2) or nil })
        end
        return orig(self, mode, region, dither)
    end
    local ok, err = pcall(function()
        API.open(m.id, { gesture = H.gesture("tap", 40, 60) })
        H.drain()
        local p = assert(H.popup())
        H.tap(H.rowCenter(1, H.rowIndex(1, "A")))
        H.tap(H.rowCenter(2, H.rowIndex(2, "B")))
        H.tap(H.rowCenter(3, H.rowIndex(3, "C")))
        eq(4, #p.chain)
        p:onBack()
        H.drain()
        eq(3, #p.chain)
        local panel = p.chain[1].panel
        assert(panel:pageCount() > 1, "root pages")
        p:setPage(1, 2)
        H.drain()
        H.tap(590, 790) -- outside: close
        assert(p.closed)
    end)
    UIManager._refresh = orig
    assert(ok, err)
    assert(#refreshes > 0, "refreshes recorded")
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    for i, r in ipairs(refreshes) do
        assert(r.mode ~= "full" and r.mode ~= "flashui" and r.mode ~= "flashpartial",
            ("refresh %d is %s"):format(i, tostring(r.mode)))
        assert(r.region, ("refresh %d (%s) has no region (full screen)%s"):format(i, tostring(r.mode), r.where or ""))
        assert(not (r.region.x == 0 and r.region.y == 0 and r.region.w >= sw and r.region.h >= sh),
            ("refresh %d covers the whole screen"):format(i))
    end
end)

test("closing a flyout leaves no ghost pixels", function()
    API.open(m.id, { gesture = H.gesture("tap", 40, 60) })
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "A")))
    H.tap(H.rowCenter(2, H.rowIndex(2, "B")))
    local flyout = p.chain[3] and p.chain[3].panel or p.chain[2].panel
    local r = flyout:rect()
    -- a point inside the deepest flyout but outside every remaining panel
    local px, py
    for x = r.x + r.w - 3, r.x + 3, -4 do
        for y = r.y + r.h - 3, r.y + 3, -4 do
            local covered = false
            for k = 1, #p.chain - 1 do
                local q = p.chain[k].panel:dirtyRect()
                if x >= q.x and x < q.x + q.w and y >= q.y and y < q.y + q.h then covered = true end
            end
            if not covered then px, py = x, y break end
        end
        if px then break end
    end
    assert(px, "found a sample point")
    p:onBack() -- close the deepest flyout, normal repaint only
    H.drain()
    local after_close = pixel(px, py)
    forceFull()
    eq(pixel(px, py), after_close, ("pixel at %d,%d"):format(px, py))
end)

test("night mode toggled from inside the popup repaints consistently", function()
    G_reader_settings:makeFalse("night_mode")
    if Screen.night_mode then Screen:toggleNightMode() end
    forceFull()
    API.open(m.id, { gesture = H.gesture("tap", 40, 60) })
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "Night mode")))
    H.drain()
    eq(true, Screen.night_mode == true, "night mode on")
    local panel = p.chain[1].panel
    local tr = panel.title_rect
    local popup_bg = pixel(tr.x + tr.w - 6, tr.y + 4)
    local fm_bg = pixel(Screen:getWidth() - 20, Screen:getHeight() - 120)
    eq(fm_bg, popup_bg, "popup and file browser backgrounds after toggle")
    forceFull()
    eq(pixel(tr.x + tr.w - 6, tr.y + 4), popup_bg, "popup unchanged by a full repaint")
    eq(pixel(Screen:getWidth() - 20, Screen:getHeight() - 120), fm_bg, "file browser unchanged by a full repaint")
    H.tap(H.rowCenter(1, H.rowIndex(1, "Night mode")))
    H.drain()
    eq(false, Screen.night_mode == true)
end)

H.finish()
