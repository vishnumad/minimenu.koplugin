--[[--
Item kind registry. A kind is a provider table:
    { name, title, order, pick, validate, resolve, action }
Only `name` and `resolve` are required; kinds without `pick` can't be added
from the UI. `action = true` marks kinds that do something when tapped:
their resolve gives a `run`, or `children` for a menu that opens beside the
row. They can be a row's second action (`item.secondary = { kind, data,
icon }`), and an item's action can be changed to any of them.
]]

local logger = require("logger")

local Kinds = {
    providers = {},
}

--- Registers or replaces a kind. Returns true, or false and a reason.
function Kinds.register(provider)
    if type(provider) ~= "table" then return false, "provider must be a table" end
    if type(provider.name) ~= "string" or provider.name == "" then
        return false, "provider.name must be a non-empty string"
    end
    if type(provider.resolve) ~= "function" then return false, "provider.resolve must be a function" end
    if Kinds.providers[provider.name] and Kinds.providers[provider.name] ~= provider then
        logger.warn("MiniMenu: replacing item kind", provider.name)
    end
    Kinds.providers[provider.name] = provider
    return true
end

function Kinds.unregister(name)
    Kinds.providers[name] = nil
end

function Kinds.get(name)
    return Kinds.providers[name]
end

--- Kinds the user can add, sorted by order. `filter(provider)` narrows them.
function Kinds.list(filter)
    local out = {}
    for _, p in pairs(Kinds.providers) do
        if p.pick and (not filter or filter(p)) then table.insert(out, p) end
    end
    table.sort(out, function(a, b)
        local oa, ob = a.order or 1000, b.order or 1000
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return out
end

function Kinds.registerBuiltins()
    if Kinds.builtins_registered then return end
    for _, name in ipairs({ "separator", "dispatcher", "menu_item", "plugin", "folder", "menu_link" }) do
        Kinds.register(require("minimenu/kinds/" .. name))
    end
    Kinds.builtins_registered = true
end

return Kinds
