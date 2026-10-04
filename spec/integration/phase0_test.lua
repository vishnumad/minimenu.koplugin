local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local Dispatcher = require("dispatcher")

local function act(name) return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } } end
local function sep() return { id = Store.issueItemId(), kind = "separator", data = {} } end
local function folder(label, items) return { id = Store.issueItemId(), kind = "folder", label = label, data = { items = items or {} } } end

local fm = H.fm()

test("plugin instance is loaded in the file manager", function()
    assert(fm.minimenu, "fm.minimenu missing")
end)

local tools = Store.createMenu("Reading tools")
Store.editItems(tools.id, function(items)
    table.insert(items, act("history"))
    table.insert(items, act("favorites"))
    table.insert(items, act("toc"))                -- reader only: hidden in FM
    table.insert(items, sep())
    table.insert(items, folder("Tools", { act("screenshot"), act("night_mode"),
        folder("Network", { act("toggle_wifi"), act("show_network_info") }) }))
    table.insert(items, act("full_refresh"))
    return true
end)

test("each menu is a Dispatcher action", function()
    local DispatchUtil = require("minimenu/dispatch")
    local list = DispatchUtil.settingsList()
    assert(list, "settingsList not reachable")
    local entry = list["minimenu_open_" .. tools.id]
    assert(entry, "action not registered")
    eq("MiniMenu: Reading tools", entry.title)
    eq(true, entry.general)
    eq("MiniMenu: Reading tools", Dispatcher:getNameFromItem("minimenu_open_" .. tools.id))
end)

test("Dispatcher opens the popup at the gesture with filtered rows", function()
    local ges = H.gesture("tap", 60, 80)
    Dispatcher:execute({ ["minimenu_open_" .. tools.id] = true }, { gesture = ges })
    H.drain()
    local p = assert(H.popup())
    assert(p and not p.closed, "popup not open")
    eq({ "History", "Favorites", "--", "Tools", "Full screen refresh" }, H.rowLabels(1))
    local r = p.chain[1].panel:rect()
    assert(r.x > 60 and r.y > 80, "panel should open away from the finger")
    H.shot("p0_root_fm")
end)

test("tapping a folder opens a flyout; tapping it again closes it", function()
    API.open(tools.id, { gesture = H.gesture("tap", 60, 80) })
    H.drain()
    local p = assert(H.popup())
    local fi = H.rowIndex(1, "Tools")
    H.tap(H.rowCenter(1, fi))
    eq(2, #p.chain)
    eq(fi, p.chain[1].open_index)
    eq({ "Screenshot", "Toggle night mode", "Network" }, H.rowLabels(2))
    H.tap(H.rowCenter(2, 3))
    eq(3, #p.chain)
    H.shot("p0_flyouts")
    -- tapping a row of the root closes deeper flyouts
    H.tap(H.rowCenter(1, fi))
    eq(1, #p.chain)
end)

test("open is idempotent and tap outside closes", function()
    API.open(tools.id)
    H.drain()
    local p = assert(H.popup())
    API.open(tools.id)
    eq(p, H.popup())
    H.tap(590, 790)
    assert(p.closed, "popup should close on outside tap")
    assert(not API.isOpen(), "no popup should be current")
end)

test("running a leaf closes the popup, then runs on nextTick", function()
    local ran = false
    local Kinds = require("minimenu/kinds/init")
    Kinds.register({ name = "probe", resolve = function() return { label = "Probe", run = function()
        assert(not API.isOpen(), "popup must be closed before running")
        ran = true
    end } end })
    local m = Store.createMenu("Probe menu")
    Store.editItems(m.id, function(items) table.insert(items, { id = Store.issueItemId(), kind = "probe", data = {} }) return true end)
    API.open(m.id)
    H.drain()
    H.tap(H.rowCenter(1, 1))
    assert(ran, "probe did not run")
    Store.deleteMenu(m.id)
end)

-- 8 levels of nested folders on a 600x800 screen.
local deep = Store.createMenu("Deep")
Store.editItems(deep.id, function(items)
    local list = items
    for level = 1, 8 do
        table.insert(list, act("history"))
        local f = folder("Level " .. level)
        table.insert(list, f)
        table.insert(list, act("favorites"))
        list = f.data.items
    end
    table.insert(list, act("screenshot"))
    return true
end)

for _, start in ipairs({ { 30, 60, "left" }, { 570, 60, "right" }, { 300, 400, "center" } }) do
    test(("8-level cascade opens and closes (start %s)"):format(start[3]), function()
        API.open(deep.id, { gesture = H.gesture("tap", start[1], start[2]) })
        H.drain()
        local p = assert(H.popup())
        for level = 1, 8 do
            local idx = H.rowIndex(level, "Level " .. level)
            assert(idx, "no folder row at level " .. level)
            H.tap(H.rowCenter(level, idx))
            eq(level + 1, #p.chain)
        end
        eq({ "Screenshot" }, H.rowLabels(9))
        local sw, sh = H.Screen:getWidth(), H.Screen:getHeight()
        for k, e in ipairs(p.chain) do
            local r = e.panel:rect()
            assert(r.x >= 0 and r.y >= 0 and r.x + r.w <= sw and r.y + r.h <= sh,
                ("panel %d off screen: %d,%d %dx%d"):format(k, r.x, r.y, r.w, r.h))
        end
        H.shot("p0_deep_" .. start[3])
        -- back closes the deepest flyout each time, then the popup
        for level = 8, 1, -1 do
            p:onBack()
            H.drain()
            eq(level, #p.chain)
        end
        p:onBack()
        H.drain()
        assert(p.closed)
    end)
end

test("stacked cards: ancestor strips stay tappable", function()
    API.open(deep.id, { gesture = H.gesture("tap", 300, 400) })
    H.drain()
    local p = assert(H.popup())
    for level = 1, 6 do H.tap(H.rowCenter(level, H.rowIndex(level, "Level " .. level))) end
    eq(7, #p.chain)
    -- find a level with a stacked card and tap its parent's visible strip
    local stacked
    for k = 2, #p.chain do if p.chain[k].mode == "stacked" then stacked = k break end end
    assert(stacked, "expected stacked cards on 600px")
    local parent = p.chain[stacked - 1].panel
    local child = p.chain[stacked].panel
    local strip_x = p.direction == "right" and (parent.x + 3) or (parent.x + parent.w - 4)
    local strip_y = child.y + child.h - 2
    if strip_y >= parent.y + parent.h then strip_y = parent.y + math.floor(parent.h / 2) end
    local k = p:hitTest(strip_x, strip_y)
    eq(stacked - 1, k, "strip hit")
    H.tap(strip_x, strip_y)
    eq(stacked - 1, #p.chain)
end)

test("renaming keeps the action name; deleting broadcasts removal", function()
    local m = Store.createMenu("Before")
    local name = "minimenu_open_" .. m.id
    local events = {}
    local orig = H.UIManager.broadcastEvent
    H.UIManager.broadcastEvent = function(self, ev)
        if ev.handler == "onDispatcherActionNameChanged" then table.insert(events, ev.args[1]) end
        return orig(self, ev)
    end
    Store.renameMenu(m.id, "After")
    eq("MiniMenu: After", Dispatcher:getNameFromItem(name))
    Store.deleteMenu(m.id)
    H.UIManager.broadcastEvent = orig
    eq(1, #events)
    eq(name, events[1].old_name)
    eq(nil, events[1].new_name)
    eq("Unknown item", Dispatcher:getNameFromItem(name))
end)

H.finish()
