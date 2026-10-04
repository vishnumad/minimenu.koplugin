--[[--
Icons the picker offers: named glyphs from KOReader's symbols font, and
image icons from the user's icons folder and KOReader's own set.
Entries are { name, icon } where icon is a glyph or "[icon=NAME]".
]]

local Util = require("minimenu/util")

local Index = {}

Index.CATEGORIES = require("minimenu/icons/categories")

local all
function Index.all()
    if not all then
        all = {}
        for i, e in ipairs(require("minimenu/icons/glyphs")) do
            all[i] = { name = e[1], icon = Util.utf8char(e[2]) }
        end
    end
    return all
end

local by_category = {}
function Index.category(key)
    if by_category[key] then return by_category[key] end
    local cat
    for _i, c in ipairs(Index.CATEGORIES) do
        if c.key == key then cat = c end
    end
    if not cat then return {} end
    local out, seen = {}, {}
    local function add(match)
        for _i, e in ipairs(Index.all()) do
            if not seen[e] and match(e.name) then
                seen[e] = true
                table.insert(out, e)
            end
        end
    end
    for _i, n in ipairs(cat.names or {}) do
        add(function(name)
            return name == n
        end)
    end
    for _i, p in ipairs(cat.prefixes) do
        add(function(name)
            return name:sub(1, #p) == p
        end)
    end
    by_category[key] = out
    return out
end

--- Glyphs whose name contains every word of `query`.
function Index.search(query)
    local terms = {}
    for t in (query or ""):lower():gmatch("%S+") do
        table.insert(terms, t)
    end
    local out = {}
    if #terms == 0 then return out end
    for _i, e in ipairs(Index.all()) do
        local hit = true
        for _j, t in ipairs(terms) do
            if not e.name:find(t, 1, true) then
                hit = false
                break
            end
        end
        if hit then table.insert(out, e) end
    end
    return out
end

--- Top-level .svg and .png files in `dirs`; earlier dirs win a name clash.
function Index.images(dirs)
    local lfs = require("libs/libkoreader-lfs")
    local out, seen = {}, {}
    for _i, dir in ipairs(dirs) do
        local found = {}
        if lfs.attributes(dir, "mode") == "directory" then
            pcall(function()
                for f in lfs.dir(dir) do
                    local name, ext = f:match("^([^.].*)%.(%a+)$")
                    ext = ext and ext:lower()
                    local icon = name and "[icon=" .. name .. "]"
                    if
                        (ext == "svg" or ext == "png")
                        and Util.iconName(icon)
                        and not seen[name]
                        and lfs.attributes(dir .. "/" .. f, "mode") == "file"
                    then
                        seen[name] = true
                        table.insert(found, { name = name, icon = icon, image = true })
                    end
                end
            end)
        end
        table.sort(found, function(a, b)
            return a.name:lower() < b.name:lower()
        end)
        for _j, e in ipairs(found) do
            table.insert(out, e)
        end
    end
    return out
end

return Index
