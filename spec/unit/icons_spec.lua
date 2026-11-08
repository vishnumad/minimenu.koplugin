local IconPicker = require("minimenu/ui/pickers/icons")
local Index = require("minimenu/icons/index")
local Util = require("minimenu/util")

describe("icon index", function()
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
