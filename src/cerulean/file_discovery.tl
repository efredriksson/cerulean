local lfs = require("lfs")

local file_discovery = {}

local function is_directory(path: string): boolean
    local mode, _ = lfs.attributes(path, "mode")
    return mode == "directory"
end

local function collect_tl_files_in_dir(dir: string, out: {string}): string
    local names: {string} = {}
    for name in lfs.dir(dir) do
        if name:sub(1, 1) ~= "." then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local child = dir .. "/" .. name
        if is_directory(child) then
            local err = collect_tl_files_in_dir(child, out)
            if err then
                return err
            end
        elseif child:sub(-3) == ".tl" then
            table.insert(out, child)
        end
    end
    return nil
end

function file_discovery.expand_paths(paths: {string}): {string}, string
    local all_files: {string} = {}
    for _, path in ipairs(paths) do
        if is_directory(path) then
            local err = collect_tl_files_in_dir(path, all_files)
            if err then
                return nil, err
            end
        else
            table.insert(all_files, path)
        end
    end
    return all_files, nil
end

return file_discovery
