-- Headless spec helper: stubs the few KOReader modules pure code touches.
package.path = "./?.lua;" .. package.path

local function template(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d+)", function(i) return tostring(args[tonumber(i)]) end))
end

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.preload["logger"] = function()
    local noop = function() end
    return { dbg = noop, info = noop, warn = noop, err = noop }
end
package.preload["ffi/util"] = function()
    return { template = template }
end

_G.MINIMENU_TEST = true
