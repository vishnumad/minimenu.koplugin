--[[--
Item kind registry. A kind is a provider table:
    { name, title, order, pick, validate, resolve, describe }
Only `name` and `resolve` are required; kinds without `pick` can't be added
from the UI.
]]

local Kinds = {
    providers = {},
}

local function logWarn(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.warn("MiniMenu:", ...) end
end

--- Registers or replaces a kind. Returns true, or false and a reason.
function Kinds.register(provider)
    if type(provider) ~= "table" then return false, "provider must be a table" end
    if type(provider.name) ~= "string" or provider.name == "" then
        return false, "provider.name must be a non-empty string"
    end
    if type(provider.resolve) ~= "function" then return false, "provider.resolve must be a function" end
    if Kinds.providers[provider.name] and Kinds.providers[provider.name] ~= provider then
        logWarn("replacing item kind", provider.name)
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

--- Kinds the user can add, sorted by order.
function Kinds.list()
    local out = {}
    for _, p in pairs(Kinds.providers) do
        if p.pick then table.insert(out, p) end
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
        local ok, provider = pcall(require, "minimenu/kinds/" .. name)
        if ok then
            Kinds.register(provider)
        else
            logWarn("could not load kind", name, provider)
        end
    end
    Kinds.builtins_registered = true
end

return Kinds
