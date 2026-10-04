--[[--
Persistent store, shared by every plugin instance through package.loaded.

backend = { read = function() → table|nil, write = function(data) }
]]

local model = require("minimenu/model")

local Store = {
    data = nil,
    backend = nil,
    listeners = {},
    -- migrations[n] is a pure function(data) → data from version n to n + 1.
    migrations = {},
    CURRENT_VERSION = model.SCHEMA_VERSION,
}

Store.DEFAULT_OPTIONS = {
    position = "gesture",
    show_title = true,
    hide_unavailable = true,
    lock = false,
}

Store.POSITIONS = { "gesture", "center", "top_left", "top_right", "bottom_left", "bottom_right", "top", "bottom" }

-- Global "font_size" setting; rows and icons scale with it.
Store.DEFAULT_FONT_SIZE = 20

local function log(level, ...)
    local ok, logger = pcall(require, "logger")
    if ok and logger and logger[level] then logger[level]("MiniMenu:", ...) end
end

function Store.fileBackend(path)
    if not path then
        local DataStorage = require("datastorage")
        path = DataStorage:getSettingsDir() .. "/minimenu.lua"
    end
    local LuaSettings = require("luasettings")
    local settings
    return {
        path = path,
        read = function()
            settings = LuaSettings:open(path)
            if next(settings.data) == nil then return nil end
            return settings.data
        end,
        write = function(data)
            settings = settings or LuaSettings:open(path)
            settings.data = data
            settings:flush()
        end,
    }
end

function Store.memoryBackend(initial)
    local b = { stored = initial, writes = 0 }
    b.read = function() return b.stored end
    b.write = function(data)
        b.stored = model.deepcopy(data)
        b.writes = b.writes + 1
    end
    return b
end

function Store.setBackend(backend)
    Store.backend = backend
    Store.data = nil
end

--- Returns data, changed
function Store.migrate(data)
    local changed = false
    if type(data) ~= "table" then return data, false end
    local version = type(data.version) == "number" and data.version or Store.CURRENT_VERSION
    while version < Store.CURRENT_VERSION do
        local step = Store.migrations[version]
        if not step then
            log("warn", "no migration from schema version", version)
            break
        end
        data = step(data)
        version = version + 1
        data.version = version
        changed = true
    end
    if version > Store.CURRENT_VERSION then
        log("warn", "settings use a newer schema version", version, "than this MiniMenu", Store.CURRENT_VERSION)
    end
    return data, changed
end

--- Load, migrate and sanitise; writes back only if something changed.
-- `kinds` is a function(name) → provider|nil. `seed` is called when no
-- settings exist yet, to create the starting menus.
function Store.load(kinds, seed)
    Store.kinds = kinds or Store.kinds
    if not Store.backend then Store.backend = Store.fileBackend() end
    local ok, raw = pcall(Store.backend.read)
    if not ok then
        log("err", "could not read settings:", raw)
        raw = nil
    end
    local data, changed
    if type(raw) ~= "table" then
        data, changed = model.empty(), false
        -- Never seed over a file we failed to read.
        if ok and raw == nil and seed then
            Store.data = data
            local seeded, err = pcall(seed)
            if not seeded then log("err", "could not create the default menu:", err) end
            return data
        end
    else
        local migrated
        data, migrated = Store.migrate(raw)
        local sanitized
        data, sanitized = model.sanitize(data, Store.kinds)
        changed = migrated or sanitized
    end
    Store.data = data
    if changed then Store.save() end
    return data
end

function Store.get()
    return Store.data or Store.load()
end

function Store.save()
    if not Store.data then return end
    local ok, err = pcall(Store.backend.write, Store.data)
    -- A failed write is retried on the next FlushSettings.
    Store.dirty = not ok
    if not ok then log("err", "could not save settings:", err) end
end

--- Listeners get one event per change: { type = "...", menu_id = ..., ... }
function Store.subscribe(fn)
    table.insert(Store.listeners, fn)
    return function()
        for i, f in ipairs(Store.listeners) do
            if f == fn then table.remove(Store.listeners, i) return end
        end
    end
end

function Store.emit(event)
    for _, fn in ipairs({ unpack(Store.listeners) }) do
        local ok, err = pcall(fn, event)
        if not ok then log("err", "listener failed:", err) end
    end
end

