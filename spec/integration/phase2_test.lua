local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local model = require("minimenu/model")
local ItemDialog = require("minimenu/ui/item_dialog")

local function act(name)
    return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } }
end
local function folder(label, items)
    return { id = Store.issueItemId(), kind = "folder", label = label, data = { items = items or {} } }
end
local function top()
    return H.UIManager._window_stack[#H.UIManager._window_stack].widget
end

local inner = folder("Inner", { act("screenshot"), act("full_refresh") })
local tools = folder("Tools", { act("night_mode"), inner, act("toggle_wifi") })
local m = Store.createMenu("Edit me")
Store.editItems(m.id, function(items)
    table.insert(items, act("history"))
    table.insert(items, act("favorites"))
    table.insert(items, tools)
    table.insert(items, act("collections"))
    return true
end)

H.fm()

local function buttonTexts(dialog)
    local texts = {}
    for _, row in ipairs(dialog.buttons) do
        for _, b in ipairs(row) do
            table.insert(texts, b.text)
        end
    end
    return texts
end

local function press(dialog, id, hold)
    local b = assert(dialog:getButtonById(id), "button " .. id)
    local d = b.dimen
    if hold then
        H.hold(d.x + d.w / 2, d.y + d.h / 2)
    else
        H.tap(d.x + d.w / 2, d.y + d.h / 2)
    end
    H.drain()
end

test("long-press on a root row opens the item dialog", function()
    API.open(m.id)
    H.drain()
    H.hold(H.rowCenter(1, 1))
    assert(ItemDialog.current and top() == ItemDialog.current, "item dialog on top")
    assert(not H.popup().closed, "popup stays open underneath")
    eq({
        "Rename…",
        "Change icon…",
        "Show in: Reader and File browser",
        "Move…",
        "Add item after…",
        "Duplicate",
        "Delete",
    }, buttonTexts(ItemDialog.current))
    H.shot("p2_item_dialog")
    H.UIManager:close(ItemDialog.current)
    H.drain()
end)

test("Move… stays open while moving up and down", function()
    API.open(m.id)
    H.drain()
    local first = Store.menu(m.id).items[1]
    local label = H.rowLabels(1)[1]
    local mover = assert(ItemDialog.showMove(m.id, first.id))
    H.drain()
    eq(mover, top())
    assert(not mover:getButtonById("up").enabled, "Up disabled at the top")
    assert(not mover:getButtonById("out").enabled, "Out of folder disabled at top level")
    press(mover, "down")
    eq(mover, top(), "still open after Down")
    eq(first.id, Store.menu(m.id).items[2].id)
    assert(mover:getButtonById("up").enabled, "Up enabled once moved")
    assert(mover.title:find("2 of 4"), mover.title)
    eq(label, H.rowLabels(1)[2], "the popup underneath follows")
    H.shot("p2_move_dialog")
    press(mover, "down", true)
    local items = Store.menu(m.id).items
    eq(first.id, items[#items].id)
    assert(not mover:getButtonById("down").enabled, "Down disabled at the bottom")
    press(mover, "up", true)
    eq(first.id, Store.menu(m.id).items[1].id)
    assert(not H.popup().closed, "popup stays open underneath")
    press(mover, "done")
    assert(top() ~= mover, "Done closes")
    eq(nil, ItemDialog.mover)
end)

test("Move… closes when its item is deleted", function()
    local extra = act("history")
    Store.editItems(m.id, function(items)
        table.insert(items, extra)
        return true
    end)
    local mover = assert(ItemDialog.showMove(m.id, extra.id))
    H.drain()
    eq(mover, top())
    ItemDialog.delete(m.id, extra.id)
    H.drain()
    assert(top() ~= mover, "closed")
end)

test("Show in offers the three scopes and sets one", function()
    local first = Store.menu(m.id).items[1]
    ItemDialog.chooseScope(m.id, first.id)
    H.drain()
    local dlg = top()
    eq("Show in", dlg.title)
    dlg.buttons[2][1].callback()
    H.drain()
    eq("reader", Store.menu(m.id).items[1].scope)
    ItemDialog.chooseScope(m.id, first.id)
    H.drain()
    top().buttons[1][1].callback()
    H.drain()
    eq(nil, Store.menu(m.id).items[1].scope)
end)

test("editing from a flyout keeps the chain open and re-renders", function()
    API.open(m.id)
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "Tools")))
    H.tap(H.rowCenter(2, H.rowIndex(2, "Inner")))
    eq(3, #p.chain)
    -- long-press "Screenshot" in the deepest flyout, then delete it
    H.hold(H.rowCenter(3, 1))
    H.UIManager:close(ItemDialog.current)
    ItemDialog.delete(m.id, inner.data.items[1].id)
    H.drain()
    eq(3, #p.chain, "chain still open")
    eq({ "Full screen refresh" }, H.rowLabels(3))
    -- rename a row in level 2
    local t = model.find(Store.menu(m.id).items, tools.data.items[1].id)
    t.label = "Night!"
    Store.itemChanged(m.id)
    H.drain()
    eq("Night!", H.rowLabels(2)[1])
    eq(3, #p.chain)
end)

test("an edit that removes the opening row closes deeper flyouts", function()
    API.open(m.id)
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "Tools")))
    H.tap(H.rowCenter(2, H.rowIndex(2, "Inner")))
    eq(3, #p.chain)
    -- move Inner out of Tools: level 2 no longer contains it
    Store.editItems(m.id, function(items)
        return model.moveOut(items, inner.id)
    end)
    H.drain()
    eq(2, #p.chain)
    eq(nil, p.chain[2].open_index)
    -- and it now appears at the top level
    assert(H.rowIndex(1, "Inner"), "Inner moved to top level")
end)

test("long-press on the placeholder offers Add item", function()
    local empty = Store.createMenu("Empty")
    API.open(empty.id)
    H.drain()
    H.hold(H.rowCenter(1, 1))
    local dlg = top()
    assert(dlg.title == "Add item", "kind picker shown, got " .. tostring(dlg.title))
    H.UIManager:close(dlg)
    H.drain()
    Store.deleteMenu(empty.id)
end)

test("Move to… offers other folders, not the item's own subtree, and moves there", function()
    local MoveTo = require("minimenu/ui/pickers/move_to")
    local sub = folder("Sub")
    local outer = folder("Outer", { sub })
    local other = folder("Other")
    local mv = Store.createMenu("Move to")
    Store.editItems(mv.id, function(items)
        table.insert(items, outer)
        table.insert(items, other)
        return true
    end)
    MoveTo.pick(mv.id, outer.id)
    H.drain()
    local texts = {}
    for _, row in ipairs(top().buttons) do
        table.insert(texts, row[1].text)
    end
    eq({ "\u{F0C9}  Top level", "\u{F07B}  Other" }, texts)
    eq(false, top().buttons[1][1].enabled, "already at top level")
    H.tapButton("\u{F07B}  Other")
    local items = Store.menu(mv.id).items
    eq(1, #items)
    eq(outer.id, items[1].data.items[1].id)
    local ok, why = Store.editItems(mv.id, function(list)
        return model.moveTo(list, outer.id, sub.id)
    end)
    eq(false, ok)
    eq("descendant", why)
    Store.deleteMenu(mv.id)
end)

test("duplicate gives fresh ids, deep", function()
    local before = #Store.menu(m.id).items
    ItemDialog.duplicate(m.id, tools.id)
    local items = Store.menu(m.id).items
    eq(before + 1, #items)
    local _, list, idx = model.find(items, tools.id)
    local copy = list[idx + 1]
    assert(copy.id ~= tools.id)
    assert(copy.data.items[1].id ~= tools.data.items[1].id)
    ItemDialog.delete(m.id, copy.id) -- folder with children asks first
    H.drain()
    local box = top()
    assert(box.ok_callback, "confirm box for non-empty folder")
    box.ok_callback()
    H.UIManager:close(box)
    H.drain()
    eq(before, #Store.menu(m.id).items)
end)

test("D-pad: focus, open flyout, back, run", function()
    API.open(m.id)
    H.drain()
    local p = assert(H.popup())
    H.key("Down")
    eq(true, p.focus_visible)
    eq(1, p.chain[1].focus)
    H.key("Down")
    eq(2, p.chain[1].focus)
    H.key("Down")
    eq("Tools", p.chain[1].panel.rows[p.chain[1].focus].label)
    H.key("Right")
    eq(2, #p.chain, "flyout opened")
    eq(1, p.chain[2].focus, "focus in flyout")
    H.shot("p2_dpad")
    H.key("Left")
    eq(1, #p.chain, "flyout closed")
    eq("Tools", p.chain[1].panel.rows[p.chain[1].focus].label, "focus back on opener")
    H.key("Up")
    H.key("Up")
    eq(1, p.chain[1].focus)
    H.key("Up")
    -- wraps to the last actionable row
    eq(#p.chain[1].panel.rows, p.chain[1].focus)
    H.key("Back")
    assert(p.closed, "back at root closes")
end)

test("paging: a long menu pages and swipes turn pages", function()
    local long = Store.createMenu("Long")
    Store.editItems(long.id, function(items)
        for _ = 1, 30 do
            table.insert(items, act("history"))
        end
        return true
    end)
    API.open(long.id)
    H.drain()
    local p = assert(H.popup())
    local panel = p.chain[1].panel
    assert(panel:pageCount() > 1, "paged")
    local r = panel:rect()
    local pr = panel.pager_rect
    H.tap(pr.x + pr.w - 10, pr.y + pr.h - 10) -- next arrow
    eq(2, panel.page)
    H.swipe(r.x + 20, r.y + 60, "east")
    eq(1, panel.page)
    H.shot("p2_paging")
    Store.deleteMenu(long.id)
end)

test("editor lists items with markers and drills into folders", function()
    local Editor = require("minimenu/ui/editor")
    local list = Editor.showItems(m.id)
    H.drain()
    local texts = {}
    for _, it in ipairs(list.item_table) do
        table.insert(texts, it.text)
    end
    assert(texts[#texts]:find("Add item"), "add row last")
    -- open Tools
    for _, it in ipairs(list.item_table) do
        if it.text:find("Tools") then
            it.callback(list)
            break
        end
    end
    H.drain()
    eq("Edit me \u{203A} Tools", list.title_bar.title_widget.text)
    H.shot("p2_editor")
    local night = Store.menu(m.id).items[3].data.items[1]
    local mover = assert(ItemDialog.showMove(m.id, night.id))
    H.drain()
    press(mover, "down")
    eq(mover, top())
    assert(mover.title:find("2 of %d+ in Tools"), mover.title)
    assert(list.item_table[2].text:find("Night"), list.item_table[2].text)
    H.shot("p2_editor_move")
    press(mover, "done")
    list.onReturn()
    H.drain()
    eq("Edit me", list.title_bar.title_widget.text)
    H.UIManager:close(list)
    H.drain()
end)

test("main menu entry is registered under Tools", function()
    local fm = require("apps/filemanager/filemanager").instance
    local Live = require("minimenu/menupath/live")
    local Walk = require("minimenu/menupath/walk")
    local node = Walk.resolve(Live.tree({ ui = fm }), { { id = "tools" }, { id = "minimenu" } })
    assert(node, "Tools › MiniMenu")
    local sub = assert(Walk.children(node))
    local texts = {}
    for _, it in ipairs(sub) do
        table.insert(texts, it.text or it.text_func())
    end
    local expected = { "New menu…" }
    for _, menu in ipairs(Store.menus()) do
        table.insert(expected, menu.title)
    end
    table.insert(expected, "Appearance")
    table.insert(expected, "Check for updates")
    eq(expected, texts)
end)

H.finish()
