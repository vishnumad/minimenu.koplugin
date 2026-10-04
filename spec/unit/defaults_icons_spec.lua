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
    it("builds fresh ids and drops unsupported actions, nested", function()
        local issue = counter()
        local known = { filemanager = true, exit = true, suspend = true }
        local items = Defaults.build(issue, function(name)
            return known[name]
        end)
        local kinds, ids = {}, {}
        local function walk(list)
            for _, it in ipairs(list) do
                table.insert(kinds, it.kind == "dispatcher" and next(it.data.action) or it.kind)
                assert.is_nil(ids[it.id])
                ids[it.id] = true
                if it.kind == "folder" then walk(it.data.items) end
            end
        end
        walk(items)
        assert.same({
            "folder",
            "menu_item",
            "menu_item",
            "separator",
            "menu_item",
            "menu_item",
            "menu_item",
            "menu_item",
            "filemanager",
            "separator",
            "menu_item",
            "menu_item",
            "menu_item",
            "folder",
            "exit",
            "suspend",
        }, kinds)
    end)

    it("drops empty folders and stray separators", function()
        local items = Defaults.build(counter(), function()
            return false
        end)
        local kinds = {}
        for _, it in ipairs(items) do
            table.insert(kinds, it.kind)
        end
        assert.same({ "folder", "menu_item", "separator", "menu_item", "menu_item", "menu_item" }, kinds)
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

describe("icon picker", function()
    it("offers only single PUA glyphs", function()
        for _, cp in ipairs(IconPicker.GLYPHS) do
            assert(Util.isGlyph(IconPicker.utf8char(cp)), string.format("%04X", cp))
        end
    end)

    it("parses custom input", function()
        assert.equal(IconPicker.utf8char(0xF1EB), IconPicker.parse("F1EB"))
        assert.equal(IconPicker.utf8char(0xF1EB), IconPicker.parse("U+f1eb"))
        assert.equal(IconPicker.utf8char(0xF1EB), IconPicker.parse(" 0xF1EB "))
        assert.equal("[icon=appbar.menu]", IconPicker.parse("[icon=appbar.menu]"))
        assert.is_nil(IconPicker.parse("41")) -- 'A' is not PUA
        assert.is_nil(IconPicker.parse(""))
        assert.is_nil(IconPicker.parse("hello"))
    end)
end)
