local Kinds = require("minimenu/kinds/init")
local DispatchUtil = require("minimenu/dispatch")
local Store = require("minimenu/store")

local current -- context name the fake Dispatcher believes in
local list = {
    history = { category = "none", title = "History", general = true },
    toc = { category = "none", title = "Table of contents", reader = true },
}
local executed = {}
local fakeDispatcher = {
    isActionEnabled = function(_, action)
        -- mirrors KOReader's Dispatcher:isActionEnabled
        local disabled = true
        if action and (action.condition == nil or action.condition == true) then
            if current.sub == "paging" then
                disabled = action.rolling
            elseif current.sub == "rolling" then
                disabled = action.paging
            else
                disabled = action.reader or action.rolling or action.paging
            end
        end
        return not disabled
    end,
    getNameFromItem = function(_, name)
        return list[name] and list[name].title or "Unknown item"
    end,
    menuTextFunc = function(_, action)
        local n = 0
        for k in pairs(action) do
            if k ~= "settings" then n = n + 1 end
        end
        return n .. " actions"
    end,
    execute = function(_, action)
        table.insert(executed, action)
    end,
}

local wifi = false
local function fakeTree()
    return {
        {
            id = "setting",
            {
                id = "night_mode",
                text = "\238\128\128 Night mode",
                checked_func = function()
                    return false
                end,
                callback = function() end,
            },
            {
                id = "network",
                text = "Network",
                sub_item_table = {
                    {
                        id = "network_wifi",
                        text = "Wi-Fi connection",
                        checked_func = function()
                            return wifi
                        end,
                        callback = function()
                            wifi = not wifi
                        end,
                    },
                },
            },
            {
                id = "off",
                text = "Disabled",
                enabled_func = function()
                    return false
                end,
                callback = function() end,
            },
        },
    }
end
local function readerTree()
    local t = fakeTree()
    table.insert(
        t,
        1,
        { id = "navi", { id = "table_of_contents", text = "Table of contents", callback = function() end } }
    )
    return t
end

local function fakeUI(kind, opts)
    opts = opts or {}
    local ui = { menu = {} }
    if opts.broken then
        ui.menu.setUpdateItemTable = function()
            error("MenuSorter exploded")
        end
    else
        ui.menu.tab_item_table = kind == "reader" and readerTree() or fakeTree()
    end
    ui.statistics = {
        addToMainMenu = function(_, mi)
            mi.statistics = { text = "Reading statistics", callback = function() end }
        end,
    }
    if kind == "reader" then
        ui.kosync = {
            addToMainMenu = function(_, mi)
                mi.progress_sync = { text = "Progress sync", sub_item_table = {} }
            end,
        }
    end
    return ui
end

local contexts = {
    fm = { name = "filemanager" },
    paging = { name = "reader", sub = "paging" },
    rolling = { name = "reader", sub = "rolling" },
}

local function row(kind, data, ctx)
    current = ctx
    return Kinds.get(kind).resolve({ id = "i1", kind = kind, data = data }, ctx)
end

