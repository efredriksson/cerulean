-- A/B conformance harness: pins formatter behavior on the pinned fuzz corpus so a
-- refactor (or a replacement parser) can be diffed against the previous behavior.
--   tl run fuzz/ab.tl -- snapshot    (capture baseline into fuzz/ab_snapshot/)
--   tl run fuzz/ab.tl -- diff        (re-run corpus, report drift, exit 1 on any)
-- Pins the per-file status for every corpus file and the formatted output for
-- reformatted ones. Error and failure-reason text is deliberately not pinned so
-- diagnostic wording can change without producing drift.
local options_module = require("cerulean.options")
local rewriter = require("cerulean.rewriter")

local CORPUS_DIR = "fuzz/corpus"
local SNAPSHOT_DIR = "fuzz/ab_snapshot"

local enum AbStatus
    "reformatted"
    "unchanged"
    "failed"
    "errored"
    "crashed"
end

local record Outcome
    status: AbStatus
    output: string
end

function Outcome.new(status: AbStatus, output: string): Outcome
    local self: Outcome = setmetatable({}, {__index = Outcome})
    self.status = status
    self.output = output
    return self
end

local function read_file(path: string): string | nil
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path: string, content: string)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
end

local function list_files(dir: string, pattern: string): {string}
    local paths: {string} = {}
    local handle = io.popen(
        "find " .. dir .. " -name '" .. pattern .. "' -type f 2>/dev/null | sort"
    )
    if handle then
        for line in handle:lines() do
            table.insert(paths, line)
        end
        handle:close()
    end
    return paths
end

local function base_name(path: string): string
    return path:match("([^/]+)$") or path
end

local function classify(path: string, content: string): Outcome
    local opts = options_module.default()
    local ok, result = pcall(rewriter.rewrite, content, path, opts)
    if not ok then
        return Outcome.new("crashed", "")
    end
    if #result.parse_errors > 0 then
        return Outcome.new("errored", "")
    end
    if result.status == "failed" then
        return Outcome.new("failed", "")
    end
    if result.status == "unchanged" then
        return Outcome.new("unchanged", "")
    end
    return Outcome.new("reformatted", result.output)
end

local function encode(outcome: Outcome): string
    return outcome.status .. "\n" .. outcome.output
end

local valid_statuses: {string: AbStatus} = {
    reformatted = "reformatted",
    unchanged = "unchanged",
    failed = "failed",
    errored = "errored",
    crashed = "crashed",
}

local function decode(snap: string): Outcome | nil
    local status_text, output = snap:match("^([^\n]*)\n(.*)$")
    local status = valid_statuses[status_text]
    if not status then
        return nil
    end
    return Outcome.new(status, output)
end

local function corpus_paths(): {string}
    local paths = list_files(CORPUS_DIR, "*.tl")
    if #paths == 0 then
        io.stderr:write(
            "ab: no corpus in " .. CORPUS_DIR
                .. "; generate one first (make fuzz / make fuzz-corpus)\n"
        )
        os.exit(2)
    end
    return paths
end

local function snap_path(corpus_path: string): string
    return SNAPSHOT_DIR .. "/" .. base_name(corpus_path) .. ".snap"
end

local function print_status_counts(counts: {AbStatus: integer}, total: integer)
    io.stdout:write(string.format("Corpus files: %d\n", total))
    local status_order: {AbStatus} = {
        "reformatted", "unchanged", "failed", "errored", "crashed",
    }
    for _, status in ipairs(status_order) do
        io.stdout:write(string.format("    %-13s %d\n", status .. ":", counts[status]))
    end
end

local function new_status_counts(): {AbStatus: integer}
    return {reformatted = 0, unchanged = 0, failed = 0, errored = 0, crashed = 0}
end

local function run_snapshot()
    local paths = corpus_paths()
    os.execute("mkdir -p " .. SNAPSHOT_DIR)
    os.execute("rm -f " .. SNAPSHOT_DIR .. "/*.snap")

    local counts = new_status_counts()
    for _, path in ipairs(paths) do
        local content = read_file(path)
        if content then
            local outcome = classify(path, content)
            counts[outcome.status] = counts[outcome.status] + 1
            write_file(snap_path(path), encode(outcome))
        end
    end

    io.stdout:write("Snapshot written to " .. SNAPSHOT_DIR .. "\n")
    print_status_counts(counts, #paths)
end

local function run_diff()
    local paths = corpus_paths()
    local orphan_snaps: {string: boolean} = {}
    for _, snap in ipairs(list_files(SNAPSHOT_DIR, "*.snap")) do
        orphan_snaps[base_name(snap)] = true
    end
    if not next(orphan_snaps) then
        io.stderr:write(
            "ab: no snapshot in " .. SNAPSHOT_DIR .. "; run snapshot first\n"
        )
        os.exit(2)
    end

    local drift: {string} = {}
    local counts = new_status_counts()
    for _, path in ipairs(paths) do
        local content = read_file(path)
        if content then
            local outcome = classify(path, content)
            counts[outcome.status] = counts[outcome.status] + 1
            local snap = read_file(snap_path(path))
            orphan_snaps[base_name(snap_path(path))] = nil
            if snap is nil then
                table.insert(
                    drift, base_name(path) .. ": missing snapshot (corpus changed?)"
                )
            else
                local pinned = decode(snap)
                if pinned is nil then
                    table.insert(drift, base_name(path) .. ": unreadable snapshot")
                elseif pinned.status ~= outcome.status then
                    table.insert(
                        drift,
                        base_name(path) .. ": " .. pinned.status
                            .. " -> " .. outcome.status
                    )
                elseif pinned.output ~= outcome.output then
                    table.insert(drift, base_name(path) .. ": output differs")
                end
            end
        end
    end
    for snap_name, _ in pairs(orphan_snaps) do
        table.insert(
            drift, snap_name .. ": snapshot without corpus file (corpus changed?)"
        )
    end
    table.sort(drift)

    for _, line in ipairs(drift) do
        io.stdout:write(line .. "\n")
    end
    io.stdout:write("\n")
    print_status_counts(counts, #paths)
    io.stdout:write(string.format("Drift: %d\n", #drift))
    os.exit(#drift == 0 and 0 or 1)
end

local mode = arg[1]
if mode == "snapshot" then
    run_snapshot()
elseif mode == "diff" then
    run_diff()
else
    io.stderr:write("usage: tl run fuzz/ab.tl -- snapshot|diff\n")
    os.exit(2)
end
