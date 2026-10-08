local H = require("harness").setup()
local test, eq = H.test, H.eq
local Archiver = require("ffi/archiver")
local lfs = require("libs/libkoreader-lfs")
local Update = require("minimenu/update")

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

test("treats the harness's symlinked copy as a dev install", function()
    resetCopy()
    eq(true, Update.isDevInstall(Update.pluginDir()))
    eq(false, Update.isDevInstall(COPY))
    lfs.mkdir(COPY .. "/.git")
    eq(true, Update.isDevInstall(COPY))
end)

sh(("rm -rf %q %q %q"):format(PLUGINS, BUILD, ZIP))
H.finish()
