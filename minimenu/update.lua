local logger = require("logger")

local Update = {}

local REPO = "vishnumad/minimenu.koplugin"
local ASSET = "minimenu.koplugin.zip"
local ROOT = "minimenu.koplugin"
local LATEST_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local USER_AGENT = "minimenu.koplugin"
local WORK = ".minimenu-update"

function Update.parseVersion(s)
    if type(s) ~= "string" then return nil end
    local major, minor, patch, rest = s:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major then return nil end
    local pre
    if rest ~= "" then
        pre = rest:match("^%-([0-9A-Za-z.]+)$")
        if not pre then return nil end
    end
    return { tonumber(major), tonumber(minor), tonumber(patch), pre = pre }
end

function Update.isNewer(latest, installed)
    latest = assert(Update.parseVersion(latest))
    installed = Update.parseVersion(installed) or { 0, 0, 0 }
    for i = 1, 3 do
        if latest[i] ~= installed[i] then return latest[i] > installed[i] end
    end
    if latest.pre == installed.pre then return false end
    if not latest.pre then return true end
    if not installed.pre then return false end
    return latest.pre > installed.pre
end

function Update.pickAsset(release)
    if not Update.parseVersion(release.tag_name) then return nil, "invalid tag " .. tostring(release.tag_name) end
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == ASSET then
            local sha256 = asset.digest and asset.digest:match("^sha256:(%x+)$")
            if not sha256 then return nil, "no sha256 digest" end
            return {
                version = release.tag_name:gsub("^v", ""),
                url = asset.browser_download_url,
                sha256 = sha256,
                notes = release.body,
            }
        end
    end
    return nil, "no " .. ASSET
end

function Update.notesText(body)
    if type(body) ~= "string" then return "" end
    local lines = {}
    for line in (body:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^#+%s*", ""):gsub("^(%s*)%*%s", "%1- "):gsub("[*`]", "")
        table.insert(lines, line)
    end
    return (table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Update.pluginDir()
    return debug.getinfo(1, "S").source:match("^@(.+)/minimenu/update%.lua$")
end

function Update.installedVersion(dir)
    local ok, meta = pcall(dofile, dir .. "/_meta.lua")
    return ok and type(meta) == "table" and meta.version or nil
end

function Update.isDevInstall(dir)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.symlinkattributes(dir, "mode") == "link" or lfs.attributes(dir .. "/.git", "mode") ~= nil
end

local function get(url, headers, block_timeout, total_timeout)
    local socketutil = require("socketutil")
    local chunks = {}
    headers = headers or {}
    headers["User-Agent"] = USER_AGENT
    socketutil:set_timeout(block_timeout, total_timeout)
    local ok, one, code = pcall(require("socket.http").request, {
        url = url,
        headers = headers,
        sink = socketutil.table_sink(chunks),
    })
    socketutil:reset_timeout()
    if not ok then return nil, tostring(one) end
    if not one then return nil, tostring(code) end
    if code ~= 200 then return nil, "HTTP " .. code end
    return table.concat(chunks)
end

function Update.fetchLatest()
    local socketutil = require("socketutil")
    local body, err = get(
        LATEST_URL,
        { Accept = "application/vnd.github+json" },
        socketutil.LARGE_BLOCK_TIMEOUT,
        socketutil.LARGE_TOTAL_TIMEOUT
    )
    if not body then return nil, err end
    local JSON = require("json")
    local ok, release = pcall(JSON.decode, body, JSON.decode.simple)
    if not ok or type(release) ~= "table" then return nil, "invalid response" end
    return Update.pickAsset(release)
end

function Update.download(asset)
    local data, err = get(asset.url, nil, require("socketutil").FILE_BLOCK_TIMEOUT, 120)
    if not data then return nil, err end
    if require("ffi/sha2").sha256(data) ~= asset.sha256 then return nil, "sha256 mismatch" end
    return data
end

local function workDir(dir)
    return (dir:match("^(.*)/[^/]+$") or ".") .. "/" .. WORK
end

local function purge(path)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") then require("ffi/util").purgeDir(path) end
end

-- Load every module of the running copy that isn't loaded yet, so that after
-- "Restart later" lazy requires don't read the new version's files.
local function pinModules(dir)
    local lfs = require("libs/libkoreader-lfs")
    local function walk(rel)
        for name in lfs.dir(dir .. "/" .. rel) do
            local path = rel .. "/" .. name
            local mode = name ~= "." and name ~= ".." and lfs.attributes(dir .. "/" .. path, "mode")
            if mode == "directory" then
                walk(path)
            elseif mode == "file" and name:match("%.lua$") then
                local module = path:sub(1, -5)
                if not package.loaded[module] then
                    local ok, err = pcall(require, module)
                    if not ok then logger.warn("MiniMenu: couldn't load", module, err) end
                end
            end
        end
    end
    local ok, err = pcall(walk, "minimenu")
    if not ok then logger.warn("MiniMenu: couldn't load modules before updating:", err) end
end

local function extract(zip, work)
    local reader = require("ffi/archiver").Reader:new()
    if not reader:open(zip) then return nil, reader.err end
    local ok = true
    for entry in reader:iterate() do
        ok = reader:extractToPath(entry.path, work .. "/" .. entry.path)
        if not ok then break end
    end
    local err = reader.err
    reader:close()
    if not ok or err then return nil, err end
    return true
end

function Update.install(data, dir, version)
    local work = workDir(dir)
    local function fail(err)
        purge(work)
        return nil, err
    end
    purge(work)
    local ok, err = require("libs/libkoreader-lfs").mkdir(work)
    if not ok then return fail(err) end
    local zip = work .. "/" .. ASSET
    local f
    f, err = io.open(zip, "wb")
    if not f then return fail(err) end
    ok, err = f:write(data)
    f:close()
    if not ok then return fail(err) end
    ok, err = extract(zip, work)
    if not ok then return fail(err) end
    local staged = work .. "/" .. ROOT
    local staged_version = Update.installedVersion(staged)
    if staged_version ~= version then
        return fail(("package has version %s, expected %s"):format(tostring(staged_version), version))
    end
    pinModules(dir)
    local previous = work .. "/previous"
    ok, err = os.rename(dir, previous)
    if not ok then return fail(err) end
    ok, err = os.rename(staged, dir)
    if not ok then
        local restored, restore_err = os.rename(previous, dir)
        if restored then return fail(err) end
        logger.warn("MiniMenu: couldn't restore", dir, restore_err)
        return nil, "the previous version is in " .. previous
    end
    purge(work)
    return true
end

return Update
