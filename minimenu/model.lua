--[[--
Pure tree operations on stored menus. Folders hold their children in
`item.data.items`.
]]

local M = {}

M.FOLDER = "folder"
M.SCHEMA_VERSION = 1

--- Deep copy of plain data.
function M.deepcopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = M.deepcopy(v)
    end
    return copy
end

function M.children(item)
    if
        type(item) == "table"
        and item.kind == M.FOLDER
        and type(item.data) == "table"
        and type(item.data.items) == "table"
    then
        return item.data.items
    end
end

--- Depth first, in display order. fn(item) returning true stops the walk.
function M.walk(items, fn)
    if type(items) ~= "table" then return end
    for _, item in ipairs(items) do
        if fn(item) then return true end
        if M.walk(M.children(item), fn) then return true end
    end
end

--- Returns item, list, index, ancestors (outermost first), or nil
function M.find(items, id)
    for i, item in ipairs(items) do
        if item.id == id then return item, items, i, {} end
        local kids = M.children(item)
        if kids then
            local found, list, index, ancestors = M.find(kids, id)
            if found then
                table.insert(ancestors, 1, item)
                return found, list, index, ancestors
            end
        end
    end
end

--- nil → the top level, a folder id → that folder's children.
function M.listFor(items, folder_id)
    if not folder_id then return items end
    local folder = M.find(items, folder_id)
    return M.children(folder)
end

function M.remove(items, id)
    local item, list, index = M.find(items, id)
    if not item then return nil end
    table.remove(list, index)
    return item
end

--- Move an item by `delta` within its own list. Returns true if it moved.
function M.move(items, id, delta)
    local item, list, index = M.find(items, id)
    if not item then return false end
    local target = index + delta
    if target < 1 or target > #list then return false end
    table.remove(list, index)
    table.insert(list, target, item)
    return true
end

function M.isSelfOrDescendant(item, target_id)
    if item.id == target_id then return true end
    local kids = M.children(item)
    if not kids then return false end
    return M.find(kids, target_id) ~= nil
end

--- Move an item to the end of a folder (the top level when folder_id is nil).
-- Returns true, or false and a reason
function M.moveTo(items, id, folder_id)
    local item = M.find(items, id)
    if not item then return false, "missing item" end
    if folder_id and M.isSelfOrDescendant(item, folder_id) then return false, "descendant" end
    local dest = M.listFor(items, folder_id)
    if not dest then return false, "missing folder" end
    M.remove(items, id)
    table.insert(dest, item)
    return true
end

