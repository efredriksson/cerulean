-- Top-level pipeline: lexical pass → line cleanup → structural block render → span pass → cleanup.
-- See ARCHITECTURE.md for the full pipeline diagram.
local ast_utils = require("formatter.ast_utils")
local block_doc = require("formatter.block_doc")
local parser = require("formatter.parser")
local require_sort = require("formatter.require_sort")
local structural_render_analysis = require("formatter.structural_render_analysis")
local tl = require("tl")

local rewriter = {}

local record Edit
    line: integer
    col_start: integer
    col_end: integer
    replacement: string
end

function Edit.new(
    line: integer, col_start: integer, col_end: integer, replacement: string
): Edit
    local self: Edit = setmetatable({}, {__index = Edit})
    self.line = line
    self.col_start = col_start
    self.col_end = col_end
    self.replacement = replacement
    return self
end

local record Rewrite
    output: string
    changed: boolean
    parse_errors: {tl.Error}
end

function Rewrite.new(
    output: string, changed: boolean, parse_errors: {tl.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, {__index = Rewrite})
    self.output = output
    self.changed = changed
    self.parse_errors = parse_errors
    return self
end

local record FormatterContext
    ast: parser.Node
    tokens: {tl.Token}
    edits: {Edit}
    lines: {string}
    fmt_off_regions: ast_utils.FmtOffRegions
end

function FormatterContext.new(
    ast: parser.Node,
    tokens: {tl.Token},
    edits: {Edit},
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions
): FormatterContext
    local self: FormatterContext = setmetatable({}, {__index = FormatterContext})
    self.ast = ast
    self.tokens = tokens
    self.edits = edits
    self.lines = lines
    self.fmt_off_regions = fmt_off_regions
    return self
end

-- Collect edits to convert single-quoted string literals to double quotes.
-- Skips strings that contain a double-quote character (cannot safely convert).
local function collect_quote_edits(tokens: {tl.Token}): {Edit}
    local edits: {Edit} = {}
    for _, token in ipairs(tokens) do
        if token.kind == "string" and token.tk:sub(1, 1) == "'" then
            local content = token.tk:sub(2, -2)
            if not content:find('"', 1, true) then
                local normalized = content:gsub("\\'", "'")
                local replacement = '"' .. normalized .. '"'
                table.insert(
                    edits,
                    Edit.new(token.y, token.x, token.x + #token.tk - 1, replacement)
                )
            end
        end
    end
    return edits
end

-- Bare "<" and ">" are excluded: they are indistinguishable from generic type
-- parameter brackets (e.g. Group<Bomb>) at the token level.  "<=" and ">=" are
-- two-char tokens and are unambiguous, so they stay.
local BINARY_OP_TOKENS: {string: boolean} = {
    ["+"] = true,
    ["-"] = true,
    ["*"] = true,
    ["/"] = true,
    ["%"] = true,
    ["^"] = true,
    [".."] = true,
    ["|"] = true,
    ["=="] = true,
    ["~="] = true,
    ["<="] = true,
    [">="] = true,
    ["="] = true,
    ["and"] = true,
    ["or"] = true,
}

local VALUE_ENDING_KINDS: {string: boolean} = {
    ["identifier"] = true,
    ["integer"] = true,
    ["number"] = true,
    ["string"] = true,
    [")"] = true,
    ["]"] = true,
    ["}"] = true,
}

local function is_binary_minus(prev: tl.Token): boolean
    return VALUE_ENDING_KINDS[prev.kind] ~= nil
end

-- Collect edits to enforce exactly one space on each side of binary operators.
-- Only fires when both neighbours are on the same line as the operator.
-- Skips unary minus.
local function collect_op_edits(tokens: {tl.Token}): {Edit}
    local edits: {Edit} = {}
    for i = 2, #tokens - 1 do
        local token = tokens[i]
        if not BINARY_OP_TOKENS[token.tk] then

        else
            local prev = tokens[i - 1]
            local next_token = tokens[i + 1]
            local is_binary = token.tk ~= "-" or is_binary_minus(prev)
            if is_binary then
                if prev.y == token.y then
                    local prev_end = prev.x + #prev.tk - 1
                    local gap_before = token.x - prev_end - 1
                    if gap_before ~= 1 then
                        table.insert(
                            edits, Edit.new(token.y, prev_end + 1, token.x - 1, " ")
                        )
                    end
                end
                if next_token.y == token.y then
                    local op_end = token.x + #token.tk - 1
                    local gap_after = next_token.x - op_end - 1
                    if gap_after ~= 1 then
                        table.insert(
                            edits, Edit.new(token.y, op_end + 1, next_token.x - 1, " ")
                        )
                    end
                end
            end
        end
    end
    return edits
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
                table.insert(
                    edits, Edit.new(current.y, comma_end, next_token.x - 1, " ")
                )
            end
        end
    end
    return edits
end

local function collect_all_edits(tokens: {tl.Token}): {Edit}
    local edits: {Edit} = {}
    for _, edit in ipairs(collect_comma_edits(tokens)) do
        table.insert(edits, edit)
    end
    for _, edit in ipairs(collect_op_edits(tokens)) do
        table.insert(edits, edit)
    end
    for _, edit in ipairs(collect_quote_edits(tokens)) do
        table.insert(edits, edit)
    end
    return edits
end

local function error_on_edit_conflicts(line_edits: {Edit}, line_number: integer)
    local function edit_bounds(edit: Edit): integer, integer
        if edit.col_end < edit.col_start then
            return edit.col_start, edit.col_start
        end
        return edit.col_start, edit.col_end + 1
    end

    local function edits_conflict(first: Edit, second: Edit): boolean
        local first_start, first_end = edit_bounds(first)
        local second_start, second_end = edit_bounds(second)
        local first_is_insertion = first_start == first_end
        local second_is_insertion = second_start == second_end

        if first_is_insertion and second_is_insertion then
            return first_start == second_start
        elseif first_is_insertion then
            return first_start >= second_start and first_start < second_end
        elseif second_is_insertion then
            return second_start >= first_start and second_start < first_end
        end

        return first_start < second_end and second_start < first_end
    end

    for i = 1, #line_edits do
        for j = i + 1, #line_edits do
            if edits_conflict(line_edits[i], line_edits[j]) then
                error(
                    string.format(
                        "formatter produced overlapping edits on line %d (%d:%d and %d:%d)",
                        line_number,
                        line_edits[i].col_start,
                        line_edits[i].col_end,
                        line_edits[j].col_start,
                        line_edits[j].col_end
                    )
                )
            end
        end
    end
end

local function apply_edits_to_line(
    line_str: string, line_number: integer, edits: {Edit}
): string
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
    error_on_edit_conflicts(line_edits, line_number)

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

-- Collapse runs of more than one blank line to exactly one blank line.
local function collapse_blank_lines(lines: {string}): {string}
    local result: {string} = {}
    local consecutive_blanks = 0
    for i = 1, #lines - 1 do
        local line_str = lines[i]
        if line_str:match("^%s*$") then
            consecutive_blanks = consecutive_blanks + 1
            if consecutive_blanks <= 1 then
                table.insert(result, line_str)
            end
        else
            consecutive_blanks = 0
            table.insert(result, line_str)
        end
    end
    table.insert(result, lines[#lines])
    return result
end

local function build_formatter_context(
    source: string, filename: string, ast: parser.Node
): FormatterContext
    local source_blocks = ast_utils.collect_block_spans(ast)
    local tokens, _ = tl.lex(source, filename)
    local edits = collect_all_edits(tokens)
    local lines = split_preserving_trailing_newline(source)
    local fmt_off_regions = ast_utils.collect_fmt_off_regions(lines, source_blocks)

    return FormatterContext.new(ast, tokens, edits, lines, fmt_off_regions)
end

local function run_lexical_whitespace_pass(context: FormatterContext): {string}
    local result: {string} = {}
    for i, line_str in ipairs(context.lines) do
        if context.fmt_off_regions:includes_line(i) then
            table.insert(result, line_str)
        else
            table.insert(result, apply_edits_to_line(line_str, i, context.edits))
        end
    end
    return result
end

local function run_final_cleanup_pass(
    _context: FormatterContext, lines: {string}
): {string}
    local cleaned_lines: {string} = {}
    for _, line_str in ipairs(lines) do
        local cleaned = strip_trailing_spaces(line_str)
        if cleaned:match("^%s*$") then
            table.insert(cleaned_lines, "")
        else
            table.insert(cleaned_lines, cleaned)
        end
    end

    return collapse_blank_lines(cleaned_lines)
end

local function run_structural_phase(
    source: string, filename: string, ast: parser.Node
): string
    local context = build_formatter_context(source, filename, ast)

    local output_lines = run_lexical_whitespace_pass(context)

    local cleaned_source = table.concat(output_lines, "\n")
    local cleaned_ast, cleaned_parse_errors = parser.parse(cleaned_source, filename)
    if #cleaned_parse_errors == 0 then
        context = build_formatter_context(cleaned_source, filename, cleaned_ast)
        output_lines = context.lines
    end

    local structural_layout: structural_render_analysis.BlockLayout | nil = nil
    if structural_render_analysis.can_use_block_doc_formatter(
        context.ast, output_lines, context.fmt_off_regions
    ) then
        structural_layout = structural_render_analysis.analyze_block_layout(
            context.ast, context.fmt_off_regions, output_lines
        )
    end

    if not (structural_layout is nil) then
        local structurally_rendered = block_doc.render_block(
            context.ast, structural_layout
        )
        if structurally_rendered ~= nil then
            local rendered_source = table.concat(structurally_rendered, "\n") .. "\n"
            local rendered_ast, parse_errors = parser.parse(rendered_source, filename)
            if #parse_errors == 0 then
                context = build_formatter_context(
                    rendered_source, filename, rendered_ast
                )
                output_lines = context.lines
            end
        end
    end

    output_lines = run_final_cleanup_pass(context, output_lines)

    return table.concat(output_lines, "\n")
end

local function run_require_sort_phase(source: string, filename: string): Rewrite
    local output, parse_errors = require_sort.rewrite(source, filename)
    return Rewrite.new(output, output ~= source, parse_errors)
end

function rewriter.rewrite(source: string, filename: string): Rewrite
    local ast, parse_errors = parser.parse(source, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source, false, parse_errors)
    end

    local intermediate = run_structural_phase(source, filename, ast)
    local reorder_rewrite = run_require_sort_phase(intermediate, filename)
    if #reorder_rewrite.parse_errors > 0 then
        return Rewrite.new(
            intermediate, intermediate ~= source, reorder_rewrite.parse_errors
        )
    end

    return Rewrite.new(reorder_rewrite.output, reorder_rewrite.output ~= source, {})
end

return rewriter
