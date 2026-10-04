local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq

local function item(kind, data, extra)
    local it = { id = Store.issueItemId(), kind = kind, data = data }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end
local function act(name) return item("dispatcher", { action = { [name] = true } }) end
local function path(...)
    local p = {}
    for _, id in ipairs({ ... }) do table.insert(p, { id = id }) end
    return p
end
local function labels() return H.rowLabels(1) end
local function has(list, label)
    for _, l in ipairs(list) do if l == label then return true end end
    return false
end

local other = Store.createMenu("Other menu")
Store.editItems(other.id, function(items) table.insert(items, act("history")) return true end)

local quick = Store.createMenu("Quick")
Store.editItems(quick.id, function(items)
    table.insert(items, item("menu_item", { path = path("setting", "night_mode"), toggle = true, captured_in = "filemanager" }))
    table.insert(items, item("menu_item", { path = path("setting", "network", "network_wifi"), toggle = true, captured_in = "filemanager" }))
    table.insert(items, item("menu_item", { path = path("navi", "table_of_contents"), captured_in = "reader" }))
    table.insert(items, act("toc"))
    table.insert(items, act("toggle_page_flipping"))   -- paging only
    table.insert(items, act("toggle_style_tweaks"))    -- rolling only
    table.insert(items, item("plugin", { name = "kosync", doc_only = true }))
    table.insert(items, item("plugin", { name = "statistics" }))
    table.insert(items, item("menu_item", { path = path("setting", "network"), page = true, captured_in = "filemanager" }))
    table.insert(items, item("menu_link", { menu = other.id }))
    table.insert(items, item("menu_link", { menu = "m999" }))
    table.insert(items, item("dispatcher", { action = { not_a_real_action = true } }))
    return true
end)

local reader_tools = Store.createMenu("Reader tools")
Store.editItems(reader_tools.id, function(items)
    table.insert(items, act("toc"))
    table.insert(items, act("bookmarks"))
    table.insert(items, item("plugin", { name = "kosync", doc_only = true }))
    return true
end)

H.fm()

test("FM hides reader-only targets, keeps the rest", function()
    API.open(quick.id)
    H.drain()
    local l = labels()
    eq(true, has(l, "Night mode"), "night mode")
    eq(true, has(l, "Wi-Fi connection"), "wifi")
    eq(true, has(l, "Network"), "network page")
    eq(true, has(l, "Other menu"), "link")
    eq(false, has(l, "Table of contents"), "reader-only dispatcher / menu entry")
    eq(false, has(l, "Toggle page flipping"), "paging action")
    eq(false, has(l, "Toggle style tweaks"), "rolling action")
    eq(false, has(l, "Missing menu"), "dangling link")
    eq(false, has(l, "Unknown item"), "unknown action")
    local kosync_shown = false
    for _, row in ipairs(H.popup().chain[1].panel.rows) do
        if row.item and row.item.data.name == "kosync" then kosync_shown = true end
    end
    eq(false, kosync_shown, "is_doc_only plugin hidden in FM")
    H.shot("p1_quick_fm")
end)

test("dimming instead of hiding shows reader-only rows inert", function()
    Store.setOption(quick.id, "hide_unavailable", false)
    API.open(quick.id)
    H.drain()
    local l = labels()
    eq(true, has(l, "(Table of contents)"), "dimmed toc")
    eq(true, has(l, "(Missing menu)"), "dimmed dangling link")
    local p = assert(H.popup())
    local idx
    for i, row in ipairs(p.chain[1].panel.rows) do if row.label == "Table of contents" then idx = i end end
    H.tap(H.rowCenter(1, idx))
    eq(true, not p.closed, "tapping a dimmed row does nothing")
    H.shot("p1_quick_fm_dimmed")
    Store.setOption(quick.id, "hide_unavailable", true)
end)

test("menu-entry toggle flips in place (keep_open)", function()
    G_reader_settings:makeFalse("night_mode")
    API.open(quick.id)
    H.drain()
    local p = assert(H.popup())
    local i = H.rowIndex(1, "Night mode")
    eq(false, p.chain[1].panel.rows[i].checked)
    H.tap(H.rowCenter(1, i))
    eq(true, not p.closed, "popup stays open")
    eq(true, G_reader_settings:isTrue("night_mode"), "night mode toggled")
    eq(true, p.chain[1].panel.rows[H.rowIndex(1, "Night mode")].checked, "checkbox updated")
    H.shot("p1_toggle_on")
    H.tap(H.rowCenter(1, H.rowIndex(1, "Night mode")))
    eq(false, G_reader_settings:isTrue("night_mode"))
end)

test("a captured page opens in a hosted TouchMenu", function()
    API.open(quick.id)
    H.drain()
    H.tap(H.rowCenter(1, H.rowIndex(1, "Network")))
    assert(H.popup() == nil, "popup closed")
    local top = H.UIManager._window_stack[#H.UIManager._window_stack].widget
    local tm = top[1]
    assert(tm and tm.item_table, "TouchMenu host shown")
    eq("Wi-Fi connection", tm.item_table[1].text_func and tm.item_table[1].text_func() or tm.item_table[1].text)
    H.shot("p1_hosted_page")
    tm:closeMenu()
    H.drain()
end)

test("links open the target menu as a flyout", function()
    API.open(quick.id)
    H.drain()
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, H.rowIndex(1, "Other menu")))
    eq(2, #p.chain)
    eq({ "History" }, H.rowLabels(2))
end)

