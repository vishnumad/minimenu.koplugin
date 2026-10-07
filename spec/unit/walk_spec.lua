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

    it("doesn't cache a submenu that failed to build", function()
        local fail = true
        local t = {
            {
                id = "setting",
                {
                    id = "lazy",
                    text = "Lazy",
                    sub_item_table_func = function()
                        if fail then error("not ready") end
                        return { { id = "a", text = "A", callback = function() end } }
                    end,
                },
            },
        }
        local path, cache = { { id = "setting" }, { id = "lazy" }, { id = "a" } }, {}
        assert.equal("error", select(2, Walk.resolve(t, path, cache)))
        fail = false
        assert.equal("A", Walk.text((Walk.resolve(t, path, cache))))
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

    it("takes a label's prefix up to its value", function()
        assert.equal("Items per page", Walk.prefix("Items per page: 14"))
        assert.equal("Font size", Walk.prefix("Font size (19)"))
        assert.equal("Wi-Fi connection", Walk.prefix("Wi-Fi connection"))
        assert.equal("", Walk.prefix("14 items"))
    end)

    describe("labels that show a value", function()
        local per_page, lists

        local function resolveLabel(text)
            local t = { { id = "setting", { text = "Lists", sub_item_table = lists } } }
            return Walk.text((Walk.resolve(t, { { id = "setting" }, { text = "Lists" }, { text = text } })))
        end

        before_each(function()
            per_page = 14
            lists = {
                {
                    text_func = function()
                        return per_page and ("Items per page: " .. per_page) or "Items per page"
                    end,
                    callback = function() end,
                },
                { text = "Items per row: 4", callback = function() end },
            }
        end)

        it("still match after the value changes", function()
            per_page = 20
            assert.equal("Items per page: 20", resolveLabel("Items per page: 14"))
        end)

        it("match whether or not the label shows its value", function()
            assert.equal("Items per page: 14", resolveLabel("Items per page"))
            per_page = false
            assert.equal("Items per page", resolveLabel("Items per page: 14"))
        end)

        it("need their prefix to match exactly one entry", function()
            assert.is_nil(resolveLabel("Items per column: 4"))
            table.insert(lists, { text = "Items per page: 5", callback = function() end })
            per_page = 20
            assert.is_nil(resolveLabel("Items per page: 14"))
        end)
    end)
end)
