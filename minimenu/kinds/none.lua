-- An item whose main action was cleared: grayed out until one is added.

local _ = require("gettext")

return {
    name = "none",

    resolve = function()
        return { label = _("No action"), disabled = true }
    end,
}
