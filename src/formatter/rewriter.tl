-- Top-level pipeline: lexical pass → line cleanup → structural block render → span pass → cleanup.
-- See ARCHITECTURE.md for the full pipeline diagram.
local ast_utils = require("formatter.ast_utils")
local block_doc = require("formatter.block_doc")
local call_doc = require("formatter.call_doc")
local expr_doc = require("formatter.expr_doc")
local parser = require("formatter.parser")
local require_sort = require("formatter.require_sort")
local signature_doc = require("formatter.signature_doc")
local structural_render_analysis = require("formatter.structural_render_analysis")
local table_doc = require("formatter.table_doc")
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
    parse_errors: {tl.Error}
end

local type SpanKind = enum
    "call"
    "signature"
    "table"
end

local record Span
    open_line: integer
    open_col:  integer
    close_line: integer
    close_col:  integer
    kind: SpanKind
    call_args: parser.Node | nil
    signature_args: parser.Node | nil
    table_node: parser.Node | nil
end

function Span.new(
    open_line: integer,
    open_col: integer,
    close_line: integer,
    close_col: integer,
    kind: SpanKind,
    call_args: parser.Node | nil,
    signature_args: parser.Node | nil,
    table_node: parser.Node | nil
): Span
    local self: Span = setmetatable({}, { __index = Span })
    self.open_line = open_line
    self.open_col = open_col
    self.close_line = close_line
    self.close_col = close_col
    self.kind = kind
    self.call_args = call_args
    self.signature_args = signature_args
    self.table_node = table_node
    return self
end

