local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Dialogs = require("minimenu/ui/dialogs")
local Update = require("minimenu/update")

local UpdateUI = {}

local function fail(text, err)
    logger.warn("MiniMenu: update failed:", err)
    Dialogs.info(T(text, tostring(err)))
end

local function busy(text, fn)
    local InfoMessage = require("ui/widget/infomessage")
    local message = InfoMessage:new { text = text }
    UIManager:show(message)
    UIManager:forceRePaint()
    local ok, result, err = pcall(fn)
    UIManager:close(message)
    if not ok then return nil, result end
    return result, err
end

local function install(dir, asset)
    local ok, err = busy(_("Downloading…"), function()
        local data, download_err = Update.download(asset)
        if not data then return nil, download_err end
        return Update.install(data, dir, asset.version)
    end)
    if not ok then return fail(_("MiniMenu couldn't be updated (%1)."), err) end
    UIManager:askForRestart(T(_("MiniMenu was updated to v%1."), asset.version))
end

local function offer(dir, asset, installed)
    local TextViewer = require("ui/widget/textviewer")
    local text = T(_("Installed version: v%1"), installed or "?")
    local notes = Update.notesText(asset.notes)
    if notes ~= "" then text = text .. "\n\n" .. notes end
    local viewer
    viewer = TextViewer:new {
        title = T(_("MiniMenu v%1"), asset.version),
        text = text,
        buttons_table = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
                {
                    text = _("Update"),
                    callback = function()
                        UIManager:close(viewer)
                        install(dir, asset)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function UpdateUI.check()
    local dir = Update.pluginDir()
    if Update.isDevInstall(dir) then
        Dialogs.info(_("This copy of MiniMenu is a git checkout or a symlink. Update it with git."))
        return
    end
    -- Not runWhenOnline: it drops the callback when the online check (a DNS
    -- lookup) fails, which it does behind some DNS blockers and captive portals.
    require("ui/network/manager"):runWhenConnected(function()
        local asset, err = busy(_("Checking for updates…"), Update.fetchLatest)
        if not asset then return fail(_("Couldn't check for updates (%1)."), err) end
        local installed = Update.installedVersion(dir)
        if not Update.isNewer(asset.version, installed) then
            Dialogs.info(T(_("MiniMenu is up to date (v%1)."), installed or "?"))
            return
        end
        offer(dir, asset, installed)
    end)
end

return UpdateUI
