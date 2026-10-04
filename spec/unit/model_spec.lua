local model = require("minimenu/model")

local function item(id, kind, data) return { id = id, kind = kind or "x", data = data or {} } end
local function folder(id, items) return { id = id, kind = "folder", data = { items = items or {} } } end

-- A chain of `depth` nested folders; returns root list and innermost folder.
local function deepTree(depth)
    local root = {}
    local list, last = root, nil
    for i = 1, depth do
        local f = folder("i" .. i)
        table.insert(list, f)
        list, last = f.data.items, f
    end
    table.insert(list, item("i" .. (depth + 1)))
    return root, last
end

describe("model", function()
    it("deepcopy copies nested tables without sharing", function()
        local src = { a = { b = { c = 1 } }, list = { 1, 2 } }
        local copy = model.deepcopy(src)
        assert.same(src, copy)
        copy.a.b.c = 2
        assert.equal(1, src.a.b.c)
    end)

    it("find returns item, list, index and ancestors", function()
        local items = { item("i1"), folder("i2", { item("i3"), folder("i4", { item("i5") }) }) }
        local it, list, idx, anc = model.find(items, "i5")
        assert.equal("i5", it.id)
        assert.equal(1, idx)
        assert.equal(items[2].data.items[2].data.items, list)
        assert.same({ "i2", "i4" }, { anc[1].id, anc[2].id })
        assert.is_nil(model.find(items, "nope"))
    end)

    it("walks a 50-level tree without recursion problems", function()
        local root = deepTree(50)
        local count, maxdepth = 0, 0
        model.walk(root, function(_, _, _, depth)
            count = count + 1
            if depth > maxdepth then maxdepth = depth end
        end)
        assert.equal(51, count)
        assert.equal(51, maxdepth)
        local it, _, _, anc = model.find(root, "i51")
        assert.equal("i51", it.id)
        assert.equal(50, #anc)
    end)

    it("walks a very deep tree (10000 levels)", function()
        local root = deepTree(10000)
        local it, _, _, anc = model.find(root, "i10001")
        assert.equal("i10001", it.id)
        assert.equal(10000, #anc)
        local copy = model.deepcopy(root)
        assert.equal("i10001", (model.find(copy, "i10001")).id)
    end)

    it("moves within a list", function()
        local items = { item("a"), item("b"), item("c") }
        assert.is_true(model.move(items, "a", 1))
        assert.same({ "b", "a", "c" }, { items[1].id, items[2].id, items[3].id })
        assert.is_false(model.move(items, "b", -1))
        assert.is_false(model.move(items, "c", 1))
    end)

    it("moveTo refuses moving a folder into itself or a descendant", function()
        local root = deepTree(50)
        local ok, why = model.moveTo(root, "i1", "i30")
        assert.is_false(ok)
        assert.equal("descendant", why)
        ok, why = model.moveTo(root, "i10", "i10")
        assert.is_false(ok)
        -- moving a deep folder up to the top level is fine
        assert.is_true(model.moveTo(root, "i30", nil))
        assert.equal("i30", root[2].id)
        assert.is_nil(model.find(root[1].data.items, "i30"))
    end)

    it("moveTo appends to a folder", function()
        local items = { item("a"), folder("f", { item("x") }), item("b") }
        assert.is_true(model.moveTo(items, "a", "f"))
        assert.same({ "x", "a" }, { items[1].data.items[1].id, items[1].data.items[2].id })
        assert.is_false((model.moveTo(items, "zzz", "f")))
        assert.is_false((model.moveTo(items, "x", "missing")))
    end)

    it("moveOut places an item right after its folder", function()
        local items = { folder("f", { item("x"), item("y") }), item("b") }
        assert.is_true(model.moveOut(items, "x"))
        assert.same({ "f", "x", "b" }, { items[1].id, items[2].id, items[3].id })
        assert.is_false(model.moveOut(items, "b"))
    end)

    it("folders lists folders with depth and excludes a subtree", function()
        local items = { folder("a", { folder("b", { folder("c") }) }), folder("d"), item("e") }
        local all = model.folders(items)
        assert.same({ "a", "b", "c", "d" }, { all[1].item.id, all[2].item.id, all[3].item.id, all[4].item.id })
        assert.same({ 1, 2, 3, 1 }, { all[1].depth, all[2].depth, all[3].depth, all[4].depth })
        local some = model.folders(items, "b")
        assert.same({ "a", "d" }, { some[1].item.id, some[2].item.id })
    end)

    it("cloneItem gives fresh ids to every descendant", function()
        local n = 100
        local issue = function() n = n + 1; return "i" .. n end
        local src = folder("f", { item("x"), folder("g", { item("y") }) })
        local copy = model.cloneItem(src, issue)
        assert.equal("i101", copy.id)
        local ids = {}
        model.walk(copy.data.items, function(it) table.insert(ids, it.id) end)
        assert.same({ "i102", "i103", "i104" }, ids)
        assert.equal("f", src.id)
    end)

    it("detects link cycles", function()
        local data = { menus = {
            m1 = { id = "m1", items = { { id = "i1", kind = "menu_link", data = { menu = "m2" } } } },
            m2 = { id = "m2", items = { folder("i2", { { id = "i3", kind = "menu_link", data = { menu = "m3" } } }) } },
            m3 = { id = "m3", items = {} },
        } }
        assert.is_true(model.linkCreatesCycle(data, "m3", "m1", "menu_link"))
        assert.is_false(model.linkCreatesCycle(data, "m1", "m3", "menu_link"))
        assert.is_true(model.linkCreatesCycle(data, "m1", "m1", "menu_link"))
    end)

    describe("sanitize", function()
        local kinds = function(name)
            if name == "good" then return { validate = function(d) return d.ok == true end } end
            if name == "folder" then return { validate = function(d) return type(d.items) == "table" end } end
        end

        it("turns garbage into an empty store", function()
            local clean, changed = model.sanitize("nope", kinds)
            assert.is_true(changed)
            assert.same(model.empty(), clean)
        end)

        it("does not mutate its input", function()
            local input = { version = 1, next_id = 1, menu_order = { "m9" }, menus = {
                m1 = { id = "m1", title = "A", items = { { id = 3 } } },
            } }
            local before = model.deepcopy(input)
            model.sanitize(input, kinds)
            assert.same(before, input)
        end)

        it("is unchanged on a clean store", function()
            local input = { version = 1, next_id = 5, menu_order = { "m1" }, menus = {
                m1 = { id = "m1", title = "A", items = { { id = "i2", kind = "good", data = { ok = true } } } },
            } }
            local clean, changed = model.sanitize(input, kinds)
            assert.is_false(changed)
            assert.same(input, clean)
        end)

        it("drops bad items and menus, fixes order", function()
            local input = { version = 1, next_id = 1, menu_order = { "m9", "m1", "m1" }, menus = {
                m1 = { id = "m1", title = "A", items = {
                    { id = "i2", kind = "good", data = { ok = true } },
                    { id = "i3", kind = "good", data = { ok = false } }, -- fails validate
                    { kind = "good", data = { ok = true } },             -- no id
                    { id = "i4" },                                       -- no kind
                    "junk",
                } },
                m2 = { id = "m2", title = "B", items = {} },             -- not in order
                m3 = { title = "no id" },
                m5 = { id = "m6", title = "key mismatch" },
            } }
            local clean, changed = model.sanitize(input, kinds)
            assert.is_true(changed)
            assert.same({ "m1", "m2" }, clean.menu_order)
            assert.is_nil(clean.menus.m3)
            assert.is_nil(clean.menus.m5)
            assert.equal(1, #clean.menus.m1.items)
            assert.equal("i2", clean.menus.m1.items[1].id)
        end)

        it("keeps items of unregistered kinds untouched", function()
            local orphan = { id = "i2", kind = "live_panel", data = { anything = { deep = true } }, extra = 1 }
            local input = { version = 1, next_id = 3, menu_order = { "m1" }, menus = {
                m1 = { id = "m1", title = "A", items = { orphan } },
            } }
            local clean = model.sanitize(input, kinds)
            assert.same(orphan, clean.menus.m1.items[1])
        end)

        it("recurses into deep folders and validates there", function()
            local root, inner = deepTree(40)
            table.insert(inner.data.items, { id = "i900", kind = "good", data = { ok = false } })
            local input = { version = 1, next_id = 1, menu_order = { "m1" }, menus = {
                m1 = { id = "m1", title = "A", items = root },
            } }
            local clean, changed = model.sanitize(input, kinds)
            assert.is_true(changed)
            assert.is_nil(model.find(clean.menus.m1.items, "i900"))
            assert.is_not_nil(model.find(clean.menus.m1.items, "i41"))
        end)

        it("repairs duplicate ids and next_id", function()
            local input = { version = 1, next_id = 2, menu_order = { "m1", "m7" }, menus = {
                m1 = { id = "m1", title = "A", items = { item("i5"), folder("i6", { item("i5") }) } },
                m7 = { id = "m7", title = "B", items = { item("i6") } },
            } }
            local clean, changed = model.sanitize(input, kinds)
            assert.is_true(changed)
            local ids, seen = {}, {}
            for _, mid in ipairs(clean.menu_order) do
                model.walk(clean.menus[mid].items, function(it)
                    assert.is_nil(seen[it.id])
                    seen[it.id] = true
                    table.insert(ids, it.id)
                end)
            end
            -- earlier ones keep their ids, later duplicates are re-issued
            assert.same({ "i5", "i6", "i8", "i9" }, ids)
            assert.equal(10, clean.next_id)
        end)

        it("never lowers next_id", function()
            local input = { version = 1, next_id = 99, menu_order = {}, menus = {} }
            local clean = model.sanitize(input, kinds)
            assert.equal(99, clean.next_id)
        end)
    end)
end)
