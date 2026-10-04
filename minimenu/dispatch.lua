--[[--
Dispatcher action metadata. KOReader keeps its action table (`settingsList`)
file-local, so it is found through the upvalues of Dispatcher methods. If
that fails, existence falls back to `getNameFromItem` and every action
counts as enabled.
]]

local DispatchUtil = {}

local injected_dispatcher, injected_list
local cached_list -- table, or false when lookup failed

function DispatchUtil.inject(dispatcher, list)
    injected_dispatcher, injected_list = dispatcher, list
    cached_list = nil
end

function DispatchUtil.dispatcher()
    if injected_dispatcher then return injected_dispatcher end
    return require("dispatcher")
end

local function findUpvalue(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    local i = 1
    while true do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
        i = i + 1
    end
end

function DispatchUtil.settingsList()
    if injected_list then return injected_list end
    if cached_list == nil then
        local Dispatcher = DispatchUtil.dispatcher()
        cached_list = false
        for _, fn in ipairs({ Dispatcher.registerAction, Dispatcher.getNameFromItem, Dispatcher.removeAction }) do
            local list = findUpvalue(fn, "settingsList")
            if type(list) == "table" then
                cached_list = list
                break
            end
        end
    end
    return cached_list or nil
end

--- Action names in a stored action table, in execution order.
function DispatchUtil.actionNames(action)
    local names = {}
    if type(action) ~= "table" then return names end
    local order = type(action.settings) == "table" and action.settings.order
    if type(order) == "table" and #order > 0 then
        for _, k in ipairs(order) do
            if action[k] ~= nil then table.insert(names, k) end
        end
        return names
    end
    for k in pairs(action) do
        if k ~= "settings" then table.insert(names, k) end
    end
    table.sort(names)
    return names
end

function DispatchUtil.exists(name)
    local list = DispatchUtil.settingsList()
    if list then return list[name] ~= nil end
    local Dispatcher = DispatchUtil.dispatcher()
    local ok, title = pcall(Dispatcher.getNameFromItem, Dispatcher, name)
    local _ = require("gettext")
    return ok and title ~= _("Unknown item")
end

--- Device-specific actions (Wi-Fi, frontlight…) stay registered on devices
-- without the feature, with `condition = false`.
function DispatchUtil.supported(name)
    if not DispatchUtil.exists(name) then return false end
    local list = DispatchUtil.settingsList()
    return not (list and list[name].condition == false)
end

--- Can every action in the table run in the current context?
-- Returns bool, reason ("unknown" | "disabled" | nil)
function DispatchUtil.available(action)
    local names = DispatchUtil.actionNames(action)
    if #names == 0 then return false, "unknown" end
    local Dispatcher = DispatchUtil.dispatcher()
    local list = DispatchUtil.settingsList()
    for _, name in ipairs(names) do
        if not DispatchUtil.exists(name) then return false, "unknown" end
        if list then
            local ok, enabled = pcall(Dispatcher.isActionEnabled, Dispatcher, list[name])
            if ok and not enabled then return false, "disabled" end
        end
    end
    return true
end

function DispatchUtil.readerOnly(action)
    local list = DispatchUtil.settingsList()
    for _, name in ipairs(DispatchUtil.actionNames(action)) do
        local e = list and list[name]
        if e and (e.reader or e.paging or e.rolling) then return true end
    end
    return false
end

function DispatchUtil.label(action)
    local Dispatcher = DispatchUtil.dispatcher()
    local names = DispatchUtil.actionNames(action)
    if #names == 1 then
        local ok, title = pcall(Dispatcher.getNameFromItem, Dispatcher, names[1], action)
        if ok and title then return title end
        return names[1]
    end
    local ok, text = pcall(Dispatcher.menuTextFunc, Dispatcher, action)
    if ok and text then return text end
    return table.concat(names, ", ")
end

return DispatchUtil
