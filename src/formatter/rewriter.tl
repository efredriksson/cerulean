local blocks = require("formatter.blocks")
local doc = require("formatter.doc")
local parser = require("formatter.parser")
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

local record Span
    open_line: integer
    open_col:  integer
    close_line: integer
    close_col:  integer
    is_call:   boolean
    is_signature: boolean
    is_table:  boolean
end

function Span.new(
    open_line: integer,
    open_col: integer,
    close_line: integer,
    close_col: integer,
    is_call: boolean,
    is_signature: boolean,
    is_table: boolean
): Span
    local self: Span = setmetatable({}, { __index = Span })
    self.open_line = open_line
    self.open_col = open_col
    self.close_line = close_line
    self.close_col = close_col
    self.is_call = is_call
    self.is_signature = is_signature
    self.is_table = is_table
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

local record RequireDecl
    first_line:  integer
    last_line:   integer
    module_path: string
end

function RequireDecl.new(
    first_line: integer, last_line: integer, module_path: string
): RequireDecl
    local self: RequireDecl = setmetatable({}, { __index = RequireDecl })
    self.first_line = first_line
    self.last_line = last_line
    self.module_path = module_path
    return self
end

local record FormatterContext
    source: string
    filename: string
    ast: parser.Node
    source_blocks: {blocks.Block}
    require_decls: {RequireDecl}
    tokens: {tl.Token}
    edits: {Edit}
    lines: {string}
    fmt_off_lines: {integer: boolean}
end

function FormatterContext.new(
    source: string,
    filename: string,
    ast: parser.Node,
    source_blocks: {blocks.Block},
    require_decls: {RequireDecl},
    tokens: {tl.Token},
    edits: {Edit},
    lines: {string},
    fmt_off_lines: {integer: boolean}
): FormatterContext
    local self: FormatterContext = setmetatable({}, { __index = FormatterContext })
    self.source = source
    self.filename = filename
    self.ast = ast
    self.source_blocks = source_blocks
    self.require_decls = require_decls
    self.tokens = tokens
    self.edits = edits
    self.lines = lines
    self.fmt_off_lines = fmt_off_lines
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

-- Returns the close_line of the innermost block that contains the given line,
-- or last_line + 1 when the line is at the top level (no enclosing block).
local function find_enclosing_block_end(
    source_blocks: {blocks.Block}, line: integer, last_line: integer
): integer
    local innermost_end = last_line + 1
    for _, block in ipairs(source_blocks) do
        if block.open_line <= line and block.close_line > line then
            if block.close_line < innermost_end then
                innermost_end = block.close_line
            end
        end
    end
    return innermost_end
end

