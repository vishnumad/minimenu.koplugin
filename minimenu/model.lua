--[[--
Pure tree operations on stored menus. Folders hold their children in
`item.data.items`. Trees are walked with explicit stacks rather than
recursion, so folder depth is unbounded.
]]

local M = {}

M.FOLDER = "folder"
M.SCHEMA_VERSION = 1

--- Deep copy of plain data. Shared subtables are copied once.
function M.deepcopy(value)
    if type(value) ~= "table" then return value end
    local seen = {}
    local root = {}
    seen[value] = root
    local stack = { value }
    while #stack > 0 do
        local src = table.remove(stack)
        local dst = seen[src]
        for k, v in pairs(src) do
            if type(v) == "table" then
                local copy = seen[v]
                if not copy then
                    copy = {}
                    seen[v] = copy
                    table.insert(stack, v)
                end
                dst[k] = copy
            else
                dst[k] = v
            end
        end
    end
    return root
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

--- Depth first, in display order. fn(item, list, index, depth, ancestors)
-- returning true stops the walk. `ancestors` (outermost first) is reused
-- between calls: copy it to keep it.
function M.walk(items, fn)
    if type(items) ~= "table" then return end
    local stack = { { list = items, i = 1, depth = 1 } }
    local ancestors = {}
    while #stack > 0 do
        local frame = stack[#stack]
        local item = frame.list[frame.i]
        if item == nil then
            table.remove(stack)
            table.remove(ancestors)
        else
            frame.i = frame.i + 1
            if fn(item, frame.list, frame.i - 1, frame.depth, ancestors) then return true end
            local kids = M.children(item)
            if kids then
                table.insert(ancestors, item)
                table.insert(stack, { list = kids, i = 1, depth = frame.depth + 1 })
            end
        end
    end
end

--- Returns item, list, index, ancestors (outermost first), or nil
function M.find(items, id)
    local found, flist, findex, fpath
    M.walk(items, function(item, list, index, _, ancestors)
        if item.id == id then
            found, flist, findex = item, list, index
            fpath = {}
            for i, a in ipairs(ancestors) do
                fpath[i] = a
            end
            return true
        end
    end)
    return found, flist, findex, fpath
end

--- nil → the top level, a folder id → that folder's children.
function M.listFor(items, folder_id)
    if not folder_id then return items end
    local folder = M.find(items, folder_id)
    return M.children(folder)
end

--- Returns the removed item, or nil.
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
    local skip_depth
    M.walk(items, function(item, _, _, depth)
        if skip_depth then
            if depth > skip_depth then return end
            skip_depth = nil
        end
        if item.id == exclude_id then
            skip_depth = depth
            return
        end
        if M.children(item) then table.insert(out, { item = item, depth = depth }) end
    end)
    return out
end

--- Deep copy with fresh ids from `issue()` for the item and its descendants.
function M.cloneItem(item, issue)
    local copy = M.deepcopy(item)
    copy.id = issue()
    M.walk(M.children(copy) or {}, function(it)
        it.id = issue()
    end)
    return copy
end

--- Ids of menus linked (at any depth) from `items`.
function M.linkedMenus(items, link_kind)
    local out = {}
    M.walk(items, function(item)
        if item.kind == link_kind and type(item.data) == "table" and type(item.data.menu) == "string" then
            out[item.data.menu] = true
        end
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

--[[--
Repair a store without mutating `input`. `kinds` is a function(name) →
provider|nil. Items of unregistered kinds are kept as they are; items that
fail their kind's `validate` are dropped. Duplicate ids are re-issued.

Returns clean, changed
]]
function M.sanitize(input, kinds)
    local changed = false
    local data
    if type(input) ~= "table" then return M.empty(), true end
    data = M.deepcopy(input)

    if type(data.version) ~= "number" then
        data.version = M.SCHEMA_VERSION
        changed = true
    end
    if type(data.menus) ~= "table" then
        data.menus = {}
        changed = true
    end
    if type(data.menu_order) ~= "table" then
        data.menu_order = {}
        changed = true
    end
    if data.settings ~= nil and type(data.settings) ~= "table" then
        data.settings = nil
        changed = true
    end

    local max_id = 0
    local function see(id)
        local n = idNumber(id)
        if n and n > max_id then max_id = n end
    end

    local menus = {}
    for key, menu in pairs(data.menus) do
        if type(menu) == "table" and type(menu.id) == "string" and menu.id == key then
            menus[key] = menu
            see(key)
        else
            changed = true
        end
    end
    data.menus = menus

    -- Drop missing and duplicate entries, then append unordered menus.
    local order, in_order = {}, {}
    for _, id in ipairs(data.menu_order) do
        if menus[id] and not in_order[id] then
            table.insert(order, id)
            in_order[id] = true
        else
            changed = true
        end
    end
    local missing = {}
    for id in pairs(menus) do
        if not in_order[id] then table.insert(missing, id) end
    end
    if #missing > 0 then
        table.sort(missing, function(a, b)
            return (idNumber(a) or 0) < (idNumber(b) or 0)
        end)
        for _, id in ipairs(missing) do
            table.insert(order, id)
        end
        changed = true
    end
    if #order ~= #data.menu_order then changed = true end
    data.menu_order = order

    -- Items are visited in a stable order so that the first of two
    -- duplicates always keeps its id.
    local seen_items = {}
    local dupes = {}
    for _, mid in ipairs(order) do
        local menu = menus[mid]
        if type(menu.title) ~= "string" then
            menu.title = mid
            changed = true
        end
        if menu.options ~= nil and type(menu.options) ~= "table" then
            menu.options = nil
            changed = true
        end
        if type(menu.items) ~= "table" then
            menu.items = {}
            changed = true
        end
        local stack = { menu.items }
        while #stack > 0 do
            local list = table.remove(stack)
            local kept = {}
            for _, item in ipairs(list) do
                local ok = type(item) == "table" and type(item.id) == "string" and type(item.kind) == "string"
                if ok and item.data ~= nil and type(item.data) ~= "table" then ok = false end
                if ok then
                    if item.data == nil then
                        item.data = {}
                        changed = true
                    end
                    local provider = kinds and kinds(item.kind)
                    if provider and provider.validate then
                        local valid = provider.validate(item.data)
                        if not valid then ok = false end
                    end
                end
                if ok then
                    table.insert(kept, item)
                    if seen_items[item.id] then
                        table.insert(dupes, item)
                    else
                        seen_items[item.id] = true
                    end
                    see(item.id)
                    local kids = M.children(item)
                    if kids then table.insert(stack, kids) end
                else
                    changed = true
                end
            end
            if #kept ~= #list then
                for i = #list, 1, -1 do
                    list[i] = nil
                end
                for i, v in ipairs(kept) do
                    list[i] = v
                end
            end
        end
    end

    local next_id = type(data.next_id) == "number" and data.next_id or 0
    if next_id <= max_id then
        next_id = max_id + 1
        changed = true
    end
    for _, item in ipairs(dupes) do
        item.id = "i" .. next_id
        next_id = next_id + 1
        changed = true
    end
    data.next_id = next_id

    return data, changed
end

return M
