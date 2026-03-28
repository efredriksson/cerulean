local blocks = require("formatter.blocks")
local tl = require("tl")

local rewriter = {}

local record Edit
    line: integer
    col_start: integer
    col_end: integer
    replacement: string
end

function Edit.new(
    line: integer,
    col_start: integer,
    col_end: integer,
    replacement: string
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

function Rewrite.new(
    output: string,
    changed: boolean,
    parse_errors: {tl.Error}
): Rewrite
    local self: Rewrite = setmetatable({}, { __index = Rewrite })
    self.output = output
    self.changed = changed
    self.parse_errors = parse_errors
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
                            edits,
                            Edit.new(token.y, prev_end + 1, token.x - 1, " ")
                        )
                    end
                end
                if next_token.y == token.y then
                    local op_end = token.x + #token.tk - 1
                    local gap_after = next_token.x - op_end - 1
                    if gap_after ~= 1 then
                        table.insert(
                            edits,
                            Edit.new(token.y, op_end + 1, next_token.x - 1, " ")
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
                    edits,
                    Edit.new(current.y, comma_end, next_token.x - 1, " ")
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

local function apply_edits_to_line(
    line_str: string,
    line_number: integer,
    edits: {Edit}
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
    source_blocks: {blocks.Block},
    line: integer,
    last_line: integer
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

local function is_function_signature_line(line_str: string): boolean
    return line_str:match("^%s*local%s+function%s") ~= nil or
           line_str:match("^%s*function%s") ~= nil
end

-- Returns the 1-based position of the closing ")" that matches the "(" at
-- open_pos, or 0 when the line has no matching close paren.
local function find_close_paren(line_str: string, open_pos: integer): integer
    local depth = 0
    for i = open_pos, #line_str do
        local ch = line_str:sub(i, i)
        if ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
    end
    return 0
end

-- Split a parameter-list string by top-level commas (not inside ()[]{}),
-- trimming each parameter.
local function split_params(params_str: string): {string}
    local params: {string} = {}
    local depth = 0
    local start = 1
    for i = 1, #params_str do
        local ch = params_str:sub(i, i)
        if ch == "(" or ch == "[" or ch == "{" then
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
    local last = params_str:sub(start):match("^%s*(.-)%s*$") or ""
    if last ~= "" then
        table.insert(params, last)
    end
    return params
end

-- Build the canonical single-line form of a (possibly multi-line) signature.
-- signature_lines[1] ends with "(" (the opening paren line).
-- The last element contains the closing ")" possibly followed by a return type.
local function join_signature_lines(signature_lines: {string}): string
    local header = signature_lines[1]:match("^(.-%()%s*$") or signature_lines[1]
    local body_parts: {string} = {}
    local tail = ""
    for i = 2, #signature_lines do
        local stripped = signature_lines[i]:match("^%s*(.-)%s*$") or ""
        if stripped:sub(1, 1) == ")" then
            tail = stripped
        else
            -- Strip trailing comma before collecting
            local param = stripped:gsub(",%s*$", "")
            if param ~= "" then
                table.insert(body_parts, param)
            end
        end
    end
    return header .. table.concat(body_parts, ", ") .. tail
end

-- Given a single-line signature that is longer than 88 characters, reformat
-- it to one parameter per line.  Returns the single line unchanged when it has
-- fewer than two parameters or when the line is short enough already.
local function wrap_one_signature(line_str: string): {string}
    local open_pos = line_str:find("%(")
    if not open_pos then
        return {line_str}
    end
    local close_pos = find_close_paren(line_str, open_pos)
    if close_pos == 0 then
        return {line_str}
    end
    local header    = line_str:sub(1, open_pos)
    local params_str = line_str:sub(open_pos + 1, close_pos - 1)
    local after     = line_str:sub(close_pos)
    local params    = split_params(params_str)
    if #params < 2 then
        return {line_str}
    end
    local indent = (header:match("^(%s*)") or "")
    local result: {string} = {header}
    for i, param in ipairs(params) do
        local suffix = i < #params and "," or ""
        table.insert(result, indent .. "    " .. param .. suffix)
    end
    table.insert(result, indent .. after)
    return result
end

-- Reformat function signatures: join already-wrapped ones to one line when
-- they fit, then split any single-line signatures that exceed 88 characters.
local function wrap_function_signatures(lines: {string}, fmt_off_lines: {integer: boolean}): {string}
    local result: {string} = {}
    local i = 1
    while i <= #lines do
        local line_str = lines[i]
        local is_sig = is_function_signature_line(line_str) and not fmt_off_lines[i]
        -- Detect an already-wrapped multi-line signature: sig line ends with "("
        if is_sig and line_str:sub(-1) == "(" then
            local indent = (line_str:match("^(%s*)") or "")
            local sig_lines: {string} = {line_str}
            local j = i + 1
            while j <= #lines do
                table.insert(sig_lines, lines[j])
                if lines[j]:match("^" .. indent .. "%)") then
                    break
                end
                j = j + 1
            end
            local joined = join_signature_lines(sig_lines)
            local final_lines: {string}
            if #joined <= 88 then
                final_lines = {joined}
            else
                final_lines = wrap_one_signature(joined)
            end
            for _, out_line in ipairs(final_lines) do
                table.insert(result, out_line)
            end
            i = j + 1
        elseif is_sig and #line_str > 88 then
            for _, out_line in ipairs(wrap_one_signature(line_str)) do
                table.insert(result, out_line)
            end
            i = i + 1
        else
            table.insert(result, line_str)
            i = i + 1
        end
    end
    return result
end

-- Returns the 1-based position of the closing "}" that matches the "{" at
-- open_pos, or 0 when the line has no matching close brace.
local function find_close_brace(line_str: string, open_pos: integer): integer
    local depth = 0
    for i = open_pos, #line_str do
        local ch = line_str:sub(i, i)
        if ch == "{" then
            depth = depth + 1
        elseif ch == "}" then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
    end
    return 0
end

-- Build the canonical single-line form of a (possibly multi-line) table constructor.
-- table_lines[1] ends with "{".  The last element starts with the closing "}".
local function join_table_lines(table_lines: {string}): string
    local header = table_lines[1]:match("^(.-%{)%s*$") or table_lines[1]
    local items: {string} = {}
    local tail = ""
    for i = 2, #table_lines do
        local stripped = table_lines[i]:match("^%s*(.-)%s*$") or ""
        if stripped:sub(1, 1) == "}" then
            tail = stripped
        else
            local item = stripped:gsub(",%s*$", "")
            if item ~= "" then
                table.insert(items, item)
            end
        end
    end
    return header .. table.concat(items, ", ") .. tail
end

-- Returns true when a table element string contains a string literal.
-- Used to avoid wrapping tables whose elements contain quotes, since
-- find_close_brace cannot reliably skip over string content.
local function contains_string_literal(s: string): boolean
    return s:find('"') ~= nil or s:find("'") ~= nil
end

-- Given a single-line table constructor longer than 88 characters, reformat it
-- to one element per line.  Returns the single line unchanged when it has fewer
-- than two elements, when no "= {…}" pattern is found, or when any element
-- contains a string literal (which would confuse brace-depth counting).
local function wrap_one_table(line_str: string): {string}
    local eq_pos = line_str:find("=%s*{")
    if not eq_pos then
        return {line_str}
    end
    local open_pos = line_str:find("{", eq_pos)
    if not open_pos then
        return {line_str}
    end
    local close_pos = find_close_brace(line_str, open_pos)
    if close_pos == 0 then
        return {line_str}
    end
    local header = line_str:sub(1, open_pos)
    local items_str = line_str:sub(open_pos + 1, close_pos - 1)
    -- Skip tables whose elements contain string literals: brace counting is
    -- unreliable when "}" or "{" appear inside quoted strings.
    if contains_string_literal(items_str) then
        return {line_str}
    end
    local after_brace = line_str:sub(close_pos + 1)
    local items = split_params(items_str)
    if #items < 2 then
        return {line_str}
    end
    local indent = (line_str:match("^(%s*)") or "")
    local result: {string} = {header}
    for _, item in ipairs(items) do
        table.insert(result, indent .. "    " .. item .. ",")
    end
    table.insert(result, indent .. "}" .. after_brace)
    return result
end

-- Reformat table constructors: join already-wrapped ones to one line when
-- they fit, then split any single-line constructors that exceed 88 characters.
-- Only applies to tables assigned with "= {…}" syntax.
local function wrap_table_literals(lines: {string}, fmt_off_lines: {integer: boolean}): {string}
    local result: {string} = {}
    local i = 1
    while i <= #lines do
        local line_str = lines[i]
        if fmt_off_lines[i] then
            table.insert(result, line_str)
            i = i + 1
        elseif line_str:match("=%s*{%s*$") then
            local indent = (line_str:match("^(%s*)") or "")
            local table_lines: {string} = {line_str}
            local j = i + 1
            local is_simple = true
            while j <= #lines do
                local body_line = lines[j]
                -- Skip joining if any body line contains nested structure,
                -- string literals, or comments.  Parentheses indicate a
                -- function call that may span multiple lines.
                if body_line:find("[{(]") or contains_string_literal(body_line) or body_line:find("%-%-") then
                    is_simple = false
                end
                table.insert(table_lines, body_line)
                if body_line:match("^" .. indent .. "}") then
                    break
                end
                j = j + 1
            end
            if is_simple then
                local joined = join_table_lines(table_lines)
                local final_lines: {string}
                if #joined <= 88 then
                    final_lines = {joined}
                else
                    final_lines = wrap_one_table(joined)
                end
                for _, out_line in ipairs(final_lines) do
                    table.insert(result, out_line)
                end
            else
                for _, tl_line in ipairs(table_lines) do
                    table.insert(result, tl_line)
                end
            end
            i = j + 1
        elseif #line_str > 88 and line_str:find("=%s*{") ~= nil then
            local wrapped = wrap_one_table(line_str)
            for _, out_line in ipairs(wrapped) do
                table.insert(result, out_line)
            end
            i = i + 1
        else
            table.insert(result, line_str)
            i = i + 1
        end
    end
    return result
end

-- Build the canonical single-line form of an already-wrapped function call.
-- call_lines[1] ends with "(".  The last element starts with ")".
-- Body lines may each contain one or many comma-separated arguments.
local function join_call_lines(call_lines: {string}): string
    local header = call_lines[1]:match("^(.-%()%s*$") or call_lines[1]
    local body_parts: {string} = {}
    local tail = ""
    for i = 2, #call_lines do
        local stripped = call_lines[i]:match("^%s*(.-)%s*$") or ""
        if stripped:sub(1, 1) == ")" then
            tail = stripped
        else
            local arg_text = stripped:gsub(",%s*$", "")
            local args = split_params(arg_text)
            for _, each_arg in ipairs(args) do
                table.insert(body_parts, each_arg)
            end
        end
    end
    return header .. table.concat(body_parts, ", ") .. tail
end

-- Given a single-line function call longer than 88 characters, reformat it to
-- one argument per line.  Returns the line unchanged when fewer than two
-- arguments are present.
local function wrap_one_call(line_str: string): {string}
    local open_pos = line_str:find("%(")
    if not open_pos then
        return {line_str}
    end
    local close_pos = find_close_paren(line_str, open_pos)
    if close_pos == 0 then
        return {line_str}
    end
    local header = line_str:sub(1, open_pos)
    local params_str = (line_str:sub(open_pos + 1, close_pos - 1):match("^%s*(.-)%s*$") or "")
    local after = line_str:sub(close_pos)
    local params = split_params(params_str)
    if #params < 2 then
        return {line_str}
    end
    local indent = (line_str:match("^(%s*)") or "")
    local result: {string} = {header}
    for i, param in ipairs(params) do
        local suffix = i < #params and "," or ""
        table.insert(result, indent .. "    " .. param .. suffix)
    end
    table.insert(result, indent .. after)
    return result
end

-- Reformat function calls: join already-wrapped ones to one line when they fit,
-- then split any single-line calls that exceed 88 characters.
-- Function definition lines are skipped (handled by wrap_function_signatures).
local function wrap_function_calls(lines: {string}, fmt_off_lines: {integer: boolean}): {string}
    local result: {string} = {}
    local i = 1
    while i <= #lines do
        local line_str = lines[i]
        local is_sig = is_function_signature_line(line_str)
        if fmt_off_lines[i] then
            table.insert(result, line_str)
            i = i + 1
        elseif not is_sig and line_str:sub(-1) == "(" and not line_str:match("^%s*%-%-") then
            -- Already-wrapped call: collect continuation lines until closing ")"
            -- that sits at the opening indentation level on its own line.
            local indent = (line_str:match("^(%s*)") or "")
            local open_indent_len = #indent
            local call_lines: {string} = {line_str}
            local j = i + 1
            local is_clean = true
            while j <= #lines do
                local body_line = lines[j]
                local body_indent_len = #(body_line:match("^(%s*)") or "")
                if body_line:match("^" .. indent .. "%)") then
                    table.insert(call_lines, body_line)
                    break
                elseif body_indent_len <= open_indent_len then
                    -- `)` not on its own line or structure is unexpected — bail.
                    is_clean = false
                    break
                elseif body_line:sub(-1) == "(" then
                    -- Nested wrapped call inside args — too complex to rejoin.
                    is_clean = false
                end
                table.insert(call_lines, body_line)
                j = j + 1
            end
            if is_clean and #call_lines >= 2 then
                local joined = join_call_lines(call_lines)
                local final_lines: {string}
                if #joined <= 88 then
                    final_lines = {joined}
                else
                    local rewrapped = wrap_one_call(joined)
                    -- Only accept re-wrap when it changed something (i.e. ≥2
                    -- top-level args were found); otherwise keep original form.
                    if #rewrapped == 1 and rewrapped[1] == joined then
                        final_lines = call_lines
                    else
                        final_lines = rewrapped
                    end
                end
                for _, out_line in ipairs(final_lines) do
                    table.insert(result, out_line)
                end
                i = j + 1
            else
                -- Emit opening line only; remaining lines handled in subsequent
                -- iterations.
                table.insert(result, line_str)
                i = i + 1
            end
        elseif not is_sig and #line_str > 88 and line_str:find("%(") and not line_str:match("^%s*%-%-") then
            local wrapped = wrap_one_call(line_str)
            for _, out_line in ipairs(wrapped) do
                table.insert(result, out_line)
            end
            i = i + 1
        else
            table.insert(result, line_str)
            i = i + 1
        end
    end
    return result
end

-- Matches lines of the form:  local [type] <name> = require("<path>")
-- Captures the module path string so blocks can be sorted by it.
local REQUIRE_LINE_PATTERN = '^(%s*)local%s+.-%s*=%s*require%s*%("([^"]+)"%s*%)'

local function is_require_line(line_str: string): boolean
    return line_str:match(REQUIRE_LINE_PATTERN) ~= nil
end

local function require_module_path(line_str: string): string
    local _, path = line_str:match(REQUIRE_LINE_PATTERN)
    return path or ""
end

-- Sort contiguous blocks of require lines alphabetically by module path.
-- Lines inside fmt-off regions are left in place.
local function sort_require_blocks(lines: {string}, fmt_off_lines: {integer: boolean}): {string}
    local result: {string} = {}
    local i = 1
    while i <= #lines do
        if fmt_off_lines[i] or not is_require_line(lines[i]) then
            table.insert(result, lines[i])
            i = i + 1
        else
            local block_start = i
            while i <= #lines and not fmt_off_lines[i] and is_require_line(lines[i]) do
                i = i + 1
            end
            local block: {string} = {}
            for j = block_start, i - 1 do
                table.insert(block, lines[j])
            end
            local function by_module_path(first: string, second: string): boolean
                return require_module_path(first) < require_module_path(second)
            end
            table.sort(block, by_module_path)
            for _, line_str in ipairs(block) do
                table.insert(result, line_str)
            end
        end
    end
    return result
end

function rewriter.rewrite(source: string, filename: string): Rewrite
    local source_blocks, parse_errors = blocks.parse(source, filename)
    if #parse_errors > 0 then
        return Rewrite.new(source, false, parse_errors)
    end

    local tokens, _ = tl.lex(source, filename)
    local edits = collect_all_edits(tokens)

    local lines = split_preserving_trailing_newline(source)
    local fmt_off_lines = collect_fmt_off_lines(lines, source_blocks)

    local output_lines: {string} = {}
    for i, line_str in ipairs(lines) do
        if fmt_off_lines[i] then
            table.insert(output_lines, line_str)
        else
            local result = apply_edits_to_line(line_str, i, edits)
            result = expand_tabs(result)
            result = strip_trailing_spaces(result)
            table.insert(output_lines, result)
        end
    end

    output_lines = wrap_function_signatures(output_lines, fmt_off_lines)
    output_lines = wrap_function_calls(output_lines, fmt_off_lines)
    output_lines = wrap_table_literals(output_lines, fmt_off_lines)
    output_lines = collapse_blank_lines(output_lines)
    output_lines = sort_require_blocks(output_lines, fmt_off_lines)
    local output = table.concat(output_lines, "\n")
    return Rewrite.new(output, output ~= source, {})
end

return rewriter
