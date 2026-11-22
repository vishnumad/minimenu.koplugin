--[[--
KOReader action picker: Dispatcher:addSubMenu's sections, where any number of
actions can be checked, then "Arrange actions" and Done. However it closes,
it returns the checked actions. With none checked, it returns false if it
started with some (they were cleared), or nil. Actions that no book can run
together must be changed first, or the pick is canceled.
]]

local _ = require("gettext")

local DispatcherPicker = {}

local MIXED_LAYOUTS = _(
    "These actions can't run together: some only work in reflowable books (EPUB, FB2…), others only in fixed-layout books (PDF, DjVu…)."
)

--- The rows to show from an addSubMenu table: the sections after its leading
-- "Nothing" row, then "Arrange actions", which addSubMenu adds right after
-- setting max_per_page. The rest of the tail sets how a gesture runs the
-- actions.
local function rows(menu)
    local out = {}
    local last = menu.max_per_page or #menu
    for i = 2, last do
        table.insert(out, menu[i])
    end
    out[#out].separator = true
    table.insert(out, menu[last + 1])
    return out
end

local function show(checked, current, done)
    local Dispatcher = require("dispatcher")
    local DispatchUtil = require("minimenu/dispatch")
    local Dialogs = require("minimenu/ui/dialogs")
    local Host = require("minimenu/menupath/host")
    local holder, menu = { pick = checked }, {}
    Dispatcher:addSubMenu({}, menu, holder, "pick")
    local shown = rows(menu)
    table.insert(shown, { text = _("Done"), callback = function() end })
    return Host.show(shown, {
        icon = "appbar.settings",
        on_close = function()
            local picked = holder.pick
            local any = picked and Dispatcher:_itemsCount(picked) > 0
            if any and DispatchUtil.mixesLayouts(picked) then
                Dialogs.confirm(MIXED_LAYOUTS, _("Change actions"), function()
                    show(picked, current, done)
                end, function()
                    done(nil)
                end)
            elseif any then
                done(picked)
            elseif current then
                done(false)
            else
                done(nil)
            end
        end,
    })
end

--- `ctx.data`, when given, is the item's current data: its actions start checked.
function DispatcherPicker.pick(ctx, done)
    local current = ctx.data and ctx.data.action
    return show(current and require("minimenu/model").deepcopy(current), current, done)
end

return DispatcherPicker
