local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local ItemDialog = require("minimenu/ui/item_dialog")
local DispatchUtil = require("minimenu/dispatch")
local Actions = require("minimenu/actions")
local model = require("minimenu/model")

local function act(name)
    return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } }
end
local function folder(label, items)
    return { id = Store.issueItemId(), kind = "folder", label = label, data = { items = items or {} } }
end

local function menuWith(title, ...)
    local items = { ... }
    local m = Store.createMenu(title)
    Store.editItems(m.id, function(list)
        for _, it in ipairs(items) do
            table.insert(list, it)
        end
        return true
    end)
    return m
end

local function holdRow(i)
    H.hold(H.rowCenter(1, i))
    assert(ItemDialog.current and H.top() == ItemDialog.current, "item dialog on top")
end

local function save(text)
    local dialog = assert(H.inputDialog(), "input dialog")
    dialog:setInputText(text)
    H.button(dialog, "Save").callback()
    H.drain()
end

local fm = H.fm()

test("Add item after… inserts the chosen kind right after the row", function()
    local m = menuWith("Add", act("history"), act("favorites"))
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Add item after…")
    eq("Add item", H.top().title)
    H.tapButton("Separator")
    eq({ "History", "--", "Favorites" }, H.rowLabels(1))
    eq("separator", Store.menu(m.id).items[2].kind)
    Store.deleteMenu(m.id)
end)

test("Rename… sets a label; clearing it brings the default name back", function()
    local m = menuWith("Rename", act("history"))
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Rename…")
    eq("History", H.inputDialog().input_hint, "default name as hint")
    save("  Recent  ")
    eq({ "Recent" }, H.rowLabels(1))
    holdRow(1)
    H.tapButton("Rename…")
    save("")
    eq({ "History" }, H.rowLabels(1))
    eq(nil, Store.menu(m.id).items[1].label)
    Store.deleteMenu(m.id)
end)

test("Change icon… shows the picked glyph; Default removes it", function()
    local m = menuWith("Icon", act("history"))
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Change icon…")
    local glyph = H.top().buttontable.buttons_layout[1][1]
    local d = glyph.dimen
    H.tap(d.x + 5, d.y + 5)
    eq(glyph.text, H.popup().chain[1].panel.rows[1].icon)
    holdRow(1)
    H.tapButton("Change icon…")
    H.tapButton("Default")
    eq(nil, Store.menu(m.id).items[1].icon)
    Store.deleteMenu(m.id)
end)

local ran = {}
require("minimenu/kinds/init").register({
    name = "probe",
    title = "Probe",
    action = true,
    pick = function(_ctx, done)
        done({ name = "side" })
    end,
    resolve = function(item)
        return {
            label = item.data.name,
            run = function()
                table.insert(ran, item.data.name)
            end,
        }
    end,
})

local function sideCenter(i)
    local r = assert(H.popup().chain[1].panel:sideRect(i), "row has a second action")
    return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2)
end

test("a second action runs from its icon; the rest of the row runs the first", function()
    ran = {}
    local m = menuWith("Second", { id = Store.issueItemId(), kind = "probe", data = { name = "main" } })
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Add second action…")
    eq("Second action", H.top().title)
    assert(H.button(H.top(), "Link to another menu"), "links can be second actions")
    H.tapButton("Probe")
    eq(require("minimenu/resolve").GEAR, H.popup().chain[1].panel.rows[1].secondary.icon)
    H.shot("second_action")
    H.tap(sideCenter(1))
    eq({ "side" }, ran)
    API.open(m.id)
    H.drain()
    H.tap(H.rowCenter(1, 1))
    eq({ "side", "main" }, ran)
    Store.deleteMenu(m.id)
end)

test("Action: … replaces the action, keeping the label and second action", function()
    local item = act("history")
    item.label = "Mine"
    item.secondary = { kind = "probe", data = { name = "side" } }
    local m = menuWith("Change", item)
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Action: History")
    eq("Change action", H.top().title)
    H.tapButton("Probe")
    local changed = Store.menu(m.id).items[1]
    eq("probe", changed.kind)
    eq("side", changed.data.name)
    eq("Mine", changed.label)
    eq("side", changed.secondary.data.name)
    Store.deleteMenu(m.id)
end)

test("Keep menu open runs the action in place", function()
    ran = {}
    local m = menuWith("Keep", { id = Store.issueItemId(), kind = "probe", data = { name = "main" } })
    API.open(m.id)
    H.drain()
    holdRow(1)
    H.tapButton("Keep menu open")
    eq(true, Store.menu(m.id).items[1].keep_open)
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, 1))
    H.tap(H.rowCenter(1, 1))
    eq({ "main", "main" }, ran)
    eq(true, not p.closed, "popup stays open")
    holdRow(1)
    H.tapButton("\u{2713} Keep menu open")
    eq(nil, Store.menu(m.id).items[1].keep_open)
    Store.deleteMenu(m.id)