-- tl.lex strips comments, so directives cannot be found in the token stream.
-- We scan raw lines for the directives while using the AST-derived block
-- spans to enforce that --fmt: on must close the same block as --fmt: off.
local function collect_fmt_off_lines(source_lines: {string}, source_blocks: {blocks.Block}): {integer: boolean}
    local fmt_off_lines: {integer: boolean} = {}
    local formatting_off = false
    local off_start = 0
    local region_end = 0

    for line_number, line_str in ipairs(source_lines) do
        if not formatting_off and line_str:match("%-%-%s*fmt:%s*off") then
            formatting_off = true
            off_start = line_number
            region_end = find_enclosing_block_end(source_blocks, line_number, #source_lines)
        end

        if formatting_off then
            if line_number >= region_end then
                -- The enclosing block's "end" keyword is on this line; resume formatting.
                formatting_off = false
            else
                fmt_off_lines[line_number] = true
                if line_number > off_start and line_str:match("%-%-%s*fmt:%s*on") then
                    formatting_off = false
                end
            end
        end
    end

    return fmt_off_lines
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

-- Split a parameter-list string by top-level commas (not inside ()[]{}
-- and not inside string literals), trimming each parameter.
local function split_params(params_str: string): {string}
    local params: {string} = {}
    local depth = 0
    local in_string = false
    local string_char = ""
    local start = 1
    local i = 1
    while i <= #params_str do
        local ch = params_str:sub(i, i)
        if in_string then
            if ch == "\\" then
                i = i + 1  -- skip escaped character
            elseif ch == string_char then
                in_string = false
            end
        else
            if ch == '"' or ch == "'" then
                in_string = true
                string_char = ch
            elseif ch == "(" or ch == "[" or ch == "{" then
                depth = depth + 1
            elseif ch == ")" or ch == "]" or ch == "}" then
                depth = depth - 1
            elseif ch == "," and depth == 0 then
                local param = params_str:sub(start, i - 1):match("^%s*(.-)%s*$") or ""
                if param ~= "" then
                    table.insert(params, param)
                end
                start = i + 1
            end
        end
        i = i + 1
    end
    local last = params_str:sub(start):match("^%s*(.-)%s*$") or ""
    if last ~= "" then
        table.insert(params, last)
    end
    return params
end

-- ── AST-based wrapping ────────────────────────────────────────────────────────

-- Recursively walk every child node reachable from a Node.
-- Calls visit(child) for each child node encountered.
local function walk_children(node: parser.Node, visit: function(parser.Node))
    for _, child in ipairs(node) do visit(child) end
    if node.body   then visit(node.body)   end
    if node.e1     then visit(node.e1)     end
    if node.e2     then visit(node.e2)     end
    if node.key    then visit(node.key)    end
    if node.value  then visit(node.value)  end
    if node.args   then visit(node.args)   end
    if node.name   then visit(node.name)   end
    if node.exp    then visit(node.exp)    end
    if node.var    then visit(node.var)    end
    if node.from   then visit(node.from)   end
    if node.to     then visit(node.to)     end
    if node.step   then visit(node.step)   end
    if node.vars   then visit(node.vars)   end
    if node.exps   then visit(node.exps)   end
    if node.if_blocks then
        for _, block in ipairs(node.if_blocks) do visit(block) end
    end
end

-- Returns true if any descendant of node spans more than one source line.
-- Used to guard against joining table constructors whose items contain
-- multi-line sub-expressions (nested calls, nested tables, etc.).
local function has_multiline_descendant(node: parser.Node): boolean
    local function check(child: parser.Node): boolean
        if child.yend and child.yend > child.y then
            return true
        end
        local found = false
        local function visit(grandchild: parser.Node)
            if not found then
                found = check(grandchild)
            end
        end
        walk_children(child, visit)
        return found
    end
    local found = false
    local function visit(child: parser.Node)
        if not found then
            found = check(child)
        end
    end
    walk_children(node, visit)
    return found
end

-- Returns true when a multi-line table's last item line ends with a comma,
-- indicating the author explicitly wants the table kept in expanded form.
local function has_magic_trailing_comma(node: parser.Node, source_lines: {string}): boolean
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
    fmt_off_lines: {integer: boolean},
    result: {Span}
)
    if node.kind == "literal_table" then
        local is_safe = true
        for line = node.y, node.yend do
            if fmt_off_lines[line] then
                is_safe = false
                break
            end
            if lines[line] and lines[line]:find("%-%-") then
                is_safe = false
                break
            end
        end
        if is_safe and not has_multiline_descendant(node) and not has_magic_trailing_comma(node, lines) then
            table.insert(result, Span.new(node.y, node.x, node.yend, node.xend, false, false, true))
        end
        -- Still recurse into children to find nested simple tables
    end

    local function recurse(child: parser.Node)
        collect_table_spans(child, lines, fmt_off_lines, result)
    end
    walk_children(node, recurse)
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

-- Join a multi-line table span back to a single line.
-- Each body line is stripped of leading/trailing whitespace and trailing commas
-- are collected.  Returns the joined single-line content (just {…}).
local function join_table_span(span_lines: {string}): string
    -- span_lines[1] starts with "{", last line ends with "}"
    local open_brace = span_lines[1]:match("^(%{)")
    if not open_brace then
        return table.concat(span_lines, " ")
    end
    local items: {string} = {}
    for i = 1, #span_lines do
        local stripped = span_lines[i]:match("^%s*(.-)%s*$") or ""
        -- Remove surrounding braces from first/last contributions
        if i == 1 then
            stripped = stripped:sub(2) -- remove leading "{"
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        if i == #span_lines then
            -- remove trailing "}" (and optional trailing comma before it)
            stripped = stripped:gsub("%s*}%s*$", "")
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        -- strip trailing comma
        local item = stripped:gsub(",%s*$", "")
        item = item:match("^%s*(.-)%s*$") or ""
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return "{" .. table.concat(items, ", ") .. "}"
end

