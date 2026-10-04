local Resolve = require("minimenu/resolve")

local kinds = {
    sep = {
        resolve = function()
            return { separator = true }
        end,
    },
    leaf = {
        resolve = function(item, ctx)
            local ok = not item.data.needs or item.data.needs == ctx.name or item.data.needs == ctx.sub
            return { label = item.data.text, available = ok, run = function() end }
        end,
    },
    boom = {
        resolve = function()
            error("kaboom")
        end,
    },
}
local function lookup(n)
    return kinds[n]
end
local function leaf(id, text, needs, scope)
    return { id = id, kind = "leaf", scope = scope, data = { text = text, needs = needs } }
end
local function sep(id, scope)
    return { id = id, kind = "sep", scope = scope, data = {} }
end
local function labels(rows)
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, r.separator and "--" or r.placeholder and "<empty>" or r.label)
    end
    return out
end

local contexts = {
    fm = { name = "filemanager" },
    paging = { name = "reader", sub = "paging" },
    rolling = { name = "reader", sub = "rolling" },
}

describe("resolve", function()
    local items = {
        sep("s0"),
        leaf("a", "Both"),
        leaf("b", "Reader action", "reader"),
        sep("s1"),
        leaf("c", "PDF only", "paging"),
        leaf("d", "EPUB only", "rolling"),
        sep("s2"),
        sep("s3"),
        leaf("e", "FM scoped", nil, "filemanager"),
        leaf("f", "Reader scoped", nil, "reader"),
        { id = "g", kind = "not_installed", data = {} },
        sep("s4", "reader"),
        leaf("h", "Last"),
        sep("s5"),
    }

    it("filters scope × availability in each context (hide)", function()
        local opts = { hide_unavailable = true, placeholder = "Nothing here" }
        assert.same({ "Both", "--", "FM scoped", "Last" }, labels(Resolve.rows(items, contexts.fm, lookup, opts)))
        assert.same(
            { "Both", "Reader action", "--", "PDF only", "--", "Reader scoped", "--", "Last" },
            labels(Resolve.rows(items, contexts.paging, lookup, opts))
        )
        assert.same(
            { "Both", "Reader action", "--", "EPUB only", "--", "Reader scoped", "--", "Last" },
            labels(Resolve.rows(items, contexts.rolling, lookup, opts))
        )
    end)

    it("dims unavailable rows instead of hiding them when asked", function()
        local rows = Resolve.rows(items, contexts.fm, lookup, { hide_unavailable = false })
        assert.same({ "Both", "Reader action", "--", "PDF only", "EPUB only", "--", "FM scoped", "Last" }, labels(rows))
        assert.is_true(rows[2].dim)
        assert.is_false(Resolve.actionable(rows[2]))
        assert.is_true(Resolve.actionable(rows[1]))
        -- scope still hides even when dimming
        for _, r in ipairs(rows) do
            assert.are_not.equal("Reader scoped", r.label)
        end
    end)

    it("always shows disabled rows dimmed, even when hiding unavailable ones", function()
        local k = function(n)
            if n == "greyed" then
                return {
                    resolve = function()
                        return { label = "Greyed", available = true, disabled = true }
                    end,
                }
            end
            return lookup(n)
        end
        local rows = Resolve.rows(
            { { id = "g", kind = "greyed", data = {} }, leaf("a", "Both") },
            contexts.fm,
            k,
            { hide_unavailable = true }
        )
        assert.same({ "Greyed", "Both" }, labels(rows))
        assert.is_true(rows[1].dim)
    end)

    it("shows a placeholder when nothing is left", function()
        local rows = Resolve.rows(
            { leaf("x", "Reader only", "reader"), sep("y") },
            contexts.fm,
            lookup,
            { hide_unavailable = true, placeholder = "Nothing here in the file browser" }
        )
        assert.equal(1, #rows)
        assert.is_true(rows[1].placeholder)
        assert.equal("Nothing here in the file browser", rows[1].label)
        assert.is_false(Resolve.actionable(rows[1]))
        rows = Resolve.rows({}, contexts.fm, lookup, { placeholder = "P" })
        assert.is_true(rows[1].placeholder)
    end)

    it("user labels and icons win; resolve errors become unavailable", function()
        local rows = Resolve.rows({
            { id = "z", kind = "leaf", label = "Mine", icon = "X", data = { text = "Live" } },
            { id = "q", kind = "boom", label = "Broken", data = {} },
        }, contexts.fm, lookup, { hide_unavailable = false })
        assert.equal("Mine", rows[1].label)
        assert.equal("X", rows[1].icon)
        assert.equal("Broken", rows[2].label)
        assert.is_true(rows[2].dim)
    end)
end)
