local Defaults = require("minimenu/defaults")
local Util = require("minimenu/util")

local function counter()
    local n = 0
    return function()
        n = n + 1
        return "i" .. n
    end, function()
        return n
    end
end

describe("default menu", function()
    local function check(items, supported, ids)
        for i, it in ipairs(items) do
            assert.is_nil(ids[it.id])
            ids[it.id] = true
            if it.kind == "dispatcher" then
                assert.is_true(supported(next(it.data.action)))
            elseif it.kind == "folder" then
                assert.is_true(#it.data.items > 0)
                check(it.data.items, supported, ids)
            elseif it.kind == "separator" then
                assert(i > 1 and i < #items, "separator at an end")
                assert.are_not.equal("separator", items[i - 1].kind)
            end
        end
    end

    it("keeps only supported actions, with fresh ids and no empty folders or stray separators", function()
        for _, known in ipairs({ {}, { filemanager = true, exit = true }, { suspend = true, poweroff = true } }) do
            local supported = function(name)
                return known[name] == true
            end
            check(Defaults.build(counter(), supported), supported, {})
        end
        local items = Defaults.build(counter(), function(name)
            return name == "suspend"
        end)
        assert.equal("suspend", next(items[#items].data.action))
    end)

    it("keeps the reader-only folder out of the file browser", function()
        local items = Defaults.build(counter(), function()
            return true
        end)
        for _, it in ipairs(items) do
            if it.kind == "folder" and it.label == "Go to ..." then
                assert.equal("reader", it.scope)
                return
            end
        end
        error("no Go to folder")
    end)

    it("validates", function()
        local Kinds = require("minimenu/kinds/init")
        Kinds.registerBuiltins()
        local model = require("minimenu/model")
        local issue, count = counter()
        local items = Defaults.build(issue, function()
            return true
        end)
        local data = {
            version = 1,
            next_id = count() + 1,
            menu_order = { "m0" },
            menus = { m0 = { id = "m0", title = "x", items = items } },
        }
        local _, changed = model.sanitize(data, Kinds.get)
        assert.is_false(changed)
    end)

    it("uses glyph icons, and folders keep the folder icon", function()
        local function walk(list)
            for _, it in ipairs(list) do
                if it.kind == "folder" then
                    assert.is_nil(it.icon)
                    walk(it.data.items)
                elseif it.kind ~= "separator" then
                    assert(Util.isGlyph(it.icon), it.label or it.kind)
                end
            end
        end
        walk(Defaults.build(counter(), function()
            return true
        end))
    end)
end)
