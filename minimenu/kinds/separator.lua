local _ = require("gettext")

return {
    name = "separator",
    title = _("Separator"),
    order = 60,

    pick = function(_ctx, done)
        done({})
    end,

    validate = function(data)
        return type(data) == "table"
    end,

    resolve = function()
        return { separator = true, available = true }
    end,

    describe = function()
        return _("Separator")
    end,
}
