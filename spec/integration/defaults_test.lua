local H = require("harness").setup()
local Store, test, eq = H.Store, H.test, H.eq
local DispatchUtil = require("minimenu/dispatch")
local Actions = require("minimenu/actions")

H.firstInstall()
H.fm()

local function unknown(items)
    local out = {}
    require("minimenu/model").walk(items, function(item)
        if item.kind == "dispatcher" and not DispatchUtil.exists(next(item.data.action)) then
            table.insert(out, next(item.data.action))
        end
    end)
    return out
end

test("first install: one ready-made menu, bound to an action", function()
    local menus = Store.menus()
    eq(1, #menus)
    eq("Quick menu", menus[1].title)
    assert(#menus[1].items > 0, "has items")
    eq({}, unknown(menus[1].items))
    assert(DispatchUtil.exists(Actions.name(menus[1].id)), "Dispatcher action registered")
    -- Saved straight away, so it isn't seeded again.
    assert(require("libs/libkoreader-lfs").attributes(H.settings_file, "mode") == "file", "written")
end)

test("default menu opens in the file browser without reader-only rows", function()
    local id = Store.menus()[1].id
    H.API.open(id)
    H.drain()
    local labels = H.rowLabels(1)
    for _, label in ipairs(labels) do
        assert(label ~= "Table of contents" and label ~= "Go to", "reader-only row shown: " .. label)
    end
    assert(H.rowIndex(1, "History"), "History row")
    H.shot("defaults_fm")
end)

test("default menu fits on one page in the reader", function()
    H.reader("juliet.epub")
    H.API.open(Store.menus()[1].id)
    H.drain()
    assert(H.rowIndex(1, "Table of contents"), "Table of contents row")
    assert(H.rowIndex(1, "Go to"), "Go to folder")
    H.shot("defaults_reader")
    eq(1, #H.popup().chain[1].panel.pages)
    H.API.close()
    H.closeReader()
end)

test("deleting every menu does not bring the default back", function()
    Store.deleteMenu(Store.menus()[1].id)
    Store.setBackend(Store.fileBackend(H.settings_file))
    H.API.ensure()
    eq(0, #Store.menus())
end)

test("New menu… starts from the default items", function()
    local Dialogs = require("minimenu/ui/dialogs")
    local input = Dialogs.input
    ---@diagnostic disable-next-line: duplicate-set-field
    Dialogs.input = function(_args, callback)
        callback("  Mine ")
    end
    local created
    require("minimenu/ui/editor").newMenu(function(menu)
        created = menu
    end)
    Dialogs.input = input
    eq("Mine", created.title)
    local first_install = require("minimenu/defaults").items()
    eq(#first_install, #created.items)
    eq({}, unknown(created.items))
end)

H.finish()
