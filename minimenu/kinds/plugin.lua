local _ = require("gettext")
local Util = require("minimenu/util")

local PLUGIN_ICON = "\u{F12E}"

local Plugin = {
    name = "plugin",
    title = _("Plugin"),
    order = 30,
}

function Plugin.module(name)
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok or not PluginLoader.enabled_plugins then return nil end
    for _i, p in ipairs(PluginLoader.enabled_plugins) do
        if p.name == name then return p end
    end
end

--- The entries a plugin instance adds to the main menu.
function Plugin.entries(instance)
    local scratch = {}
    if type(instance) ~= "table" or type(instance.addToMainMenu) ~= "function" then return scratch end
    local ok, err = pcall(instance.addToMainMenu, instance, scratch)
    if not ok then
        local lok, logger = pcall(require, "logger")
        if lok then logger.warn("MiniMenu: probing plugin menu failed:", err) end
    end
    return scratch
end

--- data.entry, else the entry named after the plugin, else the only entry.
function Plugin.pickEntry(entries, data)
    if data.entry and entries[data.entry] then return entries[data.entry] end
    if entries[data.name] then return entries[data.name] end
    local only, n = nil, 0
    for _k, v in pairs(entries) do
        if type(v) == "table" then only = v; n = n + 1 end
    end
    if n == 1 then return only end
end

function Plugin.pick(ctx, done)
    require("minimenu/ui/pickers/plugins").pick(ctx, function(data, icon)
        done(data, nil, icon)
    end)
end

function Plugin.validate(data)
    return type(data) == "table" and type(data.name) == "string" and data.name ~= ""
end

local function defaultLabel(data)
    if data.entry_text then return data.entry_text end
    local mod = Plugin.module(data.name)
    return mod and mod.fullname or data.name
end

function Plugin.resolve(item, ctx)
    local data = item.data
    local icon, label = Util.splitLeadingIcon(defaultLabel(data))
    local instance = ctx.ui and ctx.ui[data.name]
    return {
        label = label,
        icon = icon or PLUGIN_ICON,
        available = type(instance) == "table",
        run = function()
            local Live = require("minimenu/menupath/live")
            local Walk = require("minimenu/menupath/walk")
            local entry = Plugin.pickEntry(Plugin.entries(instance), data)
            if not entry then
                local lok, logger = pcall(require, "logger")
                if lok then logger.warn("MiniMenu: plugin has no menu entry:", data.name) end
                return
            end
            if Walk.isSubmenu(entry) then
                Live.openPage(entry)
            else
                Live.runLeaf(entry, ctx.ui)
            end
        end,
    }
end

function Plugin.describe(item)
    if item.data.doc_only then return _("Plugin · Reader only") end
    return _("Plugin")
end

return Plugin
