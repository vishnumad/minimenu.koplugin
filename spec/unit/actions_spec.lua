local Store = require("minimenu/store")
local Actions = require("minimenu/actions")

local function fakeDispatcher()
    local d = { list = {}, calls = {} }
    function d:registerAction(name, value)
        table.insert(self.calls, "register " .. name)
        if self.list[name] == nil then self.list[name] = value end
        return true
    end
    function d:removeAction(name)
        table.insert(self.calls, "remove " .. name)
        self.list[name] = nil
        return true
    end
    return d
end

describe("actions lifecycle", function()
    local D, events
    before_each(function()
        Store.setBackend(Store.memoryBackend(nil))
        Store.listeners = {}
        Store.load()
        D = fakeDispatcher()
        events = {}
        Actions.inject({ dispatcher = D, broadcast = function(name, payload)
            table.insert(events, { name = name, payload = payload })
        end })
        Actions.detach = nil
        Actions.attach(Store)
    end)

    it("registers a general none-category action per menu, named by id", function()
        local m = Store.createMenu("Reading tools")
        local spec = D.list["minimenu_open_" .. m.id]
        assert.same({ category = "none", event = "MiniMenuOpen", arg = m.id,
            title = "MiniMenu: Reading tools", general = true }, spec)
        assert.is_nil(spec.reader)
        assert.is_nil(spec.filemanager)
    end)

    it("rename = remove + register under the same name, new title", function()
        local m = Store.createMenu("Old")
        D.calls = {}
        Store.renameMenu(m.id, "New")
        local name = "minimenu_open_" .. m.id
        assert.same({ "remove " .. name, "register " .. name }, D.calls)
        assert.equal("MiniMenu: New", D.list[name].title)
        assert.equal(0, #events)
    end)

    it("delete removes the action and broadcasts new_name = nil", function()
        local m = Store.createMenu("Gone")
        Store.deleteMenu(m.id)
        local name = "minimenu_open_" .. m.id
        assert.is_nil(D.list[name])
        assert.equal(1, #events)
        assert.equal("DispatcherActionNameChanged", events[1].name)
        assert.same({ old_name = name }, events[1].payload)
        assert.is_nil(events[1].payload.new_name)
    end)

    it("switching 'show in action list' off unregisters, on registers", function()
        local m = Store.createMenu("Toggle")
        local name = "minimenu_open_" .. m.id
        Store.setRegisterAction(m.id, false)
        assert.is_nil(D.list[name])
        assert.equal(1, #events)
        Store.renameMenu(m.id, "Renamed while hidden")
        assert.is_nil(D.list[name])
        Store.setRegisterAction(m.id, true)
        assert.equal("MiniMenu: Renamed while hidden", D.list[name].title)
    end)

    it("registerAll registers only menus that want it", function()
        local a = Store.createMenu("A")
        local b = Store.createMenu("B")
        Store.setRegisterAction(b.id, false)
        D.list = {}
        Actions.registerAll(Store)
        assert.is_not_nil(D.list["minimenu_open_" .. a.id])
        assert.is_nil(D.list["minimenu_open_" .. b.id])
    end)

    it("duplicating a hidden menu does not register the copy", function()
        local m = Store.createMenu("Hidden")
        Store.setRegisterAction(m.id, false)
        local copy = assert(Store.duplicateMenu(m.id, "Hidden copy"))
        assert.is_false(copy.register_action)
        assert.is_nil(D.list["minimenu_open_" .. copy.id])
        local shown = assert(Store.duplicateMenu(Store.createMenu("Shown").id, "Shown copy"))
        assert.is_not_nil(D.list["minimenu_open_" .. shown.id])
        assert.equal("MiniMenu: Shown copy", D.list["minimenu_open_" .. shown.id].title)
    end)

    it("attaches once", function()
        Actions.attach(Store)
        Actions.attach(Store)
        D.calls = {}
        Store.createMenu("Once")
        assert.equal(1, #D.calls)
    end)
end)
