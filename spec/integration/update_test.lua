local H = require("harness").setup()
local test, eq = H.test, H.eq
local Archiver = require("ffi/archiver")
local lfs = require("libs/libkoreader-lfs")
local Update = require("minimenu/update")
local UpdateUI = require("minimenu/ui/update")
local ffiutil = require("ffi/util")

local HOME = os.getenv("KO_HOME")
local SOURCE = os.getenv("MINIMENU_DIR")
local PLUGINS = HOME .. "/plugins-x"
local COPY = PLUGINS .. "/minimenu.koplugin"
local WORK = PLUGINS .. "/.minimenu-update"
local BUILD = HOME .. "/build"
local ZIP = HOME .. "/release.zip"

local function sh(cmd)
    local status = os.execute(cmd)
    assert(status == 0 or status == true, cmd)
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    return data
end

local function write(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function export(parent, version)
    sh(("rm -rf %q && mkdir -p %q"):format(parent, parent))
    sh(("git -C %q archive --prefix=minimenu.koplugin/ HEAD | tar -x -C %q"):format(SOURCE, parent))
    write(parent .. "/minimenu.koplugin/_meta.lua", ('return { version = "%s" }\n'):format(version))
    return parent .. "/minimenu.koplugin"
end

local function resetCopy()
    sh(("chmod -R u+w %q 2>/dev/null; true"):format(PLUGINS))
    export(PLUGINS, "1.0.0")
    write(COPY .. "/marker", "old")
end

-- Writer:addFileFromMemory gives entries mode 0204 (a decimal 0644), so
-- entries are added from files on disk.
local function stage(root, version)
    os.remove(ZIP)
    local writer = Archiver.Writer:new()
    assert(writer:open(ZIP, "zip"))
    writer:addPath(root, export(BUILD, version), true)
    assert(not writer.err, writer.err)
    writer:close()
    return read(ZIP)
end

local function assertUnchanged()
    eq("1.0.0", Update.installedVersion(COPY), "version")
    eq("old", read(COPY .. "/marker"), "marker")
    eq(nil, lfs.attributes(WORK, "mode"), "work folder")
end

test("installs a release over the copy", function()
    resetCopy()
    local ok, err = Update.install(stage("minimenu.koplugin", "9.9.9"), COPY, "9.9.9")
    eq(true, ok, tostring(err))
    eq("9.9.9", Update.installedVersion(COPY))
    eq(nil, lfs.attributes(COPY .. "/marker", "mode"), "old files")
    eq("file", lfs.attributes(COPY .. "/minimenu/api.lua", "mode"))
    eq(nil, lfs.attributes(WORK, "mode"), "work folder")
end)

test("rejects a package whose version isn't the release's", function()
    resetCopy()
    eq(nil, Update.install(stage("minimenu.koplugin", "9.9.8"), COPY, "9.9.9"))
    assertUnchanged()
end)

test("leaves the copy alone when the plugins folder can't be written", function()
    resetCopy()
    local data = stage("minimenu.koplugin", "9.9.9")
    sh(("chmod a-w %q"):format(PLUGINS))
    local ok = Update.install(data, COPY, "9.9.9")
    sh(("chmod u+w %q"):format(PLUGINS))
    eq(nil, ok)
    assertUnchanged()
end)

local function installFailingRenames(data, fails)
    local rename, calls = os.rename, 0
    rawset(os, "rename", function(a, b)
        calls = calls + 1
        if fails(calls) then return nil, "refused" end
        return rename(a, b)
    end)
    local ok, result, err = pcall(Update.install, data, COPY, "9.9.9")
    rawset(os, "rename", rename)
    if not ok then error(result, 0) end
    return result, err
end

test("rolls back when the new copy can't be moved in", function()
    resetCopy()
    local data = stage("minimenu.koplugin", "9.9.9")
    local ok = installFailingRenames(data, function(n)
        return n == 2
    end)
    eq(nil, ok)
    assertUnchanged()
end)

test("names the old copy when the rollback fails too", function()
    resetCopy()
    local data = stage("minimenu.koplugin", "9.9.9")
    local ok, err = installFailingRenames(data, function(n)
        return n >= 2
    end)
    eq(nil, ok)
    eq("the previous version is in " .. WORK .. "/previous", err)
    eq(nil, lfs.attributes(COPY, "mode"), "copy")
    eq("old", read(WORK .. "/previous/marker"))
end)

local function shown(pred)
    for _, w in ipairs(H.UIManager._window_stack) do
        if pred(w.widget) then return w.widget end
    end
end

local function message(text)
    return shown(function(w)
        return w.text == text
    end)
end

-- Trapper polls its subprocess on scheduled tasks, so let real time pass.
local function waitFor(pred)
    local deadline = os.time() + 10
    while true do
        local found = pred()
        if found then return found end
        assert(os.time() < deadline, "timed out")
        ffiutil.usleep(20000)
        H.drain(1)
    end
end

local ASSET =
    { version = "9.9.9", url = "https://example.invalid/minimenu.koplugin.zip", sha256 = "x", notes = "notes" }

local function withStubs(stubs, fn)
    local restarted
    local restores = {}
    local function patch(t, k, v)
        local old = t[k]
        rawset(t, k, v)
        table.insert(restores, function()
            rawset(t, k, old)
        end)
    end
    patch(Update, "pluginDir", function()
        return COPY
    end)
    patch(Update, "fetchLatest", stubs.fetchLatest)
    patch(Update, "download", stubs.download)
    patch(require("ui/network/manager"), "runWhenConnected", function(_, callback)
        callback()
    end)
    patch(H.UIManager, "askForRestart", function(_, text)
        restarted = text
    end)
    local ok, err = pcall(fn, function()
        return restarted
    end)
    for _, restore in ipairs(restores) do
        restore()
    end
    for i = #H.UIManager._window_stack, 1, -1 do
        H.UIManager:close(H.UIManager._window_stack[i].widget)
    end
    H.drain()
    if not ok then error(err, 0) end
end

local function offered()
    return shown(function(w)
        return w.title == "MiniMenu v9.9.9"
    end)
end

test("checks and downloads in a subprocess and installs here", function()
    resetCopy()
    local data = stage("minimenu.koplugin", "9.9.9")
    local in_child = false
    withStubs({
        fetchLatest = function()
            in_child = true
            return ASSET
        end,
        download = function(asset)
            in_child = true
            eq(ASSET.url, asset.url)
            return data
        end,
    }, function(restarted)
        UpdateUI.check()
        H.tapButton("Update", waitFor(offered))
        waitFor(restarted)
        eq(false, in_child, "ran in KOReader's process")
        eq("MiniMenu was updated to v9.9.9.", restarted())
        eq("9.9.9", Update.installedVersion(COPY))
        eq(nil, message("Downloading…"), "message")
    end)
end)

test("reports a failed check", function()
    resetCopy()
    withStubs({
        fetchLatest = function()
            return nil, "HTTP 403"
        end,
    }, function()
        UpdateUI.check()
        waitFor(function()
            return message("Couldn't check for updates (HTTP 403).")
        end)
        eq(nil, message("Checking for updates…"), "message")
    end)
end)

test("reports a failed download and keeps the copy", function()
    resetCopy()
    withStubs({
        fetchLatest = function()
            return ASSET
        end,
        download = function()
            error("boom")
        end,
    }, function(restarted)
        UpdateUI.check()
        H.tapButton("Update", waitFor(offered))
        waitFor(function()
            return shown(function(w)
                return type(w.text) == "string" and w.text:match("^MiniMenu couldn't be updated %(.*boom%)%.$")
            end)
        end)
        eq(nil, restarted())
        assertUnchanged()
    end)
end)

test("tapping the message cancels the check quietly", function()
    resetCopy()
    withStubs({
        fetchLatest = function()
            ffiutil.sleep(30)
            return ASSET
        end,
    }, function()
        UpdateUI.check()
        local busy = waitFor(function()
            return message("Checking for updates…")
        end)
        H.drain()
        local d = busy.movable.dimen
        H.tap(d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2))
        eq(nil, message("Checking for updates…"), "message")
        ffiutil.usleep(300000)
        H.drain()
        eq(0, #H.UIManager._window_stack, "dialogs")
    end)
end)

test("treats the harness's symlinked copy as a dev install", function()
    resetCopy()
    eq(true, Update.isDevInstall(Update.pluginDir()))
    eq(false, Update.isDevInstall(COPY))
    lfs.mkdir(COPY .. "/.git")
    eq(true, Update.isDevInstall(COPY))
end)

test("says so when it can't find its own folder", function()
    local pluginDir = Update.pluginDir
    ---@diagnostic disable-next-line: duplicate-set-field
    Update.pluginDir = function() end
    local ok, err = pcall(require("minimenu/ui/update").check)
    Update.pluginDir = pluginDir
    eq(true, ok, tostring(err))
    H.drain()
    local top = H.top()
    eq(true, type(top.text) == "string" and top.text:find("plugin folder not found", 1, true) ~= nil, top.text)
    H.UIManager:close(top)
    H.drain()
end)

sh(("rm -rf %q %q %q"):format(PLUGINS, BUILD, ZIP))
H.finish()
