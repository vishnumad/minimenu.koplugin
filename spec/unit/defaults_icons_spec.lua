local Defaults = require("minimenu/defaults")
local IconPicker = require("minimenu/ui/pickers/icons")
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
end)

describe("dispatch supported", function()
    local DispatchUtil = require("minimenu/dispatch")
    after_each(function()
        DispatchUtil.inject(nil, nil)
    end)

    it("rejects unknown actions and ones this device can't use", function()
        DispatchUtil.inject({}, { toc = {}, toggle_wifi = { condition = false }, reboot = { condition = true } })
        assert.is_true(DispatchUtil.supported("toc"))
        assert.is_true(DispatchUtil.supported("reboot"))
        assert.is_false(DispatchUtil.supported("toggle_wifi"))
        assert.is_false(DispatchUtil.supported("nope"))
    end)
end)

describe("icon index", function()
    local Index = require("minimenu/icons/index")

    it("offers only single PUA glyphs with names", function()
        local seen = {}
        for _, e in ipairs(Index.all()) do
            assert(Util.isGlyph(e.icon), e.name)
            assert.is_nil(seen[e.name])
            seen[e.name] = true
        end
        assert.is_true(#Index.all() > 3000)
    end)

    it("fills every category, and every prefix matches", function()
        for _, cat in ipairs(Index.CATEGORIES) do
            assert(#Index.category(cat.key) > 0, cat.key)
            for _, p in ipairs(cat.prefixes) do
                local hit = false
                for _, e in ipairs(Index.all()) do
                    if e.name:sub(1, #p) == p then
                        hit = true
                        break
                    end
                end
                assert(hit, cat.key .. ": " .. p)
            end
            for _, n in ipairs(cat.names or {}) do
                assert(#Index.search(n) > 0, cat.key .. ": " .. n)
            end
        end
    end)

    it("searches by every word of the query", function()
        local names = {}
        for _, e in ipairs(Index.search("Book  Open")) do
            names[e.name] = true
            assert(e.name:find("book", 1, true) and e.name:find("open", 1, true), e.name)
        end
        assert.is_true(names["book-open-variant"])
        assert.same({}, Index.search("   "))
        assert.equal(1, #Index.search("u+f1eb"))
    end)

    it("default menu icons are glyphs, and folders keep the folder icon", function()
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

describe("icon picker", function()
    it("parses custom input", function()
        assert.equal(Util.utf8char(0xF1EB), IconPicker.parse("F1EB"))
        assert.equal(Util.utf8char(0xF1EB), IconPicker.parse("U+f1eb"))
        assert.equal(Util.utf8char(0xF1EB), IconPicker.parse(" 0xF1EB "))
        assert.equal("[icon=appbar.menu]", IconPicker.parse("[icon=appbar.menu]"))
        assert.is_nil(IconPicker.parse("41")) -- 'A' is not PUA
        assert.is_nil(IconPicker.parse(""))
        assert.is_nil(IconPicker.parse("hello"))
    end)
end)
