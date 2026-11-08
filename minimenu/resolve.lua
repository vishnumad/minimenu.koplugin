--[[--
Turns stored items into the rows a panel shows:
    { label, icon, available, disabled, checked, children, run, keep_open,
      separator, title, menu_id, dim, placeholder, item, secondary }

`available = false`: can't run in this context; hidden or dimmed per the
menu's hide_unavailable. `disabled = true`: greyed out right now (e.g. "Go
back" with no history); always dimmed, so rows don't come and go.
`secondary` is the row's second action, { label, icon, available, disabled,
run, keep_open, children, title, menu_id, dim }, hidden or dimmed the same way.
`kinds` is a function(name) → provider.
]]

local Util = require("minimenu/util")
local logger = require("logger")

local Resolve = {}

Resolve.GEAR = "\u{F013}" -- cog

--- nil when the item is out of scope or its kind isn't installed.
function Resolve.item(item, ctx, kinds)
    if item.scope and item.scope ~= ctx.name then return nil end
    local provider = kinds(item.kind)
    if not provider then return nil end
    local ok, row = pcall(provider.resolve, item, ctx)
    if not ok or type(row) ~= "table" then
        logger.err("MiniMenu: resolving", item.kind, "item", item.id, "failed:", row)
        row = { label = item.label or item.kind, available = false }
    end
    if row.available == nil then row.available = true end
    if item.label and item.label ~= "" and not row.separator then row.label = item.label end
    if item.icon and item.icon ~= "" then row.icon = item.icon end
    row.label = row.label or ""
    row.item = item
    if not row.separator then row.secondary = Resolve.secondary(item, ctx, kinds) end
    return row
end

--- nil when the item has no second action or its kind can't be one.
function Resolve.secondary(item, ctx, kinds)
    local s = item.secondary
    if type(s) ~= "table" then return nil end
    local provider = kinds(s.kind)
    if not (provider and provider.action) then return nil end
    local ok, res = pcall(provider.resolve, { id = item.id, kind = s.kind, data = s.data }, ctx)
    if not ok or type(res) ~= "table" then
        logger.err("MiniMenu: resolving the second action of item", item.id, "failed:", res)
        res = { available = false }
    end
    return {
        label = res.label,
        icon = (s.icon and s.icon ~= "") and s.icon or Resolve.GEAR,
        available = res.available ~= false,
        disabled = res.disabled,
        run = res.run,
        keep_open = res.keep_open,
        children = res.children,
        title = res.title,
        menu_id = res.menu_id,
    }
end

local function settleSecondary(row, opts)
    local s = row.secondary
    if not s then return end
    if not s.available and opts.hide_unavailable then
        row.secondary = nil
    elseif not s.available or s.disabled then
        s.dim = true
    end
end

--- Editor view of an item, whatever its scope.
-- Returns { label, icon, available, missing, orphan, separator }
function Resolve.inspect(item, ctx, kinds)
    local provider = kinds(item.kind)
    if not provider then
        return { label = item.label or item.kind, icon = item.icon, available = false, orphan = true }
    end
    local ok, row = pcall(provider.resolve, item, ctx)
    if not ok or type(row) ~= "table" then row = { available = false } end
    local label = (item.label and item.label ~= "") and item.label or row.label or item.kind
    return {
        label = label,
        icon = (item.icon and item.icon ~= "") and item.icon or row.icon,
        available = row.available ~= false,
        missing = row.missing,
        separator = row.separator,
    }
end

--- opts.placeholder labels the inert row shown when no rows are left.
function Resolve.rows(items, ctx, kinds, opts)
    opts = opts or {}
    local rows = {}
    for _, item in ipairs(items or {}) do
        local row = Resolve.item(item, ctx, kinds)
        if row and (row.separator or row.available or not opts.hide_unavailable) then
            settleSecondary(row, opts)
            if not row.separator and (not row.available or row.disabled) then row.dim = true end
            table.insert(rows, row)
        end
    end
    rows = Util.tidySeparators(rows, function(row)
        return row.separator
    end)
    if #rows == 0 then
        table.insert(rows, { placeholder = true, label = opts.placeholder or "", available = false, dim = true })
    end
    return rows
end

function Resolve.actionable(row)
    return row and not row.separator and not row.placeholder and not row.dim
end

return Resolve
