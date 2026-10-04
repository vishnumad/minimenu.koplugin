--[[--
Icon picker: a paged grid of glyphs from KOReader's bundled symbols font,
browsed by category or searched by name, plus image icons from the user's
icons folder and KOReader's own set. Long-press an icon to see its name.
]]

local Index = require("minimenu/icons/index")
local Util = require("minimenu/util")
local _ = require("gettext")
local T = require("ffi/util").template

local IconPicker = {}

--- Accepts "F1EB", "U+F1EB", a glyph, or "[icon=name]".
function IconPicker.parse(text)
    text = Util.trim(text or "")
    if text == "" then return nil end
    if Util.iconName(text) or Util.isGlyph(text) then return text end
    local hex = text:match("^[Uu]%+(%x+)$") or text:match("^0?[xX]?(%x+)$")
    local cp = hex and tonumber(hex, 16)
    if cp then
        local glyph = Util.utf8char(cp)
        if Util.isGlyph(glyph) then return glyph end
    end
end

local function imageDirs()
    local DataStorage = require("datastorage")
    return { DataStorage:getDataDir() .. "/icons", "resources/icons/mdlight" }
end

local function views()
    local out = {}
    for _i, c in ipairs(Index.CATEGORIES) do
        table.insert(out, {
            title = c.title,
            entries = function()
                return Index.category(c.key)
            end,
        })
    end
    table.insert(out, {
        title = _("Image icons"),
        entries = function()
            return Index.images(imageDirs())
        end,
    })
    table.insert(out, { title = _("All glyphs"), entries = Index.all })
    return out
end

local last_view

-- Glyphs preview at least as large as menu rows show them. Rows shrink to
-- leave room for the title and the two rows of buttons below the grid.
local function gridLayout()
    local Screen = require("device").screen
    local pt = math.max(26, require("minimenu/ui/popup").iconPoints())
    local cell_h = Screen:scaleBySize(pt * 2)
    local max_rows = Screen:getWidth() > Screen:getHeight() and 4 or 7
    local fit = math.floor((Screen:getHeight() * 0.85 - 3 * Screen:scaleBySize(52)) / cell_h)
    return { cols = 6, rows = math.max(2, math.min(max_rows, fit)), pt = pt, cell_h = cell_h }
end

--- callback(icon): a glyph or "[icon=…]", false for the kind's default, or
-- nil when cancelled.
function IconPicker.pick(callback)
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Dialogs = require("minimenu/ui/dialogs")
    local Screen = require("device").screen
    local all_views = views()
    local view = last_view or all_views[1]
    local entries = view.entries()
    local page = 1
    local dialog

    local show
    local function close()
        UIManager:close(dialog)
        dialog = nil
    end
    local function setView(v, list)
        view, entries, page = v, list or v.entries(), 1
        if not list then last_view = v end
        show()
    end

    local function chooseCategory()
        local choices = {}
        for _i, v in ipairs(all_views) do
            table.insert(choices, { text = v.title, value = v })
        end
        Dialogs.choose({ title = _("Icon category"), choices = choices, on_cancel = show }, setView)
    end

    local function search()
        Dialogs.input({
            title = _("Search icons"),
            hint = _("book open"),
            ok_text = _("Search"),
            on_cancel = show,
        }, function(text)
            local found = Index.search(text)
            if #found == 0 then
                Dialogs.info(T(_('No icons match "%1".'), Util.trim(text)), 2)
                show()
                return
            end
            setView({ title = T(_('"%1"'), Util.trim(text)) }, found)
        end)
    end

    local function custom()
        Dialogs.input({
            title = _("Custom icon"),
            hint = "F1EB",
            description = _(
                "A Private Use Area codepoint in hex (for example F1EB), or [icon=name] for an icon in koreader/icons."
            ),
            on_cancel = show,
        }, function(text)
            local icon = IconPicker.parse(text)
            if icon then
                callback(icon)
            else
                Dialogs.info(_("Not a usable icon."))
                show()
            end
        end)
    end

    show = function()
        local grid = gridLayout()
        local cols, rows = grid.cols, grid.rows
        local per_page = cols * rows
        local pages = math.max(1, math.ceil(#entries / per_page))
        local icon_size = Screen:scaleBySize(grid.pt)
        local buttons = {}
        for r = 1, rows do
            local row = {}
            for c = 1, cols do
                local e = entries[(page - 1) * per_page + (r - 1) * cols + c]
                if not e then
                    table.insert(row, { text = " ", height = grid.cell_h, enabled = false, callback = function() end })
                else
                    local b = {
                        height = grid.cell_h,
                        callback = function()
                            close()
                            callback(e.icon)
                        end,
                        hold_callback = function()
                            local Notification = require("ui/widget/notification")
                            UIManager:show(Notification:new { text = e.name, timeout = 3 })
                        end,
                    }
                    if e.image then
                        b.icon, b.icon_width, b.icon_height, b.alpha = Util.iconName(e.icon), icon_size, icon_size, true
                    else
                        b.text, b.font_size, b.font_bold = e.icon, grid.pt, false
                    end
                    table.insert(row, b)
                end
            end
            table.insert(buttons, row)
        end
        if #entries == 0 then
            buttons[1] = {
                { text = _("No icons here."), height = grid.cell_h, enabled = false, callback = function() end },
            }
        end
        local function turn(delta)
            return function()
                page = page + delta
                close()
                show()
            end
        end
        table.insert(buttons, {
            { text = "\u{25C1}", enabled = page > 1, callback = turn(-1) },
            {
                text = _("Categories"),
                callback = function()
                    close()
                    chooseCategory()
                end,
            },
            {
                text = _("Search"),
                callback = function()
                    close()
                    search()
                end,
            },
            { text = "\u{25B7}", enabled = page < pages, callback = turn(1) },
        })
        table.insert(buttons, {
            {
                text = _("Default"),
                callback = function()
                    close()
                    callback(false)
                end,
            },
            {
                text = _("Custom…"),
                callback = function()
                    close()
                    custom()
                end,
            },
        })
        local title = view.title
        if pages > 1 then title = T("%1 · %2 / %3", view.title, page, pages) end
        dialog = ButtonDialog:new {
            title = title,
            title_align = "center",
            buttons = buttons,
            tap_close_callback = function()
                callback(nil)
            end,
        }
        UIManager:show(dialog)
    end

    show()
end

return IconPicker
