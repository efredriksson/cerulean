local lfs = require("lfs")

local file_discovery = {}

local function is_directory(path: string): boolean
    local mode, _ = lfs.attributes(path, "mode")
    return mode == "directory"
end

local function collect_tl_files_in_dir(dir: string, out: {string}, errors: {string})
    local results: {any} = {pcall(lfs.dir, dir)}
    local ok = results[1] as boolean
    if not ok or type(results[2]) ~= "function" then
        local reason = ok and "unexpected lfs.dir failure" or tostring(results[2])
        table.insert(
            errors, string.format("cannot read directory '%s': %s", dir, reason)
        )
        return
    end
    local iter = results[2] as function(any): string
    local state = results[3]
    local names: {string} = {}
    for name in iter, state do
        if name:sub(1, 1) ~= "." then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local child = dir .. "/" .. name
        if is_directory(child) then
            collect_tl_files_in_dir(child, out, errors)
        elseif child:sub(-3) == ".tl" then
            table.insert(out, child)
        end
    end
end

function file_discovery.expand_paths(paths: {string}): {string}, {string}
    local all_files: {string} = {}
    local errors: {string} = {}
    for _, path in ipairs(paths) do
        if is_directory(path) then
            collect_tl_files_in_dir(path, all_files, errors)
        else
            table.insert(all_files, path)
        end
    end
    return all_files, errors
end

return file_discovery