--- Ids are never reused: next_id only grows.
function Store.issueId(prefix)
    local data = Store.get()
    local id = prefix .. data.next_id
    data.next_id = data.next_id + 1
    return id
end

function Store.issueItemId()
    return Store.issueId("i")
end

function Store.menu(id)
    local data = Store.get()
    return id and data.menus[id]
end

--- Menus in display order.
function Store.menus()
    local data = Store.get()
    local out = {}
    for _, id in ipairs(data.menu_order) do
        if data.menus[id] then table.insert(out, data.menus[id]) end
    end
    return out
end

function Store.option(menu, key)
    local v = menu and menu.options and menu.options[key]
    if v ~= nil then return v end
    return Store.DEFAULT_OPTIONS[key]
end

function Store.options(menu)
    local out = {}
    for k in pairs(Store.DEFAULT_OPTIONS) do out[k] = Store.option(menu, k) end
    return out
end

function Store.setting(key)
    local data = Store.get()
    return data.settings and data.settings[key]
end

function Store.setSetting(key, value)
    local data = Store.get()
    data.settings = data.settings or {}
    data.settings[key] = value
    Store.save()
    Store.emit({ type = "settings_changed", key = key })
end

--- `fields` overrides the new menu's fields before listeners hear of it.
function Store.createMenu(title, items, fields)
    local data = Store.get()
    local id = Store.issueId("m")
    local menu = {
        id = id,
        title = title,
        register_action = true,
        options = {},
        items = items or {},
    }
    for k, v in pairs(fields or {}) do menu[k] = v end
    data.menus[id] = menu
    table.insert(data.menu_order, id)
    Store.save()
    Store.emit({ type = "menu_created", menu_id = id })
    return menu
end

function Store.renameMenu(id, title)
    local menu = Store.menu(id)
    if not menu or menu.title == title then return false end
    menu.title = title
    Store.save()
    Store.emit({ type = "menu_renamed", menu_id = id })
    return true
end

function Store.deleteMenu(id)
    local data = Store.get()
    local menu = data.menus[id]
    if not menu then return false end
    data.menus[id] = nil
    for i, mid in ipairs(data.menu_order) do
        if mid == id then table.remove(data.menu_order, i) break end
    end
    Store.save()
    Store.emit({ type = "menu_deleted", menu_id = id, menu = menu })
    return true
end

function Store.setRegisterAction(id, value)
    local menu = Store.menu(id)
    if not menu then return end
    menu.register_action = value and true or false
    Store.save()
    Store.emit({ type = "menu_action_changed", menu_id = id })
end

function Store.setOption(id, key, value)
    local menu = Store.menu(id)
    if not menu then return end
    menu.options = menu.options or {}
    menu.options[key] = value
    Store.save()
    Store.emit({ type = "menu_changed", menu_id = id, key = key })
end

function Store.duplicateMenu(id, title)
    local src = Store.menu(id)
    if not src then return nil end
    local items = {}
    for i, item in ipairs(src.items) do
        items[i] = model.cloneItem(item, Store.issueItemId)
    end
    return Store.createMenu(title or src.title, items, {
        options = model.deepcopy(src.options or {}),
        register_action = src.register_action ~= false,
    })
end

--- fn(items, menu) edits the tree in place and returns truthy if it changed
-- anything; its results are returned.
function Store.editItems(menu_id, fn)
    local menu = Store.menu(menu_id)
    if not menu then return nil end
    local result = { fn(menu.items, menu) }
    if result[1] then
        Store.save()
        Store.emit({ type = "items_changed", menu_id = menu_id })
    end
    return unpack(result)
end

--- Searches every menu when `menu_id` is nil.
-- Returns menu, item, list, index, ancestors
function Store.findItem(item_id, menu_id)
    if menu_id then
        local menu = Store.menu(menu_id)
        if not menu then return nil end
        local item, list, index, ancestors = model.find(menu.items, item_id)
        if item then return menu, item, list, index, ancestors end
        return nil
    end
    for _, menu in ipairs(Store.menus()) do
        local item, list, index, ancestors = model.find(menu.items, item_id)
        if item then return menu, item, list, index, ancestors end
    end
end

--- Save and notify after changing an item's fields in place.
function Store.itemChanged(menu_id)
    Store.save()
    Store.emit({ type = "items_changed", menu_id = menu_id })
end

return Store
