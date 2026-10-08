local Update = require("minimenu/update")

local SHA = string.rep("ab", 32)
local URL = "https://github.com/vishnumad/minimenu.koplugin/releases/download/v1.2.0/minimenu.koplugin.zip"

local function release(overrides, asset_overrides)
    local asset = {
        name = "minimenu.koplugin.zip",
        browser_download_url = URL,
        digest = "sha256:" .. SHA,
    }
    for k, v in pairs(asset_overrides or {}) do
        asset[k] = v
    end
    local r = { tag_name = "v1.2.0", body = "notes", assets = { asset } }
    for k, v in pairs(overrides or {}) do
        r[k] = v
    end
    return r
end

describe("update", function()
    describe("parseVersion", function()
        it("accepts X.Y.Z with an optional v and prerelease suffix", function()
            assert.same({ 1, 2, 3 }, Update.parseVersion("1.2.3"))
            assert.same({ 10, 0, 7 }, Update.parseVersion("v10.0.7"))
            assert.same({ 1, 2, 0, pre = "beta.1" }, Update.parseVersion("v1.2.0-beta.1"))
        end)

        it("rejects anything else", function()
            for _, s in ipairs({ "", "1.2", "1.2.3.4", "v1.2.x", "1.2.3-", "1.2.3+build", " 1.2.3", "V1.2.3" }) do
                assert.is_nil(Update.parseVersion(s))
            end
            assert.is_nil(Update.parseVersion(nil))
        end)
    end)

    describe("isNewer", function()
        it("compares numerically", function()
            assert.is_true(Update.isNewer("1.10.0", "1.9.9"))
            assert.is_true(Update.isNewer("v2.0.0", "1.99.99"))
            assert.is_false(Update.isNewer("1.2.3", "1.2.3"))
            assert.is_false(Update.isNewer("v1.2.3", "1.2.3"))
            assert.is_false(Update.isNewer("1.2.2", "1.2.3"))
        end)

        it("sorts a prerelease below its release", function()
            assert.is_true(Update.isNewer("1.2.0", "1.2.0-beta.1"))
            assert.is_false(Update.isNewer("1.2.0-beta.1", "1.2.0"))
            assert.is_true(Update.isNewer("1.2.0-beta.1", "1.1.9"))
            assert.is_true(Update.isNewer("1.2.0-beta.2", "1.2.0-beta.1"))
        end)

        it("treats a missing or invalid installed version as 0.0.0", function()
            assert.is_true(Update.isNewer("0.0.1", nil))
            assert.is_true(Update.isNewer("1.0.0", "dev"))
            assert.is_false(Update.isNewer("0.0.0", nil))
        end)
    end)

    describe("pickAsset", function()
        it("returns the asset of a valid release", function()
            assert.same({
                version = "1.2.0",
                url = URL,
                sha256 = SHA,
                notes = "notes",
            }, Update.pickAsset(release()))
        end)

        local rejected = {
            ["an invalid tag"] = { { tag_name = "latest" } },
            ["no matching asset"] = { {}, { name = "minimenu.koplugin-v1.2.0.zip" } },
            ["no sha256 digest"] = { {}, { digest = false } },
        }
        for name, args in pairs(rejected) do
            it("rejects " .. name, function()
                local asset, reason = Update.pickAsset(release(args[1], args[2]))
                assert.is_nil(asset)
                assert.is_string(reason)
            end)
        end
    end)

    describe("notesText", function()
        it("removes basic markdown", function()
            local body = "## What's new\r\n\r\n* **Bold** change\r\n- `code` fix\r\n\r\n"
                .. "**Full changelog**: https://example.com/compare/v1...v2"
            assert.equal(
                "What's new\n\n- Bold change\n- code fix\n\nFull changelog: https://example.com/compare/v1...v2",
                Update.notesText(body)
            )
        end)

        it("returns an empty string for no body", function()
            assert.equal("", Update.notesText(nil))
            assert.equal("", Update.notesText(""))
        end)
    end)
end)
