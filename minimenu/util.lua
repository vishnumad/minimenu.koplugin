local Util = {}

--- Byte length of the Private Use Area codepoint starting at byte `i`, or nil.
function Util.puaLength(s, i)
    i = i or 1
    local b1, b2 = s:byte(i, i + 1)
    if not b1 then return nil end
    if b1 == 0xEE and b2 and b2 >= 0x80 and b2 <= 0xBF then return 3 end -- U+E000–U+EFFF
    if b1 == 0xEF and b2 and b2 >= 0x80 and b2 <= 0xA3 then return 3 end -- U+F000–U+F8FF
    if b1 == 0xF3 and b2 and b2 >= 0xB0 and b2 <= 0xBF then return 4 end -- U+F0000–U+FFFFF
    if b1 == 0xF4 and b2 and b2 >= 0x80 and b2 <= 0x8F then return 4 end -- U+100000–U+10FFFF
end

--- Split a leading PUA glyph (and the spaces after it) off a label.
-- Returns icon|nil, rest
function Util.splitLeadingIcon(text)
    if type(text) ~= "string" then return nil, text end
    local n = Util.puaLength(text, 1)
    if not n then return nil, text end
    local icon = text:sub(1, n)
    local rest = text:sub(n + 1):gsub("^[%s\194\160]+", "")
    if rest == "" then return nil, text end
    return icon, rest
end

function Util.isGlyph(s)
    if type(s) ~= "string" then return false end
    local n = Util.puaLength(s, 1)
    return n ~= nil and #s == n
end

--- "[icon=NAME]" → NAME, else nil.
function Util.iconName(s)
    if type(s) ~= "string" then return nil end
    return s:match("^%[icon=([%w%._%-]+)%]$")
end

function Util.utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(
        0xF0 + math.floor(cp / 0x40000),
        0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40,
        0x80 + cp % 0x40
    )
end

function Util.trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

return Util
