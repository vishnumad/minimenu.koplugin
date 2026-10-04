--[[--
Icon picker. Only Private Use Area glyphs from KOReader's bundled symbols
font are offered: other emoji render as tofu. "[icon=NAME]" can be typed in
for KOReader's image icons.
]]

local _ = require("gettext")

local IconPicker = {}

IconPicker.GLYPHS = {
    0xF015, 0xF02D, 0xF02E, 0xF0CA, 0xF03A, 0xF005, 0xF004, 0xF02B,
    0xF013, 0xF1DE, 0xF0AD, 0xF0E4, 0xF1EB, 0xF186, 0xF185, 0xF0EB,
    0xF0E7, 0xF011, 0xF021, 0xF01E, 0xF0E2, 0xF1DA, 0xF017, 0xF073,
    0xF002, 0xF0B0, 0xF07B, 0xF07C, 0xF0C9, 0xF0C1, 0xF12E, 0xF1E6,
    0xF15B, 0xF0F6, 0xF1C1, 0xF1C6, 0xF0C5, 0xF0EA, 0xF0C7, 0xF1F8,
    0xF080, 0xF201, 0xF091, 0xF0AC, 0xF0E0, 0xF1D8, 0xF0C2, 0xF0ED,
    0xF0EE, 0xF019, 0xF093, 0xF120, 0xF121, 0xF108, 0xF10B, 0xF030,
    0xF03E, 0xF001, 0xF028, 0xF240, 0xF242, 0xF0F3, 0xF023, 0xF09C,
    0xF06E, 0xF070, 0xF040, 0xF031, 0xF034, 0xF036, 0xF0D0, 0xF0F4,
    0xF135, 0xF1B2, 0xF06B, 0xF0A1, 0xF0EC, 0xF074, 0xF0E8, 0xF1E0,
    0xF14E, 0xF041, 0xF059, 0xF05A, 0xF071, 0xF00C, 0xF067, 0xF04B,
}

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end
IconPicker.utf8char = utf8char

--- Accepts "F1EB", "U+F1EB", a glyph, or "[icon=name]".
function IconPicker.parse(text)
    local Util = require("minimenu/util")
    text = Util.trim(text or "")
    if text == "" then return nil end
    if Util.iconName(text) or Util.isGlyph(text) then return text end
    local hex = text:match("^[Uu]%+(%x+)$") or text:match("^0?[xX]?(%x+)$")
    local cp = hex and tonumber(hex, 16)
    if cp then
        local glyph = utf8char(cp)
        if Util.isGlyph(glyph) then return glyph end
    end
end

--- callback(icon): a glyph or "[icon=…]", false for the kind's default, or
-- nil when cancelled.
function IconPicker.pick(callback)
    local Dialogs = require("minimenu/ui/dialogs")
    local choices = {}
    for _i, cp in ipairs(IconPicker.GLYPHS) do
        local g = utf8char(cp)
        table.insert(choices, { text = g, value = g })
    end
    Dialogs.choose({
        title = _("Choose an icon"),
        choices = choices,
        per_row = 8,
        rows_per_page = 6,
        on_cancel = function() callback(nil) end,
        extra_rows = { {
            { text = _("Default"), callback = function() callback(false) end },
            { text = _("Custom…"), callback = function()
                Dialogs.input({
                    title = _("Custom icon"),
                    hint = "F1EB",
                    description = _("A Private Use Area codepoint in hex (for example F1EB), or [icon=name] for a KOReader icon."),
                }, function(text)
                    local icon = IconPicker.parse(text)
                    if icon then callback(icon) else
                        Dialogs.info(_("Not a usable icon."))
                        callback(nil)
                    end
                end)
            end },
        } },
    }, callback)
end

return IconPicker
