local Context = {}

function Context.readerUI()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance or nil
end

function Context.fileManager()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    return ok and FileManager and FileManager.instance or nil
end

--- Returns { name = "reader"|"filemanager", sub = "paging"|"rolling"|nil, ui }
function Context.current()
    local reader = Context.readerUI()
    if reader then return { name = "reader", sub = reader.paging and "paging" or "rolling", ui = reader } end
    return { name = "filemanager", ui = Context.fileManager() }
end

return Context
