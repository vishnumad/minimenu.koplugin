local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local model = require("minimenu/model")
local ItemDialog = require("minimenu/ui/item_dialog")

local function act(name) return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } } end
local function folder(label, items) return { id = Store.issueItemId(), kind = "folder", label = label, data = { items = items or {} } } end
local function top() return H.UIManager._window_stack[#H.UIManager._window_stack].widget end

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

test("long-press on a root row opens the item dialog", function()
    API.open(m.id)
    H.drain()
    H.hold(H.rowCenter(1, 1))
    assert(ItemDialog.current and top() == ItemDialog.current, "item dialog on top")
    assert(not H.popup().closed, "popup stays open underneath")
    H.shot("p2_item_dialog")
    H.UIManager:close(ItemDialog.current)
    H.drain()
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
    Store.editItems(m.id, function(items) return model.moveOut(items, inner.id) end)
    H.drain()
    eq(2, #p.chain)
    eq(nil, p.chain[2].open_index)
    -- and it now appears at the top level
    assert(H.rowIndex(1, "Inner"), "Inner moved to top level")
end)

test("a locked menu ignores long-press", function()
    Store.setOption(m.id, "lock", true)
    API.open(m.id)
    H.drain()
    ItemDialog.current = nil
    H.hold(H.rowCenter(1, 1))
    eq(nil, ItemDialog.current)
    eq(H.popup(), top())
    Store.setOption(m.id, "lock", false)
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

test("Move to… lists folders except the item's own subtree", function()
    local MoveTo = require("minimenu/ui/pickers/move_to")
    MoveTo.pick(m.id, tools.id)
    H.drain()
    local dlg = top()
    local texts = {}
    for _, row in ipairs(dlg.buttons) do table.insert(texts, row[1].text) end
    -- Tools is at top level; Inner was moved to top level in an earlier test.
    for _, t in ipairs(texts) do assert(not t:find("Tools"), "Tools must not be a target of itself") end
    assert(texts[1]:find("Top level"), "top level listed")
    H.UIManager:close(dlg)
    H.drain()
    -- model refuses a descendant move outright
    local sub = folder("Sub")
    Store.editItems(m.id, function() table.insert(tools.data.items, sub) return true end)
    local ok, why = Store.editItems(m.id, function(items) return model.moveTo(items, tools.id, sub.id) end)
    eq(false, ok)
    eq("descendant", why)
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
        for _ = 1, 30 do table.insert(items, act("history")) end
        return true
    end)
    API.open(long.id)
    H.drain()
    local p = assert(H.popup())
    local panel = p.chain[1].panel
    assert(panel:pageCount() > 1, "paged")
    local r = panel:rect()
    H.tap(r.x + r.w - 10, r.y + r.h - 10) -- next arrow
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
    for _, it in ipairs(list.item_table) do table.insert(texts, it.text) end
    assert(texts[#texts]:find("Add item"), "add row last")
    -- open Tools
    for _, it in ipairs(list.item_table) do
        if it.text:find("Tools") then it.callback(list) break end
    end
    H.drain()
    eq("Edit me \u{203A} Tools", list.title_bar.title_widget.text)
    H.shot("p2_editor")
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
    eq("New menu…", sub[1].text)
    local names = {}
    for i = 2, #sub - 1 do table.insert(names, sub[i].text_func()) end
    assert(#names >= 1)
end)

H.finish()