-- Split a single-line table span "{…}" into one item per line, indented
-- relative to the indent_prefix of the surrounding line.
local function split_table_span(span_content: string, indent_prefix: string): {string}
    -- strip braces
    local inner = span_content:match("^%{(.-)%}$") or span_content:sub(2, -2)
    inner = inner:match("^%s*(.-)%s*$") or ""
    local items = split_params(inner)
    if #items < 2 then
        return {span_content}
    end
    local inner_indent = indent_prefix .. "    "
    local result: {string} = {"{"}
    for _, item in ipairs(items) do
        table.insert(result, inner_indent .. item .. ",")
    end
    table.insert(result, indent_prefix .. "}")
    return result
end

-- Join a multi-line paren span back to a single line.
-- span_lines[1] starts with "(" (open_col); span_lines[last] ends with ")" (close_col).
-- Inner lines are stripped of whitespace and trailing commas.
local function join_paren_span(span_lines: {string}): string
    local items: {string} = {}
    for i = 1, #span_lines do
        local stripped = span_lines[i]:match("^%s*(.-)%s*$") or ""
        if i == 1 then
            stripped = stripped:sub(2)  -- remove leading "("
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        if i == #span_lines then
            -- span_lines[last] ends exactly at ")" so strip trailing ")"
            stripped = stripped:gsub("%)%s*$", "")
            stripped = stripped:match("^%s*(.-)%s*$") or ""
        end
        local item = stripped:gsub(",%s*$", "")
        item = item:match("^%s*(.-)%s*$") or ""
        if item ~= "" then
            table.insert(items, item)
        end
    end
    return "(" .. table.concat(items, ", ") .. ")"
end

-- Split a single-line paren span "(…)" into one item per line.
-- No trailing comma on the last item (unlike split_table_span).
local function split_paren_span(span_content: string, indent_prefix: string): {string}
    local inner = span_content:match("^%((.-)%)$") or span_content:sub(2, -2)
    inner = inner:match("^%s*(.-)%s*$") or ""
    local items = split_params(inner)
    if #items < 2 then
        return {span_content}
    end
    local inner_indent = indent_prefix .. "    "
    local result: {string} = {"("}
    for i, item in ipairs(items) do
        local suffix = i < #items and "," or ""
        table.insert(result, inner_indent .. item .. suffix)
    end
    table.insert(result, indent_prefix .. ")")
    return result
end

local function join_docs_with_separator(parts: {doc.Doc}, separator: doc.Doc): doc.Doc
    if #parts == 0 then
        return doc.concat({})
    end

    local result: {doc.Doc} = {parts[1]}
    for i = 2, #parts do
        table.insert(result, separator)
        table.insert(result, parts[i])
    end
    return doc.concat(result)
end

local function split_signature_paren_with_doc(
    span_content: string,
    indent_prefix: string
): {string}
    local inner = span_content:match("^%((.-)%)$") or span_content:sub(2, -2)
    inner = inner:match("^%s*(.-)%s*$") or ""
    local items = split_params(inner)
    if #items < 2 then
        return {span_content}
    end

    local item_docs: {doc.Doc} = {}
    for _, item in ipairs(items) do
        table.insert(item_docs, doc.text(item))
    end

    local separator = doc.concat({
        doc.text(","),
        doc.line(" "),
    })

    local grouped_items = doc.group(join_docs_with_separator(item_docs, separator))
    local signature_doc = doc.concat({
        doc.text("("),
        doc.indent(4, doc.concat({
            doc.line(""),
            grouped_items,
        })),
        doc.line(""),
        doc.text(")"),
    })

    return signature_doc:render(88, 0, #indent_prefix, true)
end

-- Split a paren span into lines, preferring compact form when possible.
-- Compact form keeps all args on a single indented line.
-- Per-arg split is used when compact would still exceed 88 chars.
--
-- Two compact paths:
-- 1. Call with trailing content (e.g. ") .. ms"): uses 3-space indent and only
--    fires when the span was already compact (3 lines), to avoid collapsing
--    intentionally expanded multi-arg calls whose ")" has trailing content.
-- 2. Signature or call with no trailing content: uses 4-space indent and
--    always fires when the args fit within the line limit.
local function split_paren_lines(
    span_content: string,
    indent_prefix: string,
    is_call: boolean,
    after: string,
    was_already_compact: boolean
): {string}
    if not is_call then
        return split_signature_paren_with_doc(span_content, indent_prefix)
    end

    if is_call and after ~= "" and not after:match("^,") and was_already_compact then
        local inner = span_content:match("^%((.-)%)$") or span_content:sub(2, -2)
        inner = inner:match("^%s*(.-)%s*$") or ""
        local compact_indent = indent_prefix .. "   "
        local items = split_params(inner)
        if #items >= 2 and #(compact_indent .. inner) <= 88 then
            return {"(", compact_indent .. inner, indent_prefix .. ")"}
        end
    end
    if not is_call or after == "" then
        local inner = span_content:match("^%((.-)%)$") or span_content:sub(2, -2)
        inner = inner:match("^%s*(.-)%s*$") or ""
        local compact_indent = indent_prefix .. "    "
        local items = split_params(inner)
        if #items >= 2 and #(compact_indent .. inner) <= 88 then
            return {"(", compact_indent .. inner, indent_prefix .. ")"}
        end
    end
    return split_paren_span(span_content, indent_prefix)
end

-- Returns true when any original line in the span's range was replaced by an
-- earlier rewrite.  Checking only the endpoints misses the case where an inner
-- same-line span expanded into multiple lines, shifting the outer span's
-- close_line reference to a now-different position in the result array.
local function span_overlaps_replaced(replaced_lines: {integer: boolean}, span: Span): boolean
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
    fmt_off_lines: {integer: boolean}
): boolean
    for line = open_line, close_line do
        if fmt_off_lines[line] then
            return true
        end
        if lines[line] and lines[line]:find("%-%-") then
            return true
        end
    end
    return false
