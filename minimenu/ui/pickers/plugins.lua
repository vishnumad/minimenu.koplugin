-- Lists every enabled plugin, not just those loaded in the current UI, so
-- reader-only plugins can be added from the file browser.

local UIManager = require("ui/uimanager")
local _ = require("gettext")

local PluginPicker = {}

--- Returns { { label, icon, data, here, reader_only }, … }
function PluginPicker.rows(ctx)
    local Plugin = require("minimenu/kinds/plugin")
    local Util = require("minimenu/util")
    local Walk = require("minimenu/menupath/walk")
    local PluginLoader = require("pluginloader")
    local enabled = PluginLoader:loadPlugins() or {}
    local rows = {}
    for _i, mod in ipairs(enabled) do
        if mod.name ~= "minimenu" then
            local instance = ctx.ui and ctx.ui[mod.name]
            if type(instance) == "table" then
                local entries = Plugin.entries(instance)
                local keys = {}
                for k, v in pairs(entries) do
                    if type(v) == "table" and Walk.text(v) then table.insert(keys, k) end
                end
                table.sort(keys)
                -- Plugins without a menu entry have nothing to launch.
                for _j, key in ipairs(keys) do
                    local icon, label = Util.splitLeadingIcon(Walk.text(entries[key]))
                    local data = { name = mod.name, doc_only = mod.is_doc_only and true or false }
                    if key ~= mod.name then data.entry = key end
                    if #keys > 1 then data.entry_text = label end
                    table.insert(rows, { label = label, icon = icon, data = data, here = true })
                end
            else
                table.insert(rows, {
                    label = mod.fullname or mod.name,
                    data = { name = mod.name, doc_only = mod.is_doc_only and true or false },
                    here = false,
                    reader_only = mod.is_doc_only and true or false,
                })
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.label:lower() < b.label:lower()
    end)
    return rows
end

function PluginPicker.pick(ctx, done)
    local Dialogs = require("minimenu/ui/dialogs")
    local chosen = false
    local items = {}
    for _i, row in ipairs(PluginPicker.rows(ctx)) do
        table.insert(items, {
            text = (row.icon and (row.icon .. "  ") or "") .. row.label,
            mandatory = row.reader_only and _("Reader only") or (not row.here and _("Not loaded here") or nil),
            callback = function(menu)
                chosen = true
                UIManager:close(menu)
                done(row.data, row.icon)
            end,
        })
    end
    Dialogs.list({
        title = _("Add plugin"),
        items = items,
        on_close = function()
            if not chosen then done(nil) end
        end,
    })
end

return PluginPicker
