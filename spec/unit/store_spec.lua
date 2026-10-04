local Store = require("minimenu/store")
local model = require("minimenu/model")

local function fresh(initial)
    local backend = Store.memoryBackend(initial)
    Store.setBackend(backend)
    Store.listeners = {}
    Store.migrations = {}
    Store.CURRENT_VERSION = model.SCHEMA_VERSION
    return backend
end

describe("store", function()
    it("treats a missing file as an empty store and does not write", function()
        local b = fresh(nil)
        local data = Store.load()
        assert.same(model.empty(), data)
        assert.equal(0, b.writes)
    end)

    describe("first-install seed", function()
        local function seed()
            Store.createMenu("Default")
        end

        it("runs once when there are no settings and writes them", function()
            local b = fresh(nil)
            Store.load(nil, seed)
            assert.equal(1, #Store.menus())
            assert.equal(1, b.writes)
            Store.setBackend(b)
            Store.load(nil, seed)
            assert.equal(1, #Store.menus())
            assert.equal(1, b.writes)
        end)

        it("does not run once the user has deleted every menu", function()
            local b = fresh({ version = 1, next_id = 5, menu_order = {}, menus = {} })
            Store.load(nil, seed)
            assert.equal(0, #Store.menus())
            assert.equal(0, b.writes)
        end)

        it("does not run when the settings can't be read", function()
            fresh(nil)
            local writes = 0
            Store.setBackend({
                read = function()
                    error("broken")
                end,
                write = function()
                    writes = writes + 1
                end,
            })
            Store.load(nil, seed)
            assert.equal(0, #Store.menus())
            assert.equal(0, writes)
        end)
    end)

    it("writes back only when sanitising changed something", function()
        local b = fresh({
            version = 1,
            next_id = 3,
            menu_order = { "m1" },
            menus = {
                m1 = { id = "m1", title = "A", items = {} },
            },
        })
        Store.load()
        assert.equal(0, b.writes)
        b = fresh({
            version = 1,
            next_id = 1,
            menu_order = {},
            menus = {
                m1 = { id = "m1", title = "A", items = {} },
            },
        })
        Store.load()
        assert.equal(1, b.writes)
        assert.same({ "m1" }, b.stored.menu_order)
    end)

    it("runs migrations in order and writes back", function()
        local b = fresh({ version = 1, next_id = 1, menu_order = {}, menus = {} })
        Store.CURRENT_VERSION = 3
        local calls = {}
        Store.migrations[1] = function(d)
            table.insert(calls, 1)
            d.a = true
            return d
        end
        Store.migrations[2] = function(d)
            table.insert(calls, 2)
            d.b = d.a
            return d
        end
        local data = Store.load()
        assert.same({ 1, 2 }, calls)
        assert.equal(3, data.version)
        assert.is_true(data.b)
        assert.equal(1, b.writes)
    end)

    it("leaves newer schema versions alone", function()
        fresh({ version = 9, next_id = 1, menu_order = {}, menus = {} })
        local data = Store.load()
        assert.equal(9, data.version)
    end)

    it("issues monotonic ids shared by menus and items", function()
        fresh(nil)
        Store.load()
        local m = Store.createMenu("One")
        assert.equal("m1", m.id)
        assert.equal("i2", Store.issueItemId())
        Store.deleteMenu("m1")
        local m2 = Store.createMenu("Two")
        assert.equal("m3", m2.id)
    end)

    it("emits lifecycle events and saves on every edit", function()
        local b = fresh(nil)
        Store.load()
        local events = {}
        Store.subscribe(function(e)
            table.insert(events, e.type)
        end)
        local m = Store.createMenu("One")
        Store.renameMenu(m.id, "Uno")
        Store.renameMenu(m.id, "Uno") -- no-op
        Store.setRegisterAction(m.id, false)
        Store.setOption(m.id, "position", "top")
        Store.editItems(m.id, function(items)
            table.insert(items, { id = Store.issueItemId(), kind = "separator", data = {} })
            return true
        end)
        Store.deleteMenu(m.id)
        assert.same(
            { "menu_created", "menu_renamed", "menu_action_changed", "menu_changed", "items_changed", "menu_deleted" },
            events
        )
        assert.equal(6, b.writes)
        assert.same({}, b.stored.menu_order)
    end)

    it("resolves options menu → built-in; ignores retired options", function()
        fresh(nil)
        Store.load()
        local m = Store.createMenu("One")
        assert.equal("gesture", Store.option(m, "position"))
        Store.setOption(m.id, "position", "top_left")
        assert.equal("top_left", Store.option(m, "position"))
        assert.is_true(Store.options(m).hide_unavailable)
        -- Stored by older versions; no longer exposed.
        Store.setOption(m.id, "width", 0.5)
        Store.setOption(m.id, "cascade", "left")
        assert.same(
            { position = "top_left", show_title = true, hide_unavailable = true, lock = false },
            Store.options(m)
        )
        -- Old global defaults are not copied into new menus.
        Store.setSetting("defaults", { position = "center" })
        assert.equal("gesture", Store.option(Store.createMenu("Two"), "position"))
    end)

    it("duplicates menus with fresh item ids", function()
        fresh(nil)
        Store.load()
        local a = Store.createMenu("A")
        Store.createMenu("B")
        Store.editItems(a.id, function(items)
            table.insert(items, {
                id = Store.issueItemId(),
                kind = "folder",
                data = {
                    items = {
                        { id = Store.issueItemId(), kind = "separator", data = {} },
                    },
                },
            })
            return true
        end)
        local copy = assert(Store.duplicateMenu(a.id, "A copy"))
        assert.equal("A copy", copy.title)
        assert.are_not.equal(a.items[1].id, copy.items[1].id)
        assert.are_not.equal(a.items[1].data.items[1].id, copy.items[1].data.items[1].id)
        local _, found = Store.findItem(copy.items[1].data.items[1].id)
        assert.is_not_nil(found)
    end)

    it("keeps orphan-kind items across load/save", function()
        local orphan = { id = "i2", kind = "from_other_plugin", data = { x = 1 } }
        local b = fresh({
            version = 1,
            next_id = 3,
            menu_order = { "m1" },
            menus = {
                m1 = { id = "m1", title = "A", items = { orphan } },
            },
        })
        Store.load(function(name)
            if name == "separator" then return {} end
        end)
        Store.renameMenu("m1", "B")
        assert.same(orphan, b.stored.menus.m1.items[1])
    end)
end)