end

-- Apply all collected spans (paren and table) in a single bottom-to-top pass.
-- Processing all span types together ensures that line-number shifts caused by
-- one rewrite (e.g. a signature compaction) do not invalidate the line numbers
-- of subsequent spans.  Each span carries is_call and is_table to select the
-- correct join/split functions.
local function apply_all_spans(
    lines: {string},
    spans: {Span},
    fmt_off_lines: {integer: boolean}
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
        elseif fmt_off_lines[span.open_line] then
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
                local after  = line_str:sub(span.close_col + 1)
                local span_content = line_str:sub(span.open_col, span.close_col)
                local indent_prefix = before:match("^(%s*)") or ""
                local split_lines: {string}
                if span.is_table then
                    split_lines = split_table_span(span_content, indent_prefix)
                else
                    split_lines = split_paren_lines(span_content, indent_prefix, span.is_call, after, true)
                end
                if #split_lines > 1 then
                    local new_lines: {string} = {}
                    table.insert(new_lines, before .. split_lines[1])
                    for i = 2, #split_lines - 1 do
                        table.insert(new_lines, split_lines[i])
                    end
                    table.insert(new_lines, split_lines[#split_lines] .. after)
                    local head: {string} = {}
                    local tail: {string} = {}
                    for i = 1, span.open_line - 1 do table.insert(head, result[i]) end
                    for i = span.open_line + 1, #result do table.insert(tail, result[i]) end
                    result = {}
                    for _, head_line in ipairs(head) do table.insert(result, head_line) end
                    for _, new_line in ipairs(new_lines) do table.insert(result, new_line) end
                    for _, tail_line in ipairs(tail) do table.insert(result, tail_line) end
                    replaced_lines[span.open_line] = true
                end
            end
        else
            local span_lines = extract_span_lines(result, span)
            local joined: string
            if span.is_table then
                joined = join_table_span(span_lines)
            else
                joined = join_paren_span(span_lines)
            end
            local before = result[span.open_line]:sub(1, span.open_col - 1)
            local after  = result[span.close_line]:sub(span.close_col + 1)
            local full_joined = before .. joined .. after
            local head: {string} = {}
            local tail: {string} = {}
            for i = 1, span.open_line - 1 do table.insert(head, result[i]) end
            for i = span.close_line + 1, #result do table.insert(tail, result[i]) end
            if #full_joined <= 88 then
                result = {}
                for _, line_str in ipairs(head) do table.insert(result, line_str) end
                table.insert(result, full_joined)
                for _, line_str in ipairs(tail) do table.insert(result, line_str) end
                for line = span.open_line, span.close_line do
                    replaced_lines[line] = true
                end
            else
                local indent_prefix = before:match("^(%s*)") or ""
                local split_lines: {string}
                if span.is_table then
                    split_lines = split_table_span(joined, indent_prefix)
                else
                    split_lines = split_paren_lines(joined, indent_prefix, span.is_call, after, #span_lines == 3)
                end
                if #split_lines > 1 then
                    local new_lines: {string} = {}
                    table.insert(new_lines, before .. split_lines[1])
                    for i = 2, #split_lines - 1 do
                        table.insert(new_lines, split_lines[i])
                    end
                    table.insert(new_lines, split_lines[#split_lines] .. after)
                    result = {}
                    for _, line_str in ipairs(head) do table.insert(result, line_str) end
                    for _, line_str in ipairs(new_lines) do table.insert(result, line_str) end
                    for _, line_str in ipairs(tail) do table.insert(result, line_str) end
                    for line = span.open_line, span.close_line do
                        replaced_lines[line] = true
                    end
                end
            end
        end
    end

    return result
end

local FUNCTION_DEF_KINDS: {tl.NodeKind: boolean} = {
    ["local_function"]  = true,
    ["global_function"] = true,
    ["record_function"] = true,
    ["function"]        = true,
}

-- Walk the AST collecting Spans for function parameter lists.
local function collect_signature_spans(
    node: parser.Node,
    lines: {string},
    fmt_off_lines: {integer: boolean},
    result: {Span}
)
    if FUNCTION_DEF_KINDS[node.kind] and node.args then
        local args = node.args
        if not span_range_is_unsafe(args.y, args.yend, lines, fmt_off_lines)
            and not has_multiline_descendant(args)
        then
            table.insert(result, Span.new(args.y, args.x, args.yend, args.xend, false, true, false))
        end
    end
    local function recurse(child: parser.Node)
        collect_signature_spans(child, lines, fmt_off_lines, result)
    end
    walk_children(node, recurse)
end

-- Walk the AST collecting Spans for function call argument lists.
-- Skips calls that use string-call or table-call syntax (no "(" on the line).
local function collect_call_spans(
    node: parser.Node,
    lines: {string},
    fmt_off_lines: {integer: boolean},
    result: {Span}
)
    if node.kind == "op" and node.op ~= nil and node.op.op == "@funcall" and node.e2 ~= nil then
        local args = node.e2
        local args_line = lines[args.y]
        if args_line and args_line:sub(args.x, args.x) == "(" then
            if not span_range_is_unsafe(args.y, args.yend, lines, fmt_off_lines)
                and not has_multiline_descendant(args)
            then
                table.insert(result, Span.new(args.y, args.x, args.yend, args.xend, true, false, false))
            end
        end
    end
    local function recurse(child: parser.Node)
        collect_call_spans(child, lines, fmt_off_lines, result)
    end
    walk_children(node, recurse)
end

-- Walk only the immediate children of the AST root (top-level statements) and
-- return a RequireDecl for each local_declaration or local_type whose sole
-- expression is a bare require("<path>") call.  Requires inside function
-- bodies are ignored because only the top-level list is walked.
local function collect_require_decls(ast: parser.Node): {RequireDecl}
    local result: {RequireDecl} = {}
    for _, node in ipairs(ast) do
        local call_node: parser.Node
        if node.kind == "local_declaration"
            and node.exps ~= nil
            and node.exps[1] ~= nil
        then
            call_node = node.exps[1]
        elseif node.kind == "local_type" and node.value ~= nil then
            call_node = node.value
        end
        if call_node ~= nil
            and call_node.kind == "op"
            and call_node.op ~= nil
            and call_node.op.op == "@funcall"
            and call_node.e1 ~= nil
            and call_node.e1.tk == "require"
            and call_node.e2 ~= nil
            and #call_node.e2 == 1
            and call_node.e2[1].kind == "string"
        then
            local module_path = call_node.e2[1].conststr or ""
            -- Use the closing line of the argument list as last_line so that
            -- multi-line declarations (local x =\n    require("...")) are
            -- captured as a range and sorted as a unit.
            local last_line = call_node.e2.yend or call_node.e2.y or node.y
            table.insert(result, RequireDecl.new(node.y, last_line, module_path))
        end
    end
    return result
end

-- Sort contiguous blocks of top-level require declarations alphabetically by
-- module path.  Lines inside fmt-off regions are left in place.
local function sort_require_blocks(
    lines: {string},
    fmt_off_lines: {integer: boolean},
    require_decls: {RequireDecl}
): {string}
    local decl_by_start: {integer: RequireDecl} = {}
    for _, decl in ipairs(require_decls) do
        decl_by_start[decl.first_line] = decl
    end

    local result: {string} = {}
    local i = 1
    while i <= #lines do
        local decl = decl_by_start[i]
        if fmt_off_lines[i] or decl == nil then
            table.insert(result, lines[i])
            i = i + 1
        else
            local block: {RequireDecl} = {}
            local block_end = 0
            local current = decl
            while current ~= nil do
                table.insert(block, current)
                block_end = current.last_line
                local next_line = current.last_line + 1
                local next_decl = decl_by_start[next_line]
                if next_decl == nil or fmt_off_lines[next_line] then
                    break
                end
                current = next_decl
            end
            local function by_module_path(first: RequireDecl, second: RequireDecl): boolean
                return first.module_path < second.module_path
            end
            table.sort(block, by_module_path)
            for _, sorted_decl in ipairs(block) do
                for line = sorted_decl.first_line, sorted_decl.last_line do
                    table.insert(result, lines[line])
                end
            end
            i = block_end + 1
        end
    end
    return result
end

local function build_formatter_context(
    source: string,
    filename: string,
    ast: parser.Node
): FormatterContext
    local source_blocks = blocks.collect_from_ast(ast)
    local require_decls = collect_require_decls(ast)
    local tokens, _ = tl.lex(source, filename)
    local edits = collect_all_edits(tokens)
    local lines = split_preserving_trailing_newline(source)
    local fmt_off_lines = collect_fmt_off_lines(lines, source_blocks)

    return FormatterContext.new(
        source,
        filename,
        ast,
        source_blocks,
        require_decls,
        tokens,
        edits,
        lines,
        fmt_off_lines
    )
end

local function run_lexical_whitespace_pass(
    context: FormatterContext
): {string}
    local result: {string} = {}
    for i, line_str in ipairs(context.lines) do
        if context.fmt_off_lines[i] then
            table.insert(result, line_str)
        else
            table.insert(result, apply_edits_to_line(line_str, i, context.edits))
        end
    end
    return result
end

local function run_line_cleanup_pass(
    context: FormatterContext,
    lines: {string}
): {string}
    local result: {string} = {}
    for i, line_str in ipairs(lines) do
        if context.fmt_off_lines[i] then
            table.insert(result, line_str)
        else
            local cleaned = expand_tabs(line_str)
            cleaned = strip_trailing_spaces(cleaned)
            table.insert(result, cleaned)
        end
    end
    return result
end

local function run_reorder_pass(
    context: FormatterContext,
    lines: {string}
): {string}
    -- Require sorting runs before span rewrites so the AST line numbers
    -- collected from the original source are still accurate.
    -- Token edits preserve line count; span rewrites may not.
    return sort_require_blocks(lines, context.fmt_off_lines, context.require_decls)
end

local function collect_structural_spans(
    context: FormatterContext
): {Span}
    local spans: {Span} = {}
    collect_signature_spans(context.ast, context.lines, context.fmt_off_lines, spans)
    collect_call_spans(context.ast, context.lines, context.fmt_off_lines, spans)
    collect_table_spans(context.ast, context.lines, context.fmt_off_lines, spans)
    return spans
end

local function run_structural_span_pass(
    context: FormatterContext,
    lines: {string},
    spans: {Span}
): {string}
    return apply_all_spans(lines, spans, context.fmt_off_lines)
end

local function run_final_cleanup_pass(_context: FormatterContext, lines: {string}): {string}
    return collapse_blank_lines(lines)
end

function rewriter.rewrite(source: string, filename: string): Rewrite
    local ast, parse_errors = parser.parse(source, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source, false, parse_errors)
    end

    local context = build_formatter_context(source, filename, ast)

    local output_lines = run_lexical_whitespace_pass(context)
    output_lines = run_line_cleanup_pass(context, output_lines)
    output_lines = run_reorder_pass(context, output_lines)

    local structural_spans = collect_structural_spans(context)
    output_lines = run_structural_span_pass(context, output_lines, structural_spans)
    output_lines = run_final_cleanup_pass(context, output_lines)

    local output = table.concat(output_lines, "\n")
    return Rewrite.new(output, output ~= source, {})
end

return rewriter
