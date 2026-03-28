local rewriter = require("formatter.rewriter")

local record Args
    check_only: boolean
    files: {string}
end

function Args.new(check_only: boolean, files: {string}): Args
    local self: Args = setmetatable({}, { __index = Args })
    self.check_only = check_only
    self.files = files
    return self
end

local function read_file(path: string): string, string
    local file, open_err = io.open(path, "r")
    if not file then
        return nil, open_err
    end
    local content = file:read("*a")
    file:close()
    return content, nil
end

local function write_file(path: string, content: string): string
    local file, open_err = io.open(path, "w")
    if not file then
        return open_err
    end
    file:write(content)
    file:close()
    return nil
end

local function parse_args(script_args: {string}): Args
    local check_only = false
    local files: {string} = {}

    for _, value in ipairs(script_args) do
        if value == "--check" then
            check_only = true
        else
            table.insert(files, value)
        end
    end

    if #files == 0 then
        io.stderr:write("usage: tl run src/formatter/init.tl -- [--check] <file...>\n")
        os.exit(1)
    end

    return Args.new(check_only, files)
end

-- Returns true if the file was changed (or would be changed in check mode).
local function process_file(path: string, check_only: boolean): boolean
    local source, read_err = read_file(path)
    if read_err then
        io.stderr:write("error reading " .. path .. ": " .. read_err .. "\n")
        os.exit(1)
    end

    local rewrite = rewriter.rewrite(source, path)

    if #rewrite.parse_errors > 0 then
        for _, err in ipairs(rewrite.parse_errors) do
            io.stderr:write(path .. ":" .. tostring(err.y) .. ":" .. tostring(err.x) .. ": " .. err.msg .. "\n")
        end
        os.exit(1)
    end

    if not rewrite.changed then
        io.stdout:write(path .. ": ok\n")
        return false
    end

    if check_only then
        io.stdout:write(path .. ": would reformat\n")
        return true
    end

    local write_err = write_file(path, rewrite.output)
    if write_err then
        io.stderr:write("error writing " .. path .. ": " .. write_err .. "\n")
        os.exit(1)
    end
    io.stdout:write(path .. ": reformatted\n")
    return true
end

local function main()
    local args = parse_args(arg)

    local any_changed = false
    for _, path in ipairs(args.files) do
        if process_file(path, args.check_only) then
            any_changed = true
        end
    end

    if args.check_only and any_changed then
        os.exit(1)
    end
end

main()
