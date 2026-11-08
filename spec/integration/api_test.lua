local H = require("harness").setup()
local Store, test, eq = H.Store, H.test, H.eq

local function act(name)
    return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } }
end

local a = Store.createMenu("Alpha")
Store.editItems(a.id, function(items)
    table.insert(items, act("history"))
    table.insert(items, act("favorites"))
    return true
end)
local b = Store.createMenu("Beta")
Store.editItems(b.id, function(items)
    table.insert(items, act("collections"))
    return true
end)

local fm = H.fm()

-- What another plugin would do:
local MiniMenu = require("minimenu/api")

test("list and exists", function()
    local l = MiniMenu.list()
    eq(a.id, l[1].id)
    eq("Alpha", l[1].title)
    eq(true, MiniMenu.exists(b.id))
    eq(false, MiniMenu.exists("m999"))
end)

test("open with an anchor rect and a preferred side", function()
    local anchor = H.Geom:new { x = 200, y = 700, w = 100, h = 40 }
    local closed = false
    MiniMenu.open(a.id, {
        anchor = anchor,
        prefer = "above",
        on_close = function()
            closed = true
        end,
    })
    H.drain()
    local r = H.popup().chain[1].panel:rect()
    assert(r.y + r.h <= 700, "above the anchor")
    eq(200, r.x)
    eq(true, MiniMenu.isOpen(a.id))
    eq(true, MiniMenu.isOpen())
    eq(false, MiniMenu.isOpen(b.id))
    MiniMenu.close()
    H.drain()
    eq(true, closed, "on_close called")
    eq(false, MiniMenu.isOpen())
end)

test("toggle opens then closes; open of another menu replaces", function()
    MiniMenu.toggle(a.id)
    H.drain()
    eq(true, MiniMenu.isOpen(a.id))
    MiniMenu.open(b.id)
    H.drain()
    eq(true, MiniMenu.isOpen(b.id))
    eq(false, MiniMenu.isOpen(a.id))
    -- exactly one popup on the stack
    local n = 0
    for _, w in ipairs(H.UIManager._window_stack) do
        if w.widget.name == "MiniMenuPopup" then n = n + 1 end
    end
    eq(1, n)
    MiniMenu.toggle(b.id)
    H.drain()
    eq(false, MiniMenu.isOpen())
end)

test("missing menu: open returns false", function()
    eq(false, MiniMenu.open("m999"))
    H.drain()
    eq(false, MiniMenu.isOpen())
end)

test("broadcast event form opens the menu, idempotently", function()
    H.UIManager:broadcastEvent(H.Event:new("MiniMenuOpen", a.id))
    H.drain()
    local p = assert(H.popup())
    eq(true, MiniMenu.isOpen(a.id))
    H.UIManager:broadcastEvent(H.Event:new("MiniMenuOpen", a.id))
    H.drain()
    eq(p, H.popup(), "same popup")
end)

test("Dispatcher event reaches us through a forwarding full-screen widget", function()
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Forwarder = InputContainer:extend { covers_fullscreen = true }
    function Forwarder:handleEvent(ev)
        if InputContainer.handleEvent(self, ev) then return true end
        return fm:handleEvent(ev)
    end
    local f = Forwarder:new { dimen = H.Screen:getSize() }
    H.UIManager:show(f)
    H.drain()
    require("dispatcher"):execute({ ["minimenu_open_" .. b.id] = true })
    H.drain()
    eq(true, MiniMenu.isOpen(b.id))
    MiniMenu.close()
    H.UIManager:close(f)
    H.drain()
end)

test("registerKind: stored items of a new kind appear once registered", function()
    local c = Store.createMenu("Gamma")
    Store.editItems(c.id, function(items)
        table.insert(items, act("history"))
        table.insert(items, { id = Store.issueItemId(), kind = "clock_panel", data = { fmt = "%H:%M" } })
        return true
    end)
    -- survives a reload while the kind is missing
    Store.load()
    MiniMenu.open(c.id)
    H.drain()
    eq({ "History" }, H.rowLabels(1))
    MiniMenu.close()
    H.drain()
    eq(
        true,
        MiniMenu.registerKind({
            name = "clock_panel",
            title = "Clock",
            resolve = function(item)
                return { label = "Clock " .. item.data.fmt, available = true, run = function() end }
            end,
        })
    )
    MiniMenu.open(c.id)
    H.drain()
    eq({ "History", "Clock %H:%M" }, H.rowLabels(1))
end)

test("pickMenu shows MiniMenu's chooser and returns the id", function()
    local got
    MiniMenu.pickMenu(function(id)
        got = id
    end)
    H.drain()
    local dlg = H.UIManager._window_stack[#H.UIManager._window_stack].widget
    dlg.buttons[2][1].callback()
    H.drain()
    eq(b.id, got)
end)

test("gesture binding: works after rename, removed on delete", function()
    local g = fm.gestures
    assert(g, "gestures plugin loaded")
    local name = "minimenu_open_" .. a.id
    g.data.gesture_fm.tap_left_bottom_corner = { [name] = true }
    g.gestures = g.data.gesture_fm
    Store.renameMenu(a.id, "Alpha renamed")
    g:gestureAction("tap_left_bottom_corner", H.gesture("tap", 10, 790))
    H.drain()
    eq(true, MiniMenu.isOpen(a.id), "binding still opens the renamed menu")
    local r = H.popup().chain[1].panel:rect()
    assert(r.y + r.h <= 790 and r.x >= 10, "opened at the corner, away from the finger")
    eq("Alpha renamed", H.popup().chain[1].panel.title)
    MiniMenu.close()
    H.drain()
    Store.deleteMenu(a.id)
    H.drain()
    eq(nil, g.data.gesture_fm.tap_left_bottom_corner, "binding removed from the Gesture manager")
end)

test("a stale binding to a deleted menu shows a notice, not another menu", function()
    Store.createMenu("Delta")
    local Notification = require("ui/widget/notification")
    local notify = Notification.notify
    local notice
    Notification.notify = function(_, text)
        notice = text
    end
    local opened = MiniMenu.open(a.id)
    Notification.notify = notify
    eq(false, opened)
    eq("Menu no longer exists", notice)
    eq(false, MiniMenu.isOpen())
end)

H.finish()
