local Kinds = require("minimenu/kinds/init")

describe("kinds", function()
    setup(function()
        Kinds.registerBuiltins()
    end)

    it("registers the built-in kinds, sorted for the picker", function()
        local names = {}
        for _, p in ipairs(Kinds.list()) do
            table.insert(names, p.name)
        end
        assert.same({ "dispatcher", "menu_item", "plugin", "folder", "menu_link", "separator" }, names)
    end)

    it("rejects malformed providers", function()
        assert.is_false((Kinds.register({})))
        assert.is_false((Kinds.register({ name = "x" })))
        assert.is_true((Kinds.register({ name = "x", resolve = function() end })))
        Kinds.unregister("x")
        assert.is_nil(Kinds.get("x"))
    end)

    local cases = {
        dispatcher = {
            good = {
                { action = { toggle_wifi = true } },
                { action = { a = true, b = 2, settings = { order = { "a", "b" } } } },
            },
            bad = { {}, { action = {} }, { action = { settings = {} } }, { action = "x" } },
        },
        menu_item = {
            good = { { path = { { id = "setting" }, { text = "Wi-Fi" } } }, { path = { { id = "x" } }, page = true } },
            bad = { {}, { path = {} }, { path = { {} } }, { path = { "str" } } },
        },
        plugin = {
            good = { { name = "statistics" }, { name = "x", entry = "y", doc_only = true } },
            bad = { {}, { name = "" }, { name = 3 } },
        },
        folder = { good = { { items = {} } }, bad = { {}, { items = "x" } } },
        menu_link = { good = { { menu = "m1" } }, bad = { {}, { menu = 1 } } },
        separator = { good = { {} }, bad = {} },
    }
    it("validates each built-in kind's data", function()
        for kind, c in pairs(cases) do
            local p = Kinds.get(kind)
            for i, d in ipairs(c.good) do
                assert(p.validate(d), kind .. " good " .. i)
            end
            for i, d in ipairs(c.bad) do
                assert(not p.validate(d), kind .. " bad " .. i)
            end
        end
    end)
end)
