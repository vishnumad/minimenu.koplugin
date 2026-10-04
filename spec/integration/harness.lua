--[[--
Integration harness: runs MiniMenu inside a real (headless) KOReader.

Run through spec/integration/run.sh, which sets KO_HOME to a scratch dir and
starts the emulator's luajit from the KOReader build dir.
]]

local H = {}

local PLUGIN_DIR = os.getenv("MINIMENU_DIR")
local HOME = os.getenv("KO_HOME")
H.shots = HOME .. "/shots"

function H.setup()
    require("setupkoenv")
    package.path = "spec/front/unit/?.lua;" .. package.path
    require("commonrequire")
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(HOME .. "/settings")
    lfs.mkdir(H.shots)
    lfs.mkdir(HOME .. "/books")
    lfs.mkdir(HOME .. "/plugins")
    -- Expose the plugin through extra_plugin_paths (a symlink in KO_HOME).
    os.execute(("ln -sfn %q %q"):format(PLUGIN_DIR, HOME .. "/plugins/minimenu.koplugin"))
    for _, f in ipairs({ "juliet.epub", "sample.pdf" }) do
        os.execute(("cp --update=none spec/front/unit/data/%s %q"):format(f, HOME .. "/books/"))
    end
    G_reader_settings:saveSetting("extra_plugin_paths", { HOME .. "/plugins" })
    -- autosuspend reschedules itself on every input, and those tasks pile up
    -- under fastforward_ui_events until each tap takes seconds.
    local disabled = { autosuspend = true }
    for name in (os.getenv("KO_PLUGINS_DISABLED") or ""):gmatch("[^,%s]+") do
        disabled[name] = true
    end
    G_reader_settings:saveSetting("plugins_disabled", disabled)
    local PluginLoader = require("pluginloader")
    PluginLoader.enabled_plugins = nil
    PluginLoader:loadPlugins()
    H.UIManager = require("ui/uimanager")
    H.Screen = require("device").screen
    H.Geom = require("ui/geometry")
    H.Event = require("ui/event")
    H.Store = require("minimenu/store")
    -- Every test file starts from an empty store, not the first-install one
    -- (H.firstInstall gives that).
    H.settings_file = HOME .. "/settings/minimenu.lua"
    os.remove(H.settings_file)
    os.remove(H.settings_file .. ".old")
    H.Store.setBackend(H.Store.fileBackend(H.settings_file))
    H.Store.backend.write(require("minimenu/model").empty())
    H.API = require("minimenu/api")
    H.API.ensure()
    return H
end

--- Drop all settings and load the store again, as on a fresh install.
function H.firstInstall()
    os.remove(H.settings_file)
    os.remove(H.settings_file .. ".old")
    H.Store.setBackend(H.Store.fileBackend(H.settings_file))
    H.API.ensure()
end

function H.books(name)
    return HOME .. "/books/" .. name
end

function H.drain(n)
    for _ = 1, n or 3 do
        fastforward_ui_events()
    end
end

function H.fm()
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then return FileManager.instance end
    local fm = FileManager:new { dimen = H.Screen:getSize(), root_path = HOME .. "/books" }
    H.UIManager:show(fm)
    H.drain()
    return fm
end

function H.closeFM()
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:onClose()
        H.drain()
    end
end

function H.reader(file)
    local ReaderUI = require("apps/reader/readerui")
    local DocumentRegistry = require("document/documentregistry")
    H.closeFM()
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
        H.drain()
    end
    local reader = ReaderUI:new {
        dimen = H.Screen:getSize(),
        document = DocumentRegistry:openDocument(H.books(file)),
    }
    H.UIManager:show(reader)
    H.drain()
    return reader
end

function H.closeReader()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:onClose()
        H.drain()
    end
end

local function gesture(kind, x, y, extra)
    local ges = { ges = kind, pos = H.Geom:new { x = x, y = y, w = 0, h = 0 }, time = require("ui/time").now() }
    for k, v in pairs(extra or {}) do
        ges[k] = v
    end
    return ges
end
H.gesture = gesture

function H.tap(x, y)
    H.UIManager:sendEvent(H.Event:new("Gesture", gesture("tap", x, y)))
    H.drain()
end

function H.hold(x, y)
    H.UIManager:sendEvent(H.Event:new("Gesture", gesture("hold", x, y)))
    H.UIManager:sendEvent(H.Event:new("Gesture", gesture("hold_release", x, y)))
    H.drain()
end

function H.swipe(x, y, direction)
    H.UIManager:sendEvent(H.Event:new("Gesture", gesture("swipe", x, y, { direction = direction, distance = 100 })))
    H.drain()
end

function H.key(name)
    local Key = require("device/key")
    H.UIManager:sendEvent(H.Event:new("KeyPress", Key:new(name, {})))
    H.drain()
end

--- Repaint everything and save a PNG.
function H.shot(name)
    H.UIManager:setDirty("all", "full")
    H.drain(1)
    local path = H.shots .. "/" .. name .. ".png"
    H.Screen:shot(path)
    return path
end

function H.top()
    return H.UIManager:getTopmostVisibleWidget() or H.UIManager._window_stack[#H.UIManager._window_stack].widget
end

function H.button(widget, text)
    local bt = widget.buttontable or widget.button_table
    for _, line in ipairs(bt.buttons_layout) do
        for _, b in ipairs(line) do
            if b.text == text then return b end
        end
    end
    error("no button " .. text)
end

function H.tapButton(text, widget)
    local d = H.button(widget or H.top(), text).dimen
    H.tap(d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2))
end

-- The keyboard sits above an InputDialog on the window stack.
function H.inputDialog()
    for i = #H.UIManager._window_stack, 1, -1 do
        local w = H.UIManager._window_stack[i].widget
        if w.getInputText then return w end
    end
end

function H.popup()
    return H.API.current
end

--- Center of row `i` in panel `k` of the open popup.
function H.rowCenter(k, i)
    local r = H.popup().chain[k].panel:rowRect(i)
    assert(r, ("no row %d on panel %d's page"):format(i, k))
    return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2)
end

function H.rowLabels(k)
    local out = {}
    for _, row in ipairs(H.popup().chain[k].panel.rows) do
        table.insert(
            out,
            row.separator and "--"
                or row.placeholder and ("<" .. row.label .. ">")
                or (row.dim and ("(" .. row.label .. ")") or row.label)
        )
    end
    return out
end

--- Find a row index by label in panel k.
function H.rowIndex(k, label)
    for i, row in ipairs(H.popup().chain[k].panel.rows) do
        if row.label == label then return i end
    end
end

-- Tiny test runner -------------------------------------------------------

local results = { pass = 0, fail = 0, failures = {} }

function H.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        results.pass = results.pass + 1
        io.stdout:write("  ok   ", name, "\n")
    else
        results.fail = results.fail + 1
        table.insert(results.failures, { name = name, err = err })
        io.stdout:write("  FAIL ", name, "\n", err, "\n")
    end
    pcall(H.API.close)
    H.drain()
end

function H.eq(expected, actual, msg)
    local function ser(v)
        if type(v) ~= "table" then return tostring(v) end
        local parts = {}
        for i, x in ipairs(v) do
            parts[i] = ser(x)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    if ser(expected) ~= ser(actual) then
        error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", ser(expected), ser(actual)), 2)
    end
end

function H.finish()
    io.stdout:write(("\n%d passed, %d failed\n"):format(results.pass, results.fail))
    os.exit(results.fail == 0 and 0 or 1)
end

return H
