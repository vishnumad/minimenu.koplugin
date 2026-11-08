local DispatchUtil = require("minimenu/dispatch")
local _ = require("gettext")

return {
    name = "dispatcher",
    title = _("KOReader action"),
    order = 10,
    action = true,

    pick = function(ctx, done)
        require("minimenu/ui/pickers/dispatcher").pick(ctx, function(action)
            done(action and { action = action })
        end)
    end,

    validate = function(data)
        if type(data) ~= "table" or type(data.action) ~= "table" then return false, "no action" end
        for k in pairs(data.action) do
            if k ~= "settings" then return true end
        end
        return false, "empty action"
    end,

    resolve = function(item)
        local action = item.data.action
        return {
            label = DispatchUtil.label(action),
            available = DispatchUtil.available(action),
            run = function()
                DispatchUtil.dispatcher():execute(action)
            end,
        }
    end,
}
