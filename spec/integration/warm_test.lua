local H = require("harness").setup()
local Store, API, test, eq = H.Store, H.API, H.test, H.eq
local UIManager = H.UIManager

local builds = setmetatable({}, { __mode = "k" })
for _, class in ipairs({ require("apps/reader/modules/readermenu"), require("apps/filemanager/filemanagermenu") }) do
    local orig = class.setUpdateItemTable
    class.setUpdateItemTable = function(self, ...)
        builds[self] = (builds[self] or 0) + 1
        return orig(self, ...)
    end
end
local function built(ui)
    return builds[ui.menu] or 0
end

-- Unbound by default in both modes.
local GESTURE = "two_finger_swipe_northeast"
local gestures = H.fm().gestures.data

local menus = {}
local function menu(title)
    local m = Store.createMenu(title, {
        {
            id = Store.issueItemId(),
            kind = "menu_item",
            data = { path = { { id = "navi" }, { id = "table_of_contents" } } },
        },
    })
    table.insert(menus, m.id)
    return m
end

local function bind(mode, menu_id)
    gestures[mode][GESTURE] = { ["minimenu_open_" .. menu_id] = true }
end

local function wtest(name, fn)
    test(name, function()
        local ok, err = xpcall(fn, debug.traceback)
        gestures.gesture_reader[GESTURE] = nil
        gestures.gesture_fm[GESTURE] = nil
        H.closeReader()
        for _, id in ipairs(menus) do
            Store.deleteMenu(id)
        end
        menus = {}
        if not ok then error(err, 0) end
    end)
end

local function openBook(file)
    H.closeFM()
    local ReaderUI = require("apps/reader/readerui")
    local DocumentRegistry = require("document/documentregistry")
    local reader = ReaderUI:new {
        dimen = H.Screen:getSize(),
        document = DocumentRegistry:openDocument(H.books(file)),
    }
    UIManager:show(reader)
    return reader
end

local function hooks()
    return #(UIManager.event_hook.InputEvent or {})
end

wtest("a menu that nothing opens doesn't build KOReader's menu", function()
    menu("Unbound")
    local reader = H.reader("juliet.epub")
    H.drain()
    eq(nil, reader.menu.tab_item_table)
    eq(0, built(reader))
end)

wtest("a menu bound to a reader gesture builds it once, on idle", function()
    local m = menu("Bound")
    bind("gesture_reader", m.id)
    local reader = H.reader("juliet.epub")
    H.drain()
    eq(1, built(reader))
    API.open(m.id)
    H.drain()
    eq(true, API.isOpen(m.id))
    eq(1, built(reader))
end)

wtest("a file browser gesture warms the file browser, not the reader", function()
    local m = menu("File browser only")
    bind("gesture_fm", m.id)
    local reader = H.reader("juliet.epub")
    H.drain()
    eq(0, built(reader))
    H.closeReader()
    local fm = H.fm()
    H.drain()
    eq(1, built(fm))
end)

wtest("input during the wait puts the build off", function()
    local m = menu("Busy")
    bind("gesture_reader", m.id)
    local reader = openBook("juliet.epub")
    UIManager.event_hook:execute("InputEvent")
    H.drain(1)
    eq(0, built(reader))
    H.drain(1)
    eq(1, built(reader))
end)

wtest("closing the reader before the timer cancels it", function()
    local m = menu("Closed early")
    bind("gesture_reader", m.id)
    local before = hooks()
    local reader = openBook("juliet.epub")
    assert(hooks() > before, "hook registered")
    reader:onClose()
    H.drain()
    eq(before, hooks())
    eq(0, built(reader))
end)

H.finish()
