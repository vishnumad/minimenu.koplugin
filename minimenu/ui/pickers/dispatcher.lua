--[[--
KOReader action picker: shows Dispatcher:addSubMenu and returns the first
single action selected. Value actions (SpinWidget, radio lists) commit
asynchronously, so selection is checked on updateItems, which every commit
path calls.
]]

local UIManager = require("ui/uimanager")

local DispatcherPicker = {}

--- The section entries of an addSubMenu table: after the leading "Nothing"
-- row, up to max_per_page, which addSubMenu sets before its
-- arrange/execute/QuickMenu tail.
function DispatcherPicker.sections(menu)
    local out = {}
    local last = menu.max_per_page or #menu
    for i = 2, last do table.insert(out, menu[i]) end
    return out
end

function DispatcherPicker.pick(_ctx, done)
    local Dispatcher = require("dispatcher")
    local Host = require("minimenu/menupath/host")
    local model = require("minimenu/model")
    local holder, caller, menu = {}, {}, {}
    Dispatcher:addSubMenu(caller, menu, holder, "pick")
    local finished = false
    local tm
    tm = Host.show(DispatcherPicker.sections(menu), {
        icon = "appbar.settings",
        on_update = function()
            if finished or not holder.pick then return end
            if Dispatcher:_itemsCount(holder.pick) == 1 then
                finished = true
                local action = model.deepcopy(holder.pick)
                UIManager:nextTick(function()
                    tm:closeMenu()
                    done(action)
                end)
            end
        end,
        on_close = function()
            if not finished then
                finished = true
                done(nil)
            end
        end,
    })
    return tm
end

return DispatcherPicker