describe("kinds resolve", function()
    setup(function()
        Kinds.registerBuiltins()
        DispatchUtil.inject(fakeDispatcher, list)
    end)
    teardown(function()
        DispatchUtil.inject(nil, nil)
    end)

    before_each(function()
        for _, c in pairs(contexts) do
            c.ui = fakeUI(c.name)
            c._tree = nil
        end
    end)

    describe("dispatcher", function()
        it("is available where Dispatcher enables it, never when unknown", function()
            assert.is_true(row("dispatcher", { action = { history = true } }, contexts.fm).available)
            assert.is_false(row("dispatcher", { action = { toc = true } }, contexts.fm).available)
            assert.is_true(row("dispatcher", { action = { toc = true } }, contexts.paging).available)
            assert.is_false(row("dispatcher", { action = { gone = true } }, contexts.paging).available)
        end)
        it("labels and runs the stored table verbatim", function()
            local action = { history = true }
            local r = row("dispatcher", { action = action }, contexts.fm)
            assert.equal("History", r.label)
            r.run()
            assert.equal(action, executed[#executed])
        end)
        it("multi-action items", function()
            local r = row(
                "dispatcher",
                { action = { history = true, toc = true, settings = { order = { "history", "toc" } } } },
                contexts.paging
            )
            assert.equal("2 actions", r.label)
            assert.is_true(r.available)
            r = row("dispatcher", { action = { history = true, toc = true } }, contexts.fm)
            assert.is_false(r.available)
        end)
    end)

    describe("menu_item", function()
        local wifi_path = { path = { { id = "setting" }, { id = "network" }, { id = "network_wifi" } } }
        it("toggle entries exist in every context and keep the popup open", function()
            for _, c in pairs(contexts) do
                local r = row("menu_item", wifi_path, c)
                assert.is_true(r.available)
                assert.is_true(r.keep_open)
                assert.is_false(r.checked)
            end
            local r = row("menu_item", wifi_path, contexts.fm)
            r.run()
            assert.is_true(row("menu_item", wifi_path, contexts.fm).checked)
            wifi = false
        end)
        it("reader menu entries are unavailable in the FM", function()
            local data = {
                path = {
                    { id = "navi", text = "Navigation" },
                    { id = "table_of_contents", text = "Table of contents" },
                },
                captured_in = "reader",
            }
            assert.is_false(row("menu_item", data, contexts.fm).available)
            assert.equal("Table of contents", row("menu_item", data, contexts.fm).label)
            assert.is_true(row("menu_item", data, contexts.paging).available)
            assert.is_true(row("menu_item", data, contexts.rolling).available)
        end)
        it("greyed-out entries are available but disabled", function()
            local r = row("menu_item", { path = { { id = "setting" }, { id = "off" } } }, contexts.fm)
            assert.is_true(r.available)
            assert.is_true(r.disabled)
            assert.is_falsy(
                row("menu_item", { path = { { id = "setting" }, { id = "night_mode" } } }, contexts.fm).disabled
            )
        end)
        it("lifts a leading PUA glyph into the icon", function()
            local r = row("menu_item", { path = { { id = "setting" }, { id = "night_mode" } } }, contexts.fm)
            assert.equal("Night mode", r.label)
            assert.equal("\238\128\128", r.icon)
        end)
        it("pages need a submenu", function()
            assert.is_true(
                row("menu_item", { path = { { id = "setting" }, { id = "network" } }, page = true }, contexts.fm).available
            )
            assert.is_false(
                row("menu_item", { path = { { id = "setting" }, { id = "night_mode" } }, page = true }, contexts.fm).available
            )
        end)
        it("fails open when the menu can't be built", function()
            local ctx = { name = "filemanager", ui = fakeUI("filemanager", { broken = true }) }
            local r = row(
                "menu_item",
                { path = { { id = "setting", text = "Settings" }, { id = "x", text = "Thing" } } },
                ctx
            )
            assert.is_true(r.available)
            assert.equal("Thing", r.label)
        end)
        it("builds the tree at most once per context", function()
            local builds = 0
            local ui = {
                menu = {
                    setUpdateItemTable = function(self)
                        builds = builds + 1
                        self.tab_item_table = fakeTree()
                    end,
                },
            }
            local ctx = { name = "filemanager", ui = ui }
            for _ = 1, 3 do
                row("menu_item", wifi_path, ctx)
            end
            assert.equal(1, builds)
        end)
    end)

    describe("plugin", function()
        it("is available where the plugin is loaded", function()
            assert.is_true(row("plugin", { name = "statistics" }, contexts.fm).available)
            assert.is_false(row("plugin", { name = "kosync", doc_only = true }, contexts.fm).available)
            contexts.paging.ui = fakeUI("reader")
            assert.is_true(row("plugin", { name = "kosync", doc_only = true }, contexts.paging).available)
        end)
        it("picks the entry: data.entry, then plugin name, then the only one", function()
            local Plugin = Kinds.get("plugin")
            local entries = { a = { text = "A" }, b = { text = "B" } }
            assert.equal(entries.b, Plugin.pickEntry(entries, { name = "x", entry = "b" }))
            assert.is_nil(Plugin.pickEntry(entries, { name = "x" }))
            assert.equal(entries.a, Plugin.pickEntry({ a = entries.a }, { name = "x" }))
            assert.equal(entries.a, Plugin.pickEntry({ x = entries.a, b = entries.b }, { name = "x" }))
        end)
    end)

    describe("containers", function()
        before_each(function()
            Store.setBackend(Store.memoryBackend(nil))
            Store.listeners = {}
            Store.load()
        end)
        it("folders are always available and lazy", function()
            local called = false
            local item = {
                id = "f",
                kind = "folder",
                label = "F",
                data = {
                    items = setmetatable({}, {
                        __index = function()
                            called = true
                        end,
                    }),
                },
            }
            local r = Kinds.get("folder").resolve(item, contexts.fm)
            assert.is_true(r.available)
            assert.is_false(called)
            assert.equal(item.data.items, r.children())
        end)
        it("links follow the target and go unavailable when it is deleted", function()
            local target = Store.createMenu("Target")
            local item = { id = "l", kind = "menu_link", data = { menu = target.id } }
            local r = Kinds.get("menu_link").resolve(item, contexts.fm)
            assert.is_true(r.available)
            assert.equal("Target", r.label)
            assert.equal(target.items, r.children())
            Store.deleteMenu(target.id)
            r = Kinds.get("menu_link").resolve(item, contexts.fm)
            assert.is_false(r.available)
            assert.equal("Missing menu", r.label)
        end)
    end)
end)