function Rewrite.new(
    output: string, changed: boolean, parse_errors: {tl.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, { __index = Rewrite })
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
    local self: FormatterContext = setmetatable({}, { __index = FormatterContext })
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
    [")"] = true, ["]"] = true, ["}"] = true,
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

-- Replace each leading tab character with four spaces.
-- Only leading tabs are converted; tabs within a line are left alone.
local function expand_tabs(line_str: string): string
    local indent, rest = line_str:match("^(\t*)(.*)")
    if not indent or indent == "" then
        return line_str
    end
    return string.rep("    ", #indent) .. rest
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

-- ── AST-based wrapping ────────────────────────────────────────────────────────

-- Returns true when a multi-line table's last item line ends with a comma,
-- indicating the author explicitly wants the table kept in expanded form.
local function has_magic_trailing_comma(
    node: parser.Node, source_lines: {string}
): boolean
    if node.yend <= node.y then
        return false
    end
    local last_body_line = source_lines[node.yend - 1]
    return last_body_line ~= nil and last_body_line:match(",%s*$") ~= nil
end

-- Walk the AST collecting Spans for literal_table nodes.
-- Only collects spans that are safe to join/split: no child spans multiple
-- lines, no fmt:off lines fall inside the span, no lines contain comments
-- (inline comments cannot be preserved through a join/split cycle), and no
-- magic trailing comma (author explicitly wants the table kept expanded).
local function collect_table_spans(
    node: parser.Node,
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions,
    result: {Span}
)
    if node.kind == "literal_table" then
        local is_safe = true
        if fmt_off_regions:includes_node(node) then
            is_safe = false
        else
            for line = node.y, node.yend do
                if lines[line] and lines[line]:find("%-%-") then
                    is_safe = false
                    break
                end
            end
        end
        if is_safe and not ast_utils.has_multiline_descendant(node) and not has_magic_trailing_comma(
           node, lines
        ) then
            table.insert(
                result,
                Span.new(node.y, node.x, node.yend, node.xend, "table", nil, nil, node)
            )
        end
        -- Still recurse into children to find nested simple tables
    end

    local function recurse(child: parser.Node)
        collect_table_spans(child, lines, fmt_off_regions, result)
    end
    ast_utils.walk_children(node, recurse)
end

-- Extract the text of a span from the source lines.  Returns the lines that
-- make up the span (partial first/last lines included).
local function extract_span_lines(lines: {string}, span: Span): {string}
    if span.open_line == span.close_line then
        return {lines[span.open_line]:sub(span.open_col, span.close_col)}
    end
    local result: {string} = {}
    table.insert(result, lines[span.open_line]:sub(span.open_col))
    for i = span.open_line + 1, span.close_line - 1 do
        table.insert(result, lines[i])
    end
    table.insert(result, lines[span.close_line]:sub(1, span.close_col))
    return result
end

local function render_call_with_doc(
    args: parser.Node, before: string, after: string, was_already_compact: boolean
): {string}
    local prefer_trailing_compact = after ~= ""
        and not after:match("^,")
        and was_already_compact

    return call_doc.render_call(args, before, after, false, prefer_trailing_compact)
end

local function render_compact_call_with_doc(
    args: parser.Node, before: string, after: string
): {string}
    return call_doc.render_call(args, before, after, true, false)
end

local function render_signature_with_doc(
    before: string, args: parser.Node, after: string
): {string}
    return signature_doc.render_signature(args, before, after, false)
end

local function render_compact_signature_with_doc(
    before: string, args: parser.Node, after: string
): {string}
    return signature_doc.render_signature(args, before, after, true)
end

-- Returns true when any original line in the span's range was replaced by an
-- earlier rewrite.  Checking only the endpoints misses the case where an inner
-- same-line span expanded into multiple lines, shifting the outer span's
-- close_line reference to a now-different position in the result array.
local function span_overlaps_replaced(
    replaced_lines: {integer: boolean}, span: Span
): boolean
    for line = span.open_line, span.close_line do
        if replaced_lines[line] then
            return true
        end
    end
    return false
end

-- Returns true when any line in [open_line, close_line] is fmt:off or has a comment.
local function span_range_is_unsafe(
    open_line: integer,
    close_line: integer,
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions
): boolean
    if fmt_off_regions:includes_range(open_line, close_line) then
        return true
    end
    for line = open_line, close_line do
        if lines[line] and lines[line]:find("%-%-") then
            return true
        end
    end
    return false
end

-- Apply all collected spans (paren and table) in a single bottom-to-top pass.
-- Processing all span types together ensures that line-number shifts caused by
-- one rewrite (e.g. a signature compaction) do not invalidate the line numbers
-- of subsequent spans. Each span carries a kind tag to select the correct
-- join/split functions.
local function apply_all_spans(
    lines: {string}, spans: {Span}, fmt_off_regions: ast_utils.FmtOffRegions
): {string}
    -- Process bottom-to-top (highest open_line first).  For spans on the same
    -- line, process leftmost (outermost) first so the outer span wraps and
    -- marks the line replaced before inner spans are considered.
    local function span_order(first: Span, second: Span): boolean
        if first.open_line ~= second.open_line then return first.open_line > second.open_line end
        return first.open_col < second.open_col
    end
    table.sort(spans, span_order)

    local result: {string} = {}
    for _, source_line in ipairs(lines) do
        table.insert(result, source_line)
    end

    -- Track original line numbers that have been replaced by a multi-line
    -- span rewrite.  Spans whose range overlaps this set are stale.
    local replaced_lines: {integer: boolean} = {}

    for _, span in ipairs(spans) do
        if span_overlaps_replaced(replaced_lines, span) then
            -- stale span: its lines were replaced by an earlier multi-line rewrite
        elseif fmt_off_regions:includes_range(span.open_line, span.close_line) then
            -- skip
        elseif span.open_line == span.close_line then
            local line_str = result[span.open_line]
            -- Skip spans whose open_col is beyond the current line length.
            -- This happens when an enclosing span on the same line was already
            -- processed and replaced the original long line with a shorter one.
            if span.open_col > #line_str then
                -- stale span, skip
            elseif #line_str > 88 then
                local before = line_str:sub(1, span.open_col - 1)
                local after = line_str:sub(span.close_col + 1)
                local split_lines: {string}
                if span.kind == "signature" and span.signature_args ~= nil then
                    split_lines = render_signature_with_doc(
                        before, span.signature_args, after
                    )
                elseif span.kind == "call" and span.call_args ~= nil then
                    split_lines = render_call_with_doc(
                        span.call_args, before, after, true
                    )
                elseif span.kind == "table" and span.table_node ~= nil then
                    split_lines = table_doc.render_table(
                        span.table_node, before, after, false, expr_doc.render_expr
                    )
                else
                    error("unsupported span kind: " .. span.kind)
                end
                if #split_lines > 1 then
                    local new_lines: {string} = {}
                    if span.kind == "signature" or span.kind == "table" or span.kind == "call" then
                        for _, new_line in ipairs(split_lines) do
                            table.insert(new_lines, new_line)
                        end
                    else
                        table.insert(new_lines, before .. split_lines[1])
                        for i = 2, #split_lines - 1 do
                            table.insert(new_lines, split_lines[i])
                        end
                        table.insert(new_lines, split_lines[#split_lines] .. after)
                    end
                    local head: {string} = {}
                    local tail: {string} = {}
                    for i = 1, span.open_line - 1 do table.insert(head, result[i]) end
                    for i = span.open_line + 1, #result do table.insert(
                       tail, result[i]
                    ) end
                    result = {}
                    for _, head_line in ipairs(head) do table.insert(
                       result, head_line
                    ) end
                    for _, new_line in ipairs(new_lines) do table.insert(
                       result, new_line
                    ) end
                    for _, tail_line in ipairs(tail) do table.insert(
                       result, tail_line
                    ) end
                    replaced_lines[span.open_line] = true
                end
            end
        else
            local span_lines = extract_span_lines(result, span)
            local before = result[span.open_line]:sub(1, span.open_col - 1)
            local after = result[span.close_line]:sub(span.close_col + 1)
            local compact_lines: {string}
            if span.kind == "signature" and span.signature_args ~= nil then
                compact_lines = render_compact_signature_with_doc(
                    before, span.signature_args, after
                )
            elseif span.kind == "call" and span.call_args ~= nil then
                compact_lines = render_compact_call_with_doc(
                    span.call_args, before, after
                )
            elseif span.kind == "table" and span.table_node ~= nil then
                compact_lines = table_doc.render_table(
                    span.table_node, before, after, true, expr_doc.render_expr
                )
            else
                error("unsupported span kind: " .. span.kind)
            end
            local head: {string} = {}
            local tail: {string} = {}
            for i = 1, span.open_line - 1 do table.insert(head, result[i]) end
            for i = span.close_line + 1, #result do table.insert(tail, result[i]) end
            local can_join_to_single_line = #compact_lines == 1 and #compact_lines[1] <= 88
            if span.kind == "call" and after ~= "" and not after:match("^,") then
                can_join_to_single_line = false
            end

            if can_join_to_single_line then
                result = {}
                for _, line_str in ipairs(head) do table.insert(result, line_str) end
                table.insert(result, compact_lines[1])
                for _, line_str in ipairs(tail) do table.insert(result, line_str) end
                for line = span.open_line, span.close_line do
                    replaced_lines[line] = true
                end
            else
                local split_lines: {string}
                if span.kind == "signature" and span.signature_args ~= nil then
                    split_lines = render_signature_with_doc(
                        before, span.signature_args, after
                    )
                elseif span.kind == "call" and span.call_args ~= nil then
                    split_lines = render_call_with_doc(
                        span.call_args, before, after, #span_lines == 3
                    )
                elseif span.kind == "table" and span.table_node ~= nil then
                    split_lines = table_doc.render_table(
                        span.table_node, before, after, false, expr_doc.render_expr
                    )
                else
                    error("unsupported span kind: " .. span.kind)
                end
                if #split_lines > 1 then
                    local new_lines: {string} = {}
                    if span.kind == "signature" or span.kind == "table" or span.kind == "call" then
                        for _, new_line in ipairs(split_lines) do
                            table.insert(new_lines, new_line)
                        end
                    else
                        table.insert(new_lines, before .. split_lines[1])
                        for i = 2, #split_lines - 1 do
                            table.insert(new_lines, split_lines[i])
                        end
                        table.insert(new_lines, split_lines[#split_lines] .. after)
                    end
                    result = {}
                    for _, line_str in ipairs(head) do table.insert(
                       result, line_str
                    ) end
                    for _, line_str in ipairs(new_lines) do table.insert(
                       result, line_str
                    ) end
                    for _, line_str in ipairs(tail) do table.insert(
                       result, line_str
                    ) end
                    for line = span.open_line, span.close_line do
                        replaced_lines[line] = true
                    end
                end
            end
        end
    end

    return result
end

-- Walk the AST collecting Spans for function parameter lists.
local function collect_signature_spans(
    node: parser.Node,
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions,
    result: {Span}
)
    if ast_utils.is_function_def(node) and node.args then
        local args = node.args
        if not span_range_is_unsafe(args.y, args.yend, lines, fmt_off_regions)
            and not ast_utils.has_multiline_descendant(args)
        then
            table.insert(
                result,
                Span.new(
                    args.y, args.x, args.yend, args.xend, "signature", nil, args, nil
                )
            )
        end
    end
    local function recurse(child: parser.Node)
        collect_signature_spans(child, lines, fmt_off_regions, result)
    end
    ast_utils.walk_children(node, recurse)
end

-- Walk the AST collecting Spans for function call argument lists.
-- Skips calls that use string-call or table-call syntax (no "(" on the line).
local function collect_call_spans(
    node: parser.Node,
    lines: {string},
    fmt_off_regions: ast_utils.FmtOffRegions,
    result: {Span}
)
    if node.kind == "op" and node.op ~= nil and node.op.op == "@funcall" and node.e2 ~= nil then
        local args = node.e2
        local args_line = lines[args.y]
        if args_line and args_line:sub(args.x, args.x) == "(" then
            if not span_range_is_unsafe(args.y, args.yend, lines, fmt_off_regions)
                and not ast_utils.has_multiline_descendant(args)
            then
                table.insert(
                    result,
                    Span.new(
                        args.y, args.x, args.yend, args.xend, "call", args, nil, nil
                    )
                )
            end
        end
    end
    local function recurse(child: parser.Node)
        collect_call_spans(child, lines, fmt_off_regions, result)
    end
    ast_utils.walk_children(node, recurse)
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

local function run_line_cleanup_pass(
    context: FormatterContext, lines: {string}
): {string}
    local result: {string} = {}
    for i, line_str in ipairs(lines) do
        if context.fmt_off_regions:includes_line(i) then
            table.insert(result, line_str)
        else
            local cleaned = expand_tabs(line_str)
            cleaned = strip_trailing_spaces(cleaned)
            table.insert(result, cleaned)
        end
    end
    return result
end

local function collect_structural_spans(context: FormatterContext): {Span}
    local spans: {Span} = {}
    collect_signature_spans(context.ast, context.lines, context.fmt_off_regions, spans)
    collect_call_spans(context.ast, context.lines, context.fmt_off_regions, spans)
    collect_table_spans(context.ast, context.lines, context.fmt_off_regions, spans)
    return spans
end

local function run_structural_span_pass(
    context: FormatterContext, lines: {string}, spans: {Span}
): {string}
    return apply_all_spans(lines, spans, context.fmt_off_regions)
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

local function top_level_block_has_nested_structure(block: parser.Node): boolean
    for _, stmt in ipairs(block) do
        if stmt.body ~= nil or stmt.if_blocks ~= nil then
            return true
        end
    end

    return false
end

local function run_structural_phase(
    source: string, filename: string, ast: parser.Node
): string
    local context = build_formatter_context(source, filename, ast)

    local output_lines = run_lexical_whitespace_pass(context)
    output_lines = run_line_cleanup_pass(context, output_lines)

    local cleaned_source = table.concat(output_lines, "\n")
    local cleaned_ast, cleaned_parse_errors = parser.parse(cleaned_source, filename)
    if #cleaned_parse_errors == 0 then
        context = build_formatter_context(cleaned_source, filename, cleaned_ast)
        output_lines = context.lines
    end

    local structural_layout: any = nil
    if top_level_block_has_nested_structure(context.ast) then
        structural_layout = structural_render_analysis.analyze_block(
            context.ast, output_lines, context.fmt_off_regions
        )
    end

    if structural_layout ~= nil then
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

    local structural_spans = collect_structural_spans(context)
    output_lines = run_structural_span_pass(context, output_lines, structural_spans)
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
