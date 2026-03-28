local tl = require("tl")

local rewriter = {}

local record Edit
    line: integer
    col_start: integer
    col_end: integer
    replacement: string
end

function Edit.new(line: integer, col_start: integer, col_end: integer, replacement: string): Edit
    local self: Edit = setmetatable({}, { __index = Edit })
    self.line = line
    self.col_start = col_start
    self.col_end = col_end
    self.replacement = replacement
    return self
end

local record Rewrite
    output: string
    changed: boolean
end

function Rewrite.new(output: string, changed: boolean): Rewrite
    local self: Rewrite = setmetatable({}, { __index = Rewrite })
    self.output = output
    self.changed = changed
    return self
end

-- Collect edits for "exactly one space after comma" rule.
-- Only fires when comma and the next token are on the same line and
-- the gap between them is not exactly one space.
local function collect_comma_edits(tokens: {tl.Token}): {Edit}
    local edits: {Edit} = {}
    for i = 1, #tokens - 1 do
        local current = tokens[i]
        local next_token = tokens[i + 1]
        if current.kind == "," and next_token.y == current.y then
            local comma_end = current.x + #current.tk
            local gap = next_token.x - comma_end
            if gap ~= 1 then
                table.insert(edits, Edit.new(current.y, comma_end, next_token.x - 1, " "))
            end
        end
    end
    return edits
end

-- Apply collected edits to a single line (1-based line number).
-- Edits must all be for the given line. Applied in reverse order to keep
-- column offsets valid.
local function apply_edits_to_line(line_str: string, line_number: integer, edits: {Edit}): string
    -- Edits are passed as a flat list across all lines, so we collect only
    -- those for this line before applying. Reverse column order ensures each
    -- sub() call uses the original column positions without offset drift.
    local line_edits: {Edit} = {}
    for _, edit in ipairs(edits) do
        if edit.line == line_number then
            table.insert(line_edits, edit)
        end
    end

    local function by_col_desc(first: Edit, second: Edit): boolean
        return first.col_start > second.col_start
    end
    table.sort(line_edits, by_col_desc)

    local result = line_str
    for _, edit in ipairs(line_edits) do
        local before = result:sub(1, edit.col_start - 1)
        local after = result:sub(edit.col_end + 1)
        result = before .. edit.replacement .. after
    end
    return result
end

local function strip_trailing_spaces(line_str: string): string
    return (line_str:gsub("%s+$", ""))
end

local function split_preserving_trailing_newline(source: string): {string}
    local lines: {string} = {}
    for line_str in (source .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line_str)
    end
    return lines
end

function rewriter.rewrite(source: string, filename: string): Rewrite
    local tokens, _ = tl.lex(source, filename)
    local edits = collect_comma_edits(tokens)

    local lines = split_preserving_trailing_newline(source)

    local output_lines: {string} = {}
    for i, line_str in ipairs(lines) do
        local result = apply_edits_to_line(line_str, i, edits)
        result = strip_trailing_spaces(result)
        table.insert(output_lines, result)
    end

    local output = table.concat(output_lines, "\n")
    return Rewrite.new(output, output ~= source)
end

return rewriter
