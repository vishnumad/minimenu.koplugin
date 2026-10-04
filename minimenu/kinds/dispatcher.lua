local _ = require("gettext")

local function D() return require("minimenu/dispatch") end

return {
    name = "dispatcher",
    title = _("KOReader action"),
    order = 10,

    pick = function(ctx, done)
        require("minimenu/ui/pickers/dispatcher").pick(ctx, function(action)
            if action then done({ action = action }) else done(nil) end
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
        local DU = D()
        local action = item.data.action
        local available = DU.available(action)
        return {
            label = DU.label(action),
            available = available,
            run = function()
                DU.dispatcher():execute(action)
            end,
        }
    end,

    describe = function(item)
        local DU = D()
        local names = DU.actionNames(item.data.action)
        for _i, name in ipairs(names) do
            if not DU.exists(name) then
                return require("ffi/util").template(_("Unknown action: %1"), name)
            end
        end
        if DU.readerOnly(item.data.action) then return _("KOReader action · Reader only") end
        return _("KOReader action")
    end,
}
