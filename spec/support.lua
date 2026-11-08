local Store = require("minimenu/store")

local Support = {}

--- Points the store at a memory backend holding `initial`, with no listeners.
-- Returns the backend.
function Support.memoryStore(initial)
    local backend = Store.memoryBackend(initial)
    Store.setBackend(backend)
    Store.listeners = {}
    return backend
end

return Support