test("plugin item runs its menu entry (submenu hosted)", function()
    API.open(quick.id)
    H.drain()
    local i
    for j, row in ipairs(H.popup().chain[1].panel.rows) do
        if row.item and row.item.data.name == "statistics" then i = j end
    end
    assert(i, "statistics row")
    H.tap(H.rowCenter(1, i))
    local top = H.UIManager._window_stack[#H.UIManager._window_stack].widget
    assert(top[1] and top[1].item_table, "statistics submenu hosted")
    top[1]:closeMenu()
    H.drain()
end)

test("a reader-tools menu in the FM shows the placeholder", function()
    API.open(reader_tools.id)
    H.drain()
    eq({ "<Nothing here in the file browser>" }, labels())
    H.shot("p1_placeholder_fm")
end)

test("plugin picker offers is_doc_only plugins from the FM", function()
    local Picker = require("minimenu/ui/pickers/plugins")
    local Context = require("minimenu/context")
    local found, self_listed
    for _, row in ipairs(Picker.rows(Context.current())) do
        if row.data.name == "kosync" then found = row end
        if row.data.name == "minimenu" then self_listed = true end
    end
    assert(found, "kosync offered")
    eq(true, found.reader_only)
    eq(true, found.data.doc_only)
    eq(nil, self_listed)
end)

test("editor marks items hidden here", function()
    local Editor = require("minimenu/ui/editor")
    local Context = require("minimenu/context")
    local rows = Editor.itemRows(quick.id, nil, Context.current(), {})
    local marks = {}
    for _, r in ipairs(rows) do marks[r.text] = r.mandatory end
    eq("Not available here", marks["Table of contents"])
    eq("Not available here", marks["\u{F0C9}  Missing menu"])
end)

test("capture picker drills lazily and captures a leaf with its path", function()
    local Capture = require("minimenu/ui/pickers/menu_capture")
    local Context = require("minimenu/context")
    local got
    Capture.pick(Context.current(), function(data) got = data or false end)
    H.drain()
    local menu = H.UIManager._window_stack[#H.UIManager._window_stack].widget
    local function choose(text)
        for _, it in ipairs(menu.item_table) do
            if it.text == text then it.callback(menu) H.drain() return end
        end
        error("no entry " .. text)
    end
    choose("Settings")
    choose("Network")
    eq("Settings \u{203A} Network", menu.title_bar.title_widget.text)
    H.shot("p1_capture_picker")
    choose("Wi-Fi connection")
    assert(got, "captured")
    eq("setting", got.path[1].id)
    eq("network", got.path[2].id)
    eq("network_wifi", got.path[3].id)
    eq(false, got.page)
    eq("filemanager", got.captured_in)
end)

test("dispatcher picker returns the first single selection", function()
    local DP = require("minimenu/ui/pickers/dispatcher")
    local got
    local tm = DP.pick({}, function(action) got = action or false end)
    H.drain()
    -- General section, then "History"
    local general = tm.item_table[1]
    tm:onMenuSelect(general)
    H.drain()
    local hist
    for _, it in ipairs(tm.item_table) do if it.text == "History" then hist = it end end
    assert(hist, "History in General")
    tm:onMenuSelect(hist)
    H.drain()
    H.drain()
    assert(got, "picked")
    eq(true, got.history)
end)

-- Reader contexts ------------------------------------------------------------

test("EPUB: reader items shown, PDF-only hidden", function()
    H.reader("juliet.epub")
    API.open(quick.id)
    H.drain()
    local l = labels()
    eq(true, has(l, "Table of contents"), "toc")
    eq(true, has(l, "Toggle style tweaks"), "rolling action in EPUB")
    eq(false, has(l, "Toggle page flipping"), "paging action hidden in EPUB")
    eq(true, has(l, "Wi-Fi connection"), "wifi captured in FM works in reader")
    local kosync = false
    for _, row in ipairs(H.popup().chain[1].panel.rows) do
        if row.item and row.item.data.name == "kosync" then kosync = true end
    end
    eq(true, kosync, "doc-only plugin shown in reader")
    H.shot("p1_quick_epub")
end)

test("a greyed-out reader entry stays visible (dimmed) as the first row", function()
    local reader = require("apps/reader/readerui").instance
    local back = Store.createMenu("Back first")
    Store.editItems(back.id, function(items)
        table.insert(items, item("menu_item", { path = { { id = "navi", text = "Navigation" },
            { id = "go_to_previous_location", text = "Go back to previous location" } }, captured_in = "reader" },
            { label = "Go back" }))
        table.insert(items, act("toc"))
        return true
    end)
    reader.link.location_stack = {}
    API.open(back.id)
    H.drain()
    eq({ "(Go back)", "Table of contents" }, labels(), "no history: dimmed, not hidden")
    local p = assert(H.popup())
    H.tap(H.rowCenter(1, 1))
    eq(true, not p.closed, "tapping the dimmed row does nothing")
    API.close()
    H.drain()
    reader.link:addCurrentLocationToStack()
    API.open(back.id)
    H.drain()
    eq({ "Go back", "Table of contents" }, labels(), "with history: enabled")
    Store.deleteMenu(back.id)
end)

test("PDF: paging action shown, rolling hidden", function()
    H.reader("sample.pdf")
    API.open(quick.id)
    H.drain()
    local l = labels()
    eq(true, has(l, "Toggle page flipping"), "paging action in PDF")
    eq(false, has(l, "Toggle style tweaks"), "rolling action hidden in PDF")
end)

test("scope pins an item to one context", function()
    Store.editItems(other.id, function(items)
        table.insert(items, item("dispatcher", { action = { favorites = true } }, { scope = "filemanager" }))
        return true
    end)
    API.open(other.id)
    H.drain()
    eq({ "History" }, labels())
end)

H.closeReader()
H.finish()
