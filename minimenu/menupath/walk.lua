--[[--
Pure walker over KOReader TouchMenu item tables. A `tab_item_table` is an
array of tabs, each an array of items. Item functions belong to other
modules and plugins, so they are always called under pcall.

A path is an array of segments `{ id = … }` or `{ text = … }`. An id segment
may also carry the text it had when captured, for display only.
]]

local Walk = {}

local function pcallValue(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil, v
end

function Walk.text(node)
    if type(node) ~= "table" then return nil end
    if type(node.text_func) == "function" then
        local t = pcallValue(node.text_func)
        if type(t) == "string" then return t end
    end
    if type(node.text) == "string" then return node.text end
end

--- Returns list|nil, err
function Walk.children(node)
    if type(node) ~= "table" then return nil end
    if type(node.sub_item_table) == "table" then return node.sub_item_table end
    if type(node.sub_item_table_func) == "function" then
        local t, err = pcallValue(node.sub_item_table_func)
        if type(t) == "table" then return t end
        return nil, err or "sub_item_table_func returned no table"
    end
end

function Walk.isSubmenu(node)
    return type(node) == "table"
        and (type(node.sub_item_table) == "table" or type(node.sub_item_table_func) == "function")
end

--- A tab (depth 1) is itself the list of its items.
function Walk.childrenAt(node, depth)
    if depth == 1 then return node end
    return Walk.children(node)
end

function Walk.callback(node)
    if type(node) ~= "table" then return nil end
    if type(node.callback_func) == "function" then
        local cb = pcallValue(node.callback_func)
        if type(cb) == "function" then return cb end
    end
    if type(node.callback) == "function" then return node.callback end
end

function Walk.isLeaf(node)
    return type(node) == "table"
        and not Walk.isSubmenu(node)
        and (type(node.callback) == "function" or type(node.callback_func) == "function")
end

function Walk.enabled(node)
    if type(node) ~= "table" then return false end
    if node.enabled == false then return false end
    if type(node.enabled_func) == "function" then
        local ok, v = pcall(node.enabled_func)
        if ok and v == false then return false end
    end
    return true
end

--- true/false for toggles, nil otherwise.
function Walk.checked(node)
    if type(node) ~= "table" then return nil end
    if type(node.checked_func) == "function" then
        local ok, v = pcall(node.checked_func)
        if ok then return v and true or false end
        return nil
    end
    if node.checked ~= nil then return node.checked and true or false end
end

function Walk.isToggle(node)
    return type(node) == "table" and (type(node.checked_func) == "function" or node.checked ~= nil)
end

--- "Items per page: 14" → "Items per page"
function Walk.prefix(text)
    return (text:match("^[^%d:]*"):gsub("[%s%p]+$", ""))
end

function Walk.segment(node)
    local text = Walk.text(node)
    if type(node.id) == "string" and node.id ~= "" then return { id = node.id, text = text } end
    if text then return { text = text } end
end

local function matches(node, seg)
    if type(node) ~= "table" then return false end
    if seg.id then return node.id == seg.id end
    if seg.text then return Walk.text(node) == seg.text end
    return false
end

function Walk.findChild(list, seg)
    if type(list) ~= "table" then return nil end
    for _, node in ipairs(list) do
        if matches(node, seg) then return node end
    end
    -- A label that shows a value ("Items per page: 14") still matches after the value changes.
    if seg.id or not seg.text then return nil end
    local prefix = Walk.prefix(seg.text)
    if prefix == "" then return nil end
    local found
    for _, node in ipairs(list) do
        local text = Walk.text(node)
        if text and Walk.prefix(text) == prefix then
            if found then return nil end
            found = node
        end
    end
    return found
end

--- Returns node, or nil and "missing" | "error"
function Walk.resolve(tab_item_table, path)
    if type(tab_item_table) ~= "table" or type(path) ~= "table" or #path == 0 then return nil, "missing" end
    local list = tab_item_table
    local node
    for i, seg in ipairs(path) do
        node = Walk.findChild(list, seg)
        if not node then return nil, "missing" end
        if i < #path then
            local kids, err = Walk.childrenAt(node, i)
            if not kids then
                -- A submenu that failed to build is an error, not a missing entry.
                return nil, err and "error" or "missing"
            end
            list = kids
        end
    end
    return node
end

--- Rows for one level of the capture picker, skipping separators and
-- text-less items.
function Walk.captureList(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, node in ipairs(list) do
        local text = Walk.text(node)
        if type(node) == "table" and text and text ~= "" and text ~= "KOMenu:separator" then
            local seg = Walk.segment(node)
            if seg then
                table.insert(out, {
                    text = text,
                    node = node,
                    segment = seg,
                    submenu = Walk.isSubmenu(node),
                    leaf = Walk.isLeaf(node),
                    toggle = Walk.isToggle(node),
                })
            end
        end
    end
    return out
end

--- Tabs as capture rows. Tabs only have icons, so `names` labels them by id.
function Walk.tabList(tab_item_table, names)
    local out = {}
    if type(tab_item_table) ~= "table" then return out end
    for i, tab in ipairs(tab_item_table) do
        if type(tab) == "table" and #tab > 0 then
            local id = type(tab.id) == "string" and tab.id or nil
            local text = (names and id and names[id]) or id or tostring(i)
            table.insert(out, {
                text = text,
                node = tab,
                segment = id and { id = id, text = text } or { text = text },
                submenu = true,
            })
        end
    end
    return out
end

--- "Tools › More tools › Terminal"
function Walk.describe(path)
    local parts = {}
    for _, seg in ipairs(path or {}) do
        table.insert(parts, seg.text or seg.id or "?")
    end
    return table.concat(parts, " › ")
end

return Walk
