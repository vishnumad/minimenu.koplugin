local _ = require("gettext")

local LINK_ICON = "\u{F0C9}"

local function target(item)
    local Store = require("minimenu/store")
    return Store.menu(item.data.menu)
end

return {
    name = "menu_link",
    title = _("Link to another menu"),
    order = 50,

    pick = function(ctx, done)
        require("minimenu/ui/pickers/menus").pick({
            title = _("Link to menu"),
            exclude = ctx.menu_id,
            warn_cycle_from = ctx.menu_id,
        }, function(menu_id)
            if menu_id then
                done({ menu = menu_id })
            else
                done(nil)
            end
        end)
    end,

    validate = function(data)
        return type(data) == "table" and type(data.menu) == "string"
    end,

    resolve = function(item)
        local menu = target(item)
        if not menu then return { label = _("Missing menu"), icon = LINK_ICON, available = false } end
        return {
            label = menu.title,
            icon = LINK_ICON,
            available = true,
            title = menu.title,
            menu_id = menu.id,
            children = function()
                local m = target(item)
                return m and m.items or {}
            end,
        }
    end,

    describe = function(item)
        local menu = target(item)
        if not menu then return _("Missing menu") end
        return require("ffi/util").template(_("Opens: %1"), menu.title)
    end,
}