end)

test("holding the second action edits the item; Remove clears it", function()
    local m = menuWith("Second", {
        id = Store.issueItemId(),
        kind = "probe",
        data = { name = "main" },
        secondary = { kind = "probe", data = { name = "side" } },
    })
    API.open(m.id)
    H.drain()
    H.hold(sideCenter(1))
    assert(ItemDialog.current and H.top() == ItemDialog.current, "item dialog on top")
    H.tapButton(require("minimenu/resolve").GEAR .. "  Second action: side")
    H.tapButton("Remove")
    eq(nil, Store.menu(m.id).items[1].secondary)
    eq(nil, H.popup().chain[1].panel.rows[1].secondary)
    Store.deleteMenu(m.id)
end)

test("D-pad: Right steps onto the second action, Press runs it", function()
    ran = {}
    local m = menuWith("Second", {
        id = Store.issueItemId(),
        kind = "probe",
        data = { name = "main" },
        secondary = { kind = "probe", data = { name = "side" } },
    })
    API.open(m.id)
    H.drain()
    local p = assert(H.popup())
    H.key("Down")
    H.key("Right")
    eq("secondary", p.chain[1].focus_part)
    H.key("Left")
    eq("row", p.chain[1].focus_part)
    H.key("Right")
    H.key("Press")
    eq({ "side" }, ran)
    Store.deleteMenu(m.id)
end)

