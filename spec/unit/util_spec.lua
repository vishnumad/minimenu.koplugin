local Util = require("minimenu/util")

-- Lua 5.1 has no \u{} escapes: encode by hand.
local function u(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

describe("util", function()
    it("splits a leading PUA glyph off a label", function()
        local icon, rest = Util.splitLeadingIcon(u(0xF1EB) .. " Wi-Fi")
        assert.equal(u(0xF1EB) .. "", icon)
        assert.equal("Wi-Fi", rest)
        icon, rest = Util.splitLeadingIcon("Plain")
        assert.is_nil(icon)
        assert.equal("Plain", rest)
        icon, rest = Util.splitLeadingIcon(u(0xE000))
        assert.is_nil(icon)
        assert.equal(u(0xE000), rest)
        icon, rest = Util.splitLeadingIcon("é accent")
        assert.is_nil(icon)
    end)

    it("recognises glyphs and icon names", function()
        assert.is_true(Util.isGlyph(u(0xF07B)))
        assert.is_true(Util.isGlyph(u(0xF8FF)))
        assert.is_false(Util.isGlyph(u(0xF900)))
        assert.is_false(Util.isGlyph("ab"))
        assert.equal("appbar.settings", Util.iconName("[icon=appbar.settings]"))
        assert.is_nil(Util.iconName("appbar.settings"))
    end)
end)
