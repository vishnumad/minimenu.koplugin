local Store = require("minimenu/store")
local Warm = require("minimenu/warm")

local function item(kind, data, fields)
    local it = { id = Store.issueItemId(), kind = kind, data = data }
    for k, v in pairs(fields or {}) do
        it[k] = v
    end
    return it
end

local function menuItem(fields)
    return item("menu_item", { path = { { id = "tools" } } }, fields)
end

local function link(menu_id)
    return item("menu_link", { menu = menu_id })
end

local function opens(menu_id)
    return { ["minimenu_open_" .. menu_id] = true }
end

local function ui(opts)
    opts = opts or {}
    return {
        document = opts.reader and {} or nil,
        gestures = { gestures = opts.gestures or {} },
        hotkeys = { hotkeys = opts.hotkeys },
        profiles = { data = opts.profiles or {} },
    }
end

local function needs(u, scope)
    return Warm.needsTree(Warm.roots(u, scope), scope)
end

describe("warm-up", function()
    before_each(function()
        Store.setBackend(Store.memoryBackend(nil))
        Store.listeners = {}
        Store.load()
        Warm.opened = { reader = {}, filemanager = {} }
    end)

    it("ignores menus that nothing opens, even with menu actions", function()
        Store.createMenu("Default", { menuItem() })
        assert.is_false(needs(ui(), "reader"))
    end)

    it("counts menus bound to a gesture, a hotkey or a profile", function()
        local m = Store.createMenu("M", { menuItem() })
        assert.is_true(needs(ui { gestures = { tap_top_left_corner = opens(m.id) } }, "filemanager"))
        assert.is_true(needs(ui { hotkeys = { alt_plus_m = opens(m.id) } }, "filemanager"))
        assert.is_true(needs(ui { profiles = { Night = opens(m.id) } }, "filemanager"))
    end)

    it("doesn't count a hotkeys plugin without hotkeys", function()
        Store.createMenu("M", { menuItem() })
        assert.is_false(needs(ui { hotkeys = nil }, "reader"))
    end)

    it("ignores a binding to a menu without an action", function()
        local m = Store.createMenu("M", { menuItem() }, { register_action = false })
        assert.is_false(needs(ui { gestures = { tap = opens(m.id) } }, "reader"))
    end)

    it("ignores menu actions scoped to the other context", function()
        local m = Store.createMenu("M", {
            menuItem { scope = "filemanager" },
            item("folder", { items = { menuItem() } }, { scope = "filemanager" }),
        })
        local u = ui { gestures = { tap = opens(m.id) } }
        assert.is_false(needs(u, "reader"))
        assert.is_true(needs(u, "filemanager"))
    end)

    it("finds a menu action inside a folder", function()
        local m = Store.createMenu("M", { item("folder", { items = { item("folder", { items = { menuItem() } }) } }) })
        assert.is_true(needs(ui { gestures = { tap = opens(m.id) } }, "reader"))
    end)

    it("follows links and actions that open other menus", function()
        local b = Store.createMenu("B", { menuItem() })
        local a = Store.createMenu("A", { link(b.id) })
        local c = Store.createMenu("C", { item("dispatcher", { action = opens(b.id) }) })
        assert.is_true(needs(ui { gestures = { tap = opens(a.id) } }, "reader"))
        assert.is_true(needs(ui { gestures = { tap = opens(c.id) } }, "reader"))
    end)

    it("stops on link cycles", function()
        local a = Store.createMenu("A")
        local b = Store.createMenu("B", { link(a.id) })
        table.insert(a.items, link(b.id))
        table.insert(a.items, item("dispatcher", { action = opens(a.id) }))
        assert.is_false(needs(ui { gestures = { tap = opens(a.id) } }, "reader"))
    end)

    it("ignores links to deleted menus", function()
        local gone = Store.createMenu("Gone", { menuItem() })
        local a = Store.createMenu("A", { link(gone.id) })
        Store.deleteMenu(gone.id)
        assert.is_false(needs(ui { gestures = { tap = opens(a.id), hold = opens(gone.id) } }, "reader"))
    end)

    it("counts menus opened this session, per context", function()
        local m = Store.createMenu("M", { menuItem() }, { register_action = false })
        Warm.noteOpened("reader", m.id)
        assert.is_true(needs(ui(), "reader"))
        assert.is_false(needs(ui(), "filemanager"))
    end)

    it("counts every menu with an action when a plugin's bindings can't be read", function()
        local m = Store.createMenu("M", { menuItem() })
        local hidden = Store.createMenu("Hidden", { menuItem() }, { register_action = false })
        local u = ui()
        u.gestures.gestures = nil
        assert.same({ [m.id] = true }, Warm.roots(u, "reader"))
        u.gestures = nil
        u.profiles.data = "changed"
        assert.same({ [m.id] = true }, Warm.roots(u, "reader"))
        assert.is_nil(Warm.roots(u, "reader")[hidden.id])
    end)

    it("doesn't count disabled plugins", function()
        Store.createMenu("M", { menuItem() })
        assert.is_false(needs({ document = {} }, "reader"))
    end)
end)