test("a second action that links to a menu opens it beside the row", function()
    ran = {}
    local target = menuWith("Linked", act("history"), act("favorites"))
    local m = menuWith("Second", {
        id = Store.issueItemId(),
        kind = "probe",
        data = { name = "main" },
        secondary = { kind = "menu_link", data = { menu = target.id } },
    })
    API.open(m.id)
    H.drain()
    local p = assert(H.popup())
    H.tap(sideCenter(1))
    eq(2, #p.chain, "flyout opened")
    eq("secondary", p.chain[1].open_part)
    eq({ "History", "Favorites" }, H.rowLabels(2))
    H.shot("second_action_link")
    Store.editItems(target.id, function(items)
        table.remove(items)
        return true
    end)
    eq({ "History" }, H.rowLabels(2), "stays open when the menus change")
    H.tap(sideCenter(1))
    eq(1, #p.chain, "tapping it again closes it")
    H.key("Down")
    H.key("Right")
    H.key("Press")
    eq(2, #p.chain, "keys open it too")
    H.tap(H.rowCenter(1, 1))
    eq({ "main" }, ran, "the rest of the row still runs the main action")
    Store.deleteMenu(m.id)
    Store.deleteMenu(target.id)
end)

test("show_title and a fixed position apply to the popup", function()
    local m = menuWith("Placed", act("history"))
    Store.setOption(m.id, "show_title", true)
    Store.setOption(m.id, "position", "bottom_right")
    API.open(m.id, { gesture = H.gesture("tap", 60, 80) })
    H.drain()
    local p = assert(H.popup())
    local panel = p.chain[1].panel
    eq("Placed", panel.title)
    local r = panel:rect()
    eq(H.Screen:getWidth() - p.cfg.margin, r.x + r.w, "right edge")
    eq(H.Screen:getHeight() - p.cfg.margin, r.y + r.h, "bottom edge")
    API.close()
    H.drain()
    Store.setOption(m.id, "show_title", false)
    API.open(m.id)
    H.drain()
    eq(nil, H.popup().chain[1].panel.title)
    Store.deleteMenu(m.id)
end)

test("a missing font falls back to the UI font", function()
    Store.setSetting("font", "/missing/font.ttf")
    local cfont = require("ui/font"):getFace("cfont", Store.setting("font_size"))
    eq(cfont.hash, require("minimenu/ui/metrics").get().face.hash)
    Store.setSetting("font", nil)
end)

local function entryTexts(tm)
    local out = {}
    for _, it in ipairs(tm.item_table) do
        table.insert(out, it.text or it.text_func())
    end
    return out
end

local function choose(tm, text)
    for _, it in ipairs(tm.item_table) do
        if (it.text or it.text_func()) == text then
            tm:onMenuSelect(it)
            H.drain()
            return
        end
    end
    error("no entry " .. text .. " in " .. table.concat(entryTexts(tm), ", "))
end

local function openSettings(title)
    fm.menu:onShowMenu()
    H.drain()
    local tm = fm.menu.menu_container[1]
    for i, tab in ipairs(tm.tab_item_table) do
        for _, it in ipairs(tab) do
            if it.text == "MiniMenu" then
                tm:switchMenuTab(i)
                choose(tm, "MiniMenu")
                choose(tm, title)
                return tm
            end
        end
    end
    error("no MiniMenu entry")
end

local function closeSettings(tm)
    tm:closeMenu()
    H.drain()
end

test("the Appearance page shows a live preview until it is left", function()
    local tm = openSettings("Appearance")
    local preview = H.top()
    eq("MiniMenuPreview", preview.name)
    local w = preview.dimen.w
    Store.setSetting("padding", 30)
    assert(preview.dimen.w > w, "preview follows the settings")
    Store.setSetting("padding", nil)
    H.key("Back")
    eq(false, H.UIManager:isWidgetShown(preview))
    closeSettings(tm)
end)

test("Icon size scales icons but not the text", function()
    local Metrics = require("minimenu/ui/metrics")
    local before = Metrics.get()
    Store.setSetting("icon_scale", 150)
    local after = Metrics.get()
    Store.setSetting("icon_scale", nil)
    assert(after.icon_size > before.icon_size, "icons grow")
    eq(before.face, after.face, "text unchanged")
    eq(before.icon_size, Metrics.get().icon_size, "back to the default size")
end)

test("Reset appearance asks, then restores every default", function()
    Store.setSetting("radius", 12)
    Store.setSetting("font", "/some/font.ttf")
    local tm = openSettings("Appearance")
    choose(tm, "Reset appearance")
    local box = H.UIManager._window_stack[#H.UIManager._window_stack - 1].widget
    assert(box.ok_callback, "confirm box below the preview")
    eq(12, Store.setting("radius"), "not reset before confirming")
    box.ok_callback()
    H.UIManager:close(box)
    H.drain()
    eq(Store.DEFAULT_SETTINGS.radius, Store.setting("radius"))
    eq(nil, Store.setting("font"))
    closeSettings(tm)
end)

test("menu page: Show in action list unregisters and registers the action", function()
    local m = menuWith("Listed", act("history"))
    local tm = openSettings("Listed")
    choose(tm, "Show in action list")
    eq(false, DispatchUtil.exists(Actions.name(m.id)))
    choose(tm, "Show in action list")
    eq(true, DispatchUtil.exists(Actions.name(m.id)))
    closeSettings(tm)
    Store.deleteMenu(m.id)
end)

test("menu page: Rename… renames the menu and its action", function()
    local m = menuWith("Old name", act("history"))
    local tm = openSettings("Old name")
    choose(tm, "Rename…")
    save("New name")
    eq("New name", Store.menu(m.id).title)
    eq("MiniMenu: New name", require("dispatcher"):getNameFromItem(Actions.name(m.id)))
    closeSettings(tm)
    Store.deleteMenu(m.id)
end)

test("menu page: Duplicate adds a copy to the list", function()
    local m = menuWith("Twin", act("history"))
    local tm = openSettings("Twin")
    choose(tm, "Duplicate")
    H.UIManager:close(H.top())
    H.drain()
    local copy = Store.menus()[#Store.menus()]
    eq("Twin (copy)", copy.title)
    eq(1, #copy.items)
    eq(true, DispatchUtil.exists(Actions.name(copy.id)))
    local listed = false
    for _, t in ipairs(entryTexts(tm)) do
        if t == "Twin (copy)" then listed = true end
    end
    assert(listed, "copy listed after going back up")
    closeSettings(tm)
    Store.deleteMenu(m.id)
    Store.deleteMenu(copy.id)
end)

test("menu page: Delete… asks, then removes the menu and its action", function()
    local m = menuWith("Doomed", act("history"))
    local tm = openSettings("Doomed")
    choose(tm, "Delete…")
    local box = H.top()
    assert(box.ok_callback, "confirm box")
    assert(Store.menu(m.id), "not deleted before confirming")
    box.ok_callback()
    H.UIManager:close(box)
    H.drain()
    eq(nil, Store.menu(m.id))
    eq(false, DispatchUtil.exists(Actions.name(m.id)))
    for _, t in ipairs(entryTexts(tm)) do
        assert(t ~= "Doomed", "deleted menu still listed")
    end
    closeSettings(tm)
end)

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
    eq("History", ItemDialog.current.title, "just the name when nothing is wrong")
    eq({
        "Rename…",
        "Change icon…",
        "Action: History",
        "Keep menu open",
        "Add second action…",
        "Show in: Reader and File browser",
        "Add item after…",
        "Move…",
        "Duplicate",
        "Delete",
    }, buttonTexts(ItemDialog.current))
    H.shot("editing_item_dialog")
    H.UIManager:close(ItemDialog.current)
    H.drain()
    eq(nil, ItemDialog.current)
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
    H.shot("editing_move_dialog")
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

test("deleting a folder counts the items in its subfolders too", function()
    local outer = folder("Outer", { act("history"), folder("Sub", { act("favorites"), act("collections") }) })
    Store.editItems(m.id, function(items)
        table.insert(items, outer)
        return true
    end)
    ItemDialog.delete(m.id, outer.id)
    H.drain()
    local box = top()
    eq("Delete this folder and the 4 items in it?", box.text)
    box.ok_callback()
    H.UIManager:close(box)
    H.drain()
    eq(nil, model.find(Store.menu(m.id).items, outer.id))
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
    H.shot("editing_dpad")
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

test("D-pad: Left opens and Right closes when flyouts cascade left", function()
    local deeper = folder("Deeper", { act("favorites") })
    local sub = folder("Sub", { act("history"), deeper })
    local lm = Store.createMenu("Leftwards")
    Store.editItems(lm.id, function(items)
        table.insert(items, sub)
        table.insert(items, act("favorites"))
        return true
    end)
    API.open(lm.id, { gesture = H.gesture("tap", H.Screen:getWidth() - 30, 60) })
    H.drain()
    local p = assert(H.popup())
    eq("left", p:cascadeDirection(), "root on the right")
    H.key("Down")
    eq(1, p.chain[1].focus)
    H.key("Right")
    eq(1, #p.chain, "Right does not open")
    H.key("Left")
    eq(2, #p.chain, "Left opens")
    eq("left", p.direction)
    H.key("Down")
    eq("Deeper", p.chain[2].panel.rows[p.chain[2].focus].label)
    H.key("Left")
    eq(3, #p.chain)
    H.key("Right")
    eq(2, #p.chain, "Right closes")
    eq("Deeper", p.chain[2].panel.rows[p.chain[2].focus].label, "focus back on opener")
    H.key("Right")
    eq(1, #p.chain)
    H.key("Right")
    eq(1, #p.chain)
    assert(not p.closed, "Right at the root does nothing")
    p:close()
    H.drain()
    Store.deleteMenu(lm.id)
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
    H.shot("editing_paging")
    Store.deleteMenu(long.id)
end)

test("an edit keeps a flyout's page, or its last page if that one is gone", function()
    local big = folder("Big")
    for _ = 1, 30 do
        table.insert(big.data.items, act("history"))
    end
    local paged = Store.createMenu("Paged flyout")
    Store.editItems(paged.id, function(items)
        table.insert(items, act("favorites"))
        table.insert(items, big)
        return true
    end)
    API.open(paged.id)
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "Big")))
    eq(2, #p.chain)
    local pages = p.chain[2].panel:pageCount()
    assert(pages > 2, "flyout paged")
    p:setPage(2, 2)
    Store.editItems(paged.id, function(items)
        items[1].label = "Faves"
        return true
    end)
    H.drain()
    eq(2, #p.chain)
    eq(2, p.chain[2].panel.page, "page kept")
    p:setPage(2, pages)
    Store.editItems(paged.id, function(items)
        local kids = items[2].data.items
        for i = #kids, 11, -1 do
            table.remove(kids, i)
        end
        return true
    end)
    H.drain()
    eq(2, #p.chain)
    eq(p.chain[2].panel:pageCount(), p.chain[2].panel.page, "clamped to the last page")
    p:close()
    H.drain()
    Store.deleteMenu(paged.id)
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
    H.shot("editing_editor")
    local night = Store.menu(m.id).items[3].data.items[1]
    local mover = assert(ItemDialog.showMove(m.id, night.id))
    H.drain()
    press(mover, "down")
    eq(mover, top())
    assert(mover.title:find("2 of %d+ in Tools"), mover.title)
    assert(list.item_table[2].text:find("Night"), list.item_table[2].text)
    H.shot("editing_editor_move")
    press(mover, "done")
    list.onReturn()
    H.drain()
    eq("Edit me", list.title_bar.title_widget.text)
    H.UIManager:close(list)
    H.drain()
end)

test("main menu entry is registered under Tools", function()
    local filemanager = require("apps/filemanager/filemanager").instance
    local Live = require("minimenu/menupath/live")
    local Walk = require("minimenu/menupath/walk")
    local node = Walk.resolve(Live.tree({ ui = filemanager }), { { id = "tools" }, { id = "minimenu" } })
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
