--[[--
Turns stored items into the rows a panel shows:
    { label, icon, available, disabled, checked, children, run, keep_open,
      separator, title, menu_id, dim, placeholder, item }

`available = false`: can't run in this context; hidden or dimmed per the
menu's hide_unavailable. `disabled = true`: greyed out right now (e.g. "Go
back" with no history); always dimmed, so rows don't come and go.
`kinds` is a function(name) → provider.
]]

local Resolve = {}

local function logErr(...)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.err("MiniMenu:", ...) end
end

--- nil when the item is out of scope or its kind isn't installed.
function Resolve.item(item, ctx, kinds)
    if item.scope and item.scope ~= ctx.name then return nil end
    local provider = kinds(item.kind)
    if not provider then return nil end
    local ok, row = pcall(provider.resolve, item, ctx)
    if not ok or type(row) ~= "table" then
        logErr("resolving", item.kind, "item", item.id, "failed:", row)
        row = { label = item.label or item.kind, available = false }
    end
    if row.available == nil then row.available = true end
    if item.label and item.label ~= "" and not row.separator then row.label = item.label end
    if item.icon and item.icon ~= "" then row.icon = item.icon end
    row.label = row.label or ""
    row.item = item
    return row
end

--- Editor view of an item, whatever its scope.
-- Returns { label, icon, available, orphan, separator }
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
        separator = row.separator,
    }
end

--- Drop separators that would be leading, trailing or doubled.
function Resolve.tidySeparators(rows)
    local out = {}
    for _, row in ipairs(rows) do
        if row.separator then
            if #out > 0 and not out[#out].separator then table.insert(out, row) end
        else
            table.insert(out, row)
        end
    end
    while #out > 0 and out[#out].separator do table.remove(out) end
    return out
end

--- opts.placeholder labels the inert row shown when no rows are left.
function Resolve.rows(items, ctx, kinds, opts)
    opts = opts or {}
    local rows = {}
    for _, item in ipairs(items or {}) do
        local row = Resolve.item(item, ctx, kinds)
        if row then
            if row.separator then
                table.insert(rows, row)
            elseif row.available and row.disabled then
                row.dim = true
                table.insert(rows, row)
            elseif row.available then
                table.insert(rows, row)
            elseif not opts.hide_unavailable then
                row.dim = true
                table.insert(rows, row)
            end
        end
    end
    rows = Resolve.tidySeparators(rows)
    if #rows == 0 then
        table.insert(rows, { placeholder = true, label = opts.placeholder or "", available = false, dim = true })
    end
    return rows
end

function Resolve.actionable(row)
    return row and not row.separator and not row.placeholder and not row.dim
end

return Resolve
