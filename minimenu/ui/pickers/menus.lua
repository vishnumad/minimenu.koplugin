local _ = require("gettext")

local MenuPicker = {}

--[[--
opts:
    title
    exclude          menu id to leave out
    warn_cycle_from  menu id: ask before a link from it would close a loop
callback(menu_id|nil)
]]
function MenuPicker.pick(opts, callback)
    local Dialogs = require("minimenu/ui/dialogs")
    local Store = require("minimenu/store")
    local model = require("minimenu/model")
    local choices = {}
    for _i, menu in ipairs(Store.menus()) do
        if menu.id ~= opts.exclude then table.insert(choices, { text = menu.title, value = menu.id }) end
    end
    if #choices == 0 then
        Dialogs.info(_("There are no other menus yet."))
        return callback(nil)
    end
    Dialogs.choose({
        title = opts.title or _("Choose a menu"),
        choices = choices,
        on_cancel = function()
            callback(nil)
        end,
    }, function(menu_id)
        if opts.warn_cycle_from and model.linkCreatesCycle(Store.get(), opts.warn_cycle_from, menu_id, "menu_link") then
            local T = require("ffi/util").template
            local ConfirmBox = require("ui/widget/confirmbox")
            require("ui/uimanager"):show(ConfirmBox:new {
                text = T(
                    _(
                        "“%1” already leads back to this menu. Links can form a loop; each step still needs a tap.\n\nAdd the link anyway?"
                    ),
                    Store.menu(menu_id).title
                ),
                ok_text = _("Add link"),
                ok_callback = function()
                    callback(menu_id)
                end,
                cancel_callback = function()
                    callback(nil)
                end,
            })
            return
        end
        callback(menu_id)
    end)
end

return MenuPicker
