local Trapper = require("ui/trapper")
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

-- task runs in a subprocess, so a slow network can't freeze the UI and tapping
-- the message kills it (busy then returns false). finish runs in this process,
-- as Update.install loads modules into it. Must run under Trapper:wrap.
local function busy(text, task, finish)
    local InfoMessage = require("ui/widget/infomessage")
    local message = InfoMessage:new { text = text }
    UIManager:show(message)
    UIManager:forceRePaint()
    local completed, ok, result, err = Trapper:dismissableRunInSubprocess(function()
        return pcall(task)
    end, message)
    if not completed then return false end
    -- Trapper's dismiss_callback would fire again when we close the message.
    message.dismiss_callback = nil
    if not ok then
        result, err = nil, result or "no response"
    elseif result and finish then
        ok, result, err = pcall(finish, result)
        if not ok then
            result, err = nil, result
        end
    end
    UIManager:close(message)
    return true, result, err
end

local function install(dir, asset)
    local done, ok, err = busy(_("Downloading…"), function()
        return Update.download(asset)
    end, function(data)
        return Update.install(data, dir, asset.version)
    end)
    if not done then return end
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
                        Trapper:wrap(function()
                            install(dir, asset)
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

local function check(dir)
    local done, asset, err = busy(_("Checking for updates…"), Update.fetchLatest)
    if not done then return end
    if not asset then return fail(_("Couldn't check for updates (%1)."), err) end
    local installed = Update.installedVersion(dir)
    if not Update.isNewer(asset.version, installed) then
        Dialogs.info(T(_("MiniMenu is up to date (v%1)."), installed or "?"))
        return
    end
    offer(dir, asset, installed)
end

function UpdateUI.check()
    local dir = Update.pluginDir()
    if not dir then return fail(_("Couldn't check for updates (%1)."), "plugin folder not found") end
    if Update.isDevInstall(dir) then
        Dialogs.info(_("This copy of MiniMenu is a git checkout or a symlink. Update it with git."))
        return
    end
    -- Not runWhenOnline: it drops the callback when the online check (a DNS
    -- lookup) fails, which it does behind some DNS blockers and captive portals.
    require("ui/network/manager"):runWhenConnected(function()
        Trapper:wrap(function()
            check(dir)
        end)
    end)
end

return UpdateUI