--- Move an item out of its folder, to just after it.
function M.moveOut(items, id)
    local item, _, _, ancestors = M.find(items, id)
    if not item or #ancestors == 0 then return false end
    local folder = ancestors[#ancestors]
    M.remove(items, id)
    local _, plist, pindex = M.find(items, folder.id)
    table.insert(plist, pindex + 1, item)
    return true
end

--- { { item, depth }, … } for every folder, skipping `exclude_id` and its subtree.
function M.folders(items, exclude_id)
    local out = {}
    local function visit(list, depth)
        for _, item in ipairs(list) do
            local kids = M.children(item)
            if kids and item.id ~= exclude_id then
                table.insert(out, { item = item, depth = depth })
                visit(kids, depth + 1)
            end
        end
    end
    visit(items, 1)
    return out
end

--- Deep copy with fresh ids from `issue()` for the item and its descendants.
function M.cloneItem(item, issue)
    local copy = M.deepcopy(item)
    copy.id = issue()
    M.walk(M.children(copy), function(it)
        it.id = issue()
    end)
    return copy
end

--- Ids of menus linked (at any depth, second actions included) from `items`.
function M.linkedMenus(items, link_kind)
    local out = {}
    local function see(a)
        if type(a) == "table" and a.kind == link_kind and type(a.data) == "table" and type(a.data.menu) == "string" then
            out[a.data.menu] = true
        end
    end
    M.walk(items, function(item)
        see(item)
        see(item.secondary)
    end)
    return out
end

--- Would a link from menu `from_id` to `to_id` close a loop of links?
function M.linkCreatesCycle(data, from_id, to_id, link_kind)
    if from_id == to_id then return true end
    local seen = { [to_id] = true }
    local queue = { to_id }
    while #queue > 0 do
        local mid = table.remove(queue, 1)
        local menu = data.menus and data.menus[mid]
        if menu then
            for target in pairs(M.linkedMenus(menu.items, link_kind)) do
                if target == from_id then return true end
                if not seen[target] then
                    seen[target] = true
                    table.insert(queue, target)
                end
            end
        end
    end
    return false
end

local function idNumber(id)
    if type(id) ~= "string" then return nil end
    return tonumber(id:match("^[mi](%d+)$"))
end

function M.empty()
    return { version = M.SCHEMA_VERSION, next_id = 1, menu_order = {}, menus = {} }
end

-- `s` is the repair state shared by the steps of M.sanitize:
-- { kinds, changed, max_id, seen = { [item id] = true }, dupes = { item, … } }

local function noteId(s, id)
    local n = idNumber(id)
    if n and n > s.max_id then s.max_id = n end
end

local function repairTop(data, s)
    if type(data.version) ~= "number" then
        data.version = M.SCHEMA_VERSION
        s.changed = true
    end
    if type(data.menus) ~= "table" then
        data.menus = {}
        s.changed = true
    end
    if type(data.menu_order) ~= "table" then
        data.menu_order = {}
        s.changed = true
    end
    if data.settings ~= nil and type(data.settings) ~= "table" then
        data.settings = nil
        s.changed = true
    end
end

local function validMenus(menus, s)
    local out = {}
    for key, menu in pairs(menus) do
        if type(menu) == "table" and type(menu.id) == "string" and menu.id == key then
            out[key] = menu
            noteId(s, key)
        else
            s.changed = true
        end
    end
    return out
end

--- Drops missing and duplicate entries, then appends unlisted menus by id.
local function repairOrder(order, menus, s)
    local out, listed = {}, {}
    for _, id in ipairs(order) do
        if menus[id] and not listed[id] then
            table.insert(out, id)
            listed[id] = true
        else
            s.changed = true
        end
    end
    local unlisted = {}
    for id in pairs(menus) do
        if not listed[id] then table.insert(unlisted, id) end
    end
    table.sort(unlisted, function(a, b)
        return (idNumber(a) or 0) < (idNumber(b) or 0)
    end)
    for _, id in ipairs(unlisted) do
        table.insert(out, id)
        s.changed = true
    end
    return out
end

local function validSecondary(s, kinds)
    if type(s) ~= "table" or type(s.kind) ~= "string" or type(s.data) ~= "table" then return false end
    if s.icon ~= nil and type(s.icon) ~= "string" then return false end
    local provider = kinds and kinds(s.kind)
    return not (provider and provider.validate and not provider.validate(s.data))
end

--- Fixes what it can in `item`; false when the item must be dropped.
local function repairItem(item, s)
    if type(item) ~= "table" or type(item.id) ~= "string" or type(item.kind) ~= "string" then return false end
    if item.data == nil then
        item.data = {}
        s.changed = true
    elseif type(item.data) ~= "table" then
        return false
    end
    local provider = s.kinds and s.kinds(item.kind)
    if provider and provider.validate and not provider.validate(item.data) then return false end
    if item.secondary ~= nil and not validSecondary(item.secondary, s.kinds) then
        item.secondary = nil
        s.changed = true
    end
    return true
end

local function repairItems(list, s)
    local kept = {}
    for _, item in ipairs(list) do
        if repairItem(item, s) then
            table.insert(kept, item)
            if s.seen[item.id] then
                table.insert(s.dupes, item)
            else
                s.seen[item.id] = true
            end
            noteId(s, item.id)
            local kids = M.children(item)
            if kids then item.data.items = repairItems(kids, s) end
        else
            s.changed = true
        end
    end
    return kept
end

local function repairMenu(menu, s)
    if type(menu.title) ~= "string" then
        menu.title = menu.id
        s.changed = true
    end
    if menu.options ~= nil and type(menu.options) ~= "table" then
        menu.options = nil
        s.changed = true
    end
    if type(menu.items) ~= "table" then
        menu.items = {}
        s.changed = true
    end
    menu.items = repairItems(menu.items, s)
end

--- The first of two items with the same id, in display order, keeps it.
local function reissueDuplicates(data, s)
    local next_id = type(data.next_id) == "number" and data.next_id or 0
    if next_id <= s.max_id then
        next_id = s.max_id + 1
        s.changed = true
    end
    for _, item in ipairs(s.dupes) do
        item.id = "i" .. next_id
        next_id = next_id + 1
        s.changed = true
    end
    data.next_id = next_id
end

--[[--
Repair a store without mutating `input`. `kinds` is a function(name) →
provider|nil. Items of unregistered kinds are kept as they are; items that
fail their kind's `validate` are dropped, and so are second actions that
fail theirs (keeping the item). Duplicate ids are re-issued.

Returns clean, changed
]]
function M.sanitize(input, kinds)
    if type(input) ~= "table" then return M.empty(), true end
    local data = M.deepcopy(input)
    local s = { kinds = kinds, changed = false, max_id = 0, seen = {}, dupes = {} }
    repairTop(data, s)
    data.menus = validMenus(data.menus, s)
    data.menu_order = repairOrder(data.menu_order, data.menus, s)
    for _, id in ipairs(data.menu_order) do
        repairMenu(data.menus[id], s)
    end
    reissueDuplicates(data, s)
    return data, s.changed
end

return M
