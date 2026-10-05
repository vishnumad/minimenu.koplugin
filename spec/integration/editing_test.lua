local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local ItemDialog = require("minimenu/ui/item_dialog")
local DispatchUtil = require("minimenu/dispatch")
local Actions = require("minimenu/actions")

local function act(name)
    return { id = Store.issueItemId(), kind = "dispatcher", data = { action = { [name] = true } } }
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
    eq(cfont.hash, require("minimenu/ui/popup").metrics().face.hash)
    Store.setSetting("font", nil)
end)

local function texts(tm)
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
    error("no entry " .. text .. " in " .. table.concat(texts(tm), ", "))
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
    for _, t in ipairs(texts(tm)) do
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
    for _, t in ipairs(texts(tm)) do
        assert(t ~= "Doomed", "deleted menu still listed")
    end
    closeSettings(tm)
end)

H.finish()
