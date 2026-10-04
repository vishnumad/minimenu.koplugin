local Walk = require("minimenu/menupath/walk")

local calls = 0
local function tree()
    local wifi_on = false
    return {
        {
            id = "setting",
            icon = "appbar.settings",
            {
                id = "network",
                text = "Network",
                sub_item_table = {
                    {
                        id = "wifi",
                        text_func = function()
                            return "Wi-Fi connection"
                        end,
                        checked_func = function()
                            return wifi_on
                        end,
                        callback = function()
                            wifi_on = not wifi_on
                        end,
                    },
                    {
                        text = "Inline thing",
                        callback = function()
                            calls = calls + 1
                        end,
                    },
                    {
                        text = "Disabled",
                        enabled_func = function()
                            return false
                        end,
                        callback = function() end,
                    },
                },
            },
            {
                id = "lazy",
                text = "Lazy",
                sub_item_table_func = function()
                    return { { text = "Deep", callback = function() end } }
                end,
            },
            {
                id = "broken",
                text = "Broken",
                sub_item_table_func = function()
                    error("boom")
                end,
            },
            {
                id = "throws",
                text_func = function()
                    error("nope")
                end,
                text = "Fallback",
                callback = function() end,
            },
        },
        { id = "tools", icon = "appbar.tools" },
    }
end

describe("menupath walk", function()
    it("resolves id and text segments, lazily", function()
        local t = tree()
        local node = Walk.resolve(t, { { id = "setting" }, { id = "network" }, { id = "wifi" } })
        assert.equal("Wi-Fi connection", Walk.text(node))
        assert.is_true(Walk.isLeaf(node))
        assert.is_true(Walk.isToggle(node))
        assert.is_false(Walk.checked(node))
        Walk.callback(node)()
        assert.is_true(Walk.checked(node))
        node = Walk.resolve(t, { { id = "setting" }, { text = "Lazy" }, { text = "Deep" } })
        assert.equal("Deep", Walk.text(node))
        node = Walk.resolve(t, { { id = "setting" }, { id = "network" }, { text = "Inline thing" } })
        assert.is_true(Walk.isLeaf(node))
    end)

    it("reports missing vs errored paths", function()
        local t = tree()
        local node, why = Walk.resolve(t, { { id = "setting" }, { id = "nope" } })
        assert.is_nil(node)
        assert.equal("missing", why)
        node, why = Walk.resolve(t, { { id = "setting" }, { id = "broken" }, { text = "x" } })
        assert.is_nil(node)
        assert.equal("error", why)
        assert.is_nil((Walk.resolve(nil, { { id = "x" } })))
        assert.is_nil((Walk.resolve(t, {})))
    end)

    it("prefers ids over text when both are stored", function()
        local t = tree()
        local node = Walk.resolve(
            t,
            { { id = "setting", text = "Settings (old translation)" }, { id = "network", text = "Réseau" } }
        )
        assert.equal("Network", Walk.text(node))
    end)

    it("falls back to text when text_func throws", function()
        local t = tree()
        local node = Walk.resolve(t, { { id = "setting" }, { id = "throws" } })
        assert.equal("Fallback", Walk.text(node))
    end)

    it("knows enabled state", function()
        local t = tree()
        local node = Walk.resolve(t, { { id = "setting" }, { id = "network" }, { text = "Disabled" } })
        assert.is_false(Walk.enabled(node))
    end)

    it("builds capture lists with segments", function()
        local t = tree()
        local rows = Walk.captureList(Walk.children(Walk.resolve(t, { { id = "setting" }, { id = "network" } })))
        assert.equal(3, #rows)
        assert.same({ id = "wifi", text = "Wi-Fi connection" }, rows[1].segment)
        assert.same({ text = "Inline thing" }, rows[2].segment)
        assert.is_true(rows[1].toggle)
        local tabs = Walk.tabList(t, { setting = "Settings" })
        assert.equal(1, #tabs) -- empty tabs skipped
        assert.equal("Settings", tabs[1].text)
        assert.same({ id = "setting", text = "Settings" }, tabs[1].segment)
    end)
end)
