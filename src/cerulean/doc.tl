-- Wadler-Lindig pretty-printer: groups try flat first, break when they don't fit.
local fmt_logger = require("cerulean.fmt_logger")

local interface Doc is fmt_logger.Stringable
    kind: string
    render: function(self, max_width: integer, indent_width: integer): string
end

local record DocText is Doc where self.kind == "text"
    text: string
end

local record DocRaw is Doc where self.kind == "raw"
    raw_lines: {string}
end

local record DocClosed is Doc where self.kind == "close"
    close_text: string
    close_flat_sep: string
end

local record DocLine is Doc where self.kind == "line"
    flat_text: string
end

local record DocHardLine is Doc where self.kind == "hardline"
end

local record DocBlankLine is Doc where self.kind == "blankline"
end

local record DocBreakText is Doc where self.kind == "break_text"
    flat_text: string
    broken_text: string
end

local record DocTrimStart is Doc where self.kind == "trim_start"
end

local record DocTrimEnd is Doc where self.kind == "trim_end"
end

local record DocGroup is Doc where self.kind == "group"
    child: Doc
    group_id: integer
    should_break: boolean
end

local record DocConcat is Doc where self.kind == "concat"
    parts: {Doc}
end

local record DocIndent is Doc where self.kind == "indent"
    child: Doc
end

local record DocIfBreak is Doc where self.kind == "if_break"
    flat_child: Doc
    break_child: Doc
    target_group_id: integer
end

local record DocBreakParent is Doc where self.kind == "break_parent"
end

local doc = {Doc = Doc}

local record GroupRef
    group_id: integer
end

local next_group_id = 0

local function new_group_id(): integer
    next_group_id = next_group_id + 1
    return next_group_id
end

function GroupRef.new(): GroupRef
    local self: GroupRef = setmetatable({}, {__index = GroupRef})
    self.group_id = new_group_id()
    return self
end

local record RenderCommand
    node: Doc
    indent: integer
    flat: boolean
    current_group_id: integer
end

function RenderCommand.new(
    node: Doc, indent: integer, flat: boolean, current_group_id?: integer
): RenderCommand
    local self: RenderCommand = setmetatable({}, {__index = RenderCommand})
    self.node = node
    self.indent = indent
    self.flat = flat
    self.current_group_id = current_group_id
    return self
end

local record RenderState
    lines: {string}
    current_line: string
    column: integer
    max_width: integer
    indent_width: integer
    broken_groups: {integer: boolean}
    line_suffixes: {RenderCommand}
    marked_column: integer
end

local function append_text(state: RenderState, text: string)
    state.current_line = state.current_line .. text
    state.column = state.column + #text
end

local function rstrip_whitespace(text: string): string
    return (text:gsub("%s+$", ""))
end

local function break_line(state: RenderState, indent: integer)
    table.insert(state.lines, rstrip_whitespace(state.current_line))
    state.current_line = string.rep(" ", indent)
    state.column = indent
end

local function clone_commands(commands: {RenderCommand}): {RenderCommand}
    local copied: {RenderCommand} = {}
    for _, command in ipairs(commands) do
        table.insert(copied, command)
    end
    return copied
end

local function push_concat_parts(
    commands: {RenderCommand},
    parts: {Doc},
    indent: integer,
    flat: boolean,
    current_group_id?: integer
)
    for index = #parts, 1, -1 do
        table.insert(
            commands, RenderCommand.new(parts[index], indent, flat, current_group_id)
        )
    end
end

local function should_take_break_branch(
    target_group_id: integer,
    current_group_id: integer,
    flat: boolean,
    broken_groups: {integer: boolean}
): boolean
    if target_group_id ~= nil then
        return broken_groups[target_group_id] == true
    end

    if current_group_id ~= nil and broken_groups[current_group_id] == true then
        return true
    end

    return not flat
end

-- Pre-mark groups before rendering so fits() skips break_parent traversal during width checks.
local function propagate_breaks(node: Doc): boolean
    if node is DocBreakParent then
        return true
    elseif node is DocGroup then
        local child_propagate = propagate_breaks(node.child)
        node.should_break = node.should_break or child_propagate
        return false
    elseif node is DocConcat then
        -- Must visit every part: an early return would leave later groups unmarked,
        -- so their should_break stays false and fits() treats them as flat incorrectly.
        local any_part_breaks = false
        for _, part in ipairs(node.parts or {}) do
            if propagate_breaks(part) then
                any_part_breaks = true
            end
        end
        return any_part_breaks
    elseif node is DocIndent then
        return propagate_breaks(node.child)
    elseif node is DocIfBreak then
        -- Same constraint: evaluate both sides before combining.
        local break_propagates = propagate_breaks(node.break_child)
        local flat_propagates = propagate_breaks(node.flat_child)
        return break_propagates or flat_propagates
    end
    return false
end

local function is_line(node: Doc): boolean
    return node is DocLine or node is DocHardLine or node is DocBlankLine
end

local function has_line_break_opportunity(node: Doc): boolean
    if is_line(node) or node is DocClosed or node is DocBreakParent then
        return true
    end
    if node is DocRaw then
        return false
    end

    if node is DocConcat then
        for _, part in ipairs(node.parts or {}) do
            if has_line_break_opportunity(part) then
                return true
            end
        end
        return false
    end

    if node is DocTrimEnd then
        return true
    end

    if node is DocIndent or node is DocGroup then
        if node.child == nil then
            return false
        end
        return has_line_break_opportunity(node.child)
    end

    if node is DocIfBreak then
        if node.break_child ~= nil and has_line_break_opportunity(node.break_child) then
            return true
        end
        if node.flat_child ~= nil and has_line_break_opportunity(node.flat_child) then
            return true
        end
        return false
    end

    return false
end

local function push_pending_line_suffixes(
    commands: {RenderCommand}, state: RenderState
): integer
    if #state.line_suffixes == 0 then
        return 0
    end

    local suffix_count = #state.line_suffixes
    for index = #state.line_suffixes, 1, -1 do
        table.insert(commands, state.line_suffixes[index])
    end
    state.line_suffixes = {}
    return suffix_count
end

local function write_raw_lines(state: RenderState, raw_lines: {string})
    assert(
        state.current_line:match("^%s*$"), "doc.raw must be emitted at line boundary"
    )
    for i, raw_line in ipairs(raw_lines) do
        state.current_line = raw_line
        state.column = #raw_line
        if i < #raw_lines then
            table.insert(state.lines, state.current_line)
        end
    end
end

local function fits(
    remaining_width: integer,
    commands: {RenderCommand},
    broken_groups: {integer: boolean},
    indent_width: integer
): boolean
    if remaining_width < 0 then
        return false
    end

    while #commands > 0 do
        local command = table.remove(commands)
        local node = command.node
        local flat = command.flat
        local current_group_id = command.current_group_id

        if node is DocText then
            if node.text:find("\n") then
                return false
            end
            remaining_width = remaining_width - #node.text
        elseif node is DocRaw then
            return false
        elseif node is DocBreakText then
            if flat then
                remaining_width = remaining_width - #node.flat_text
            else
                remaining_width = remaining_width - #node.broken_text
            end
        elseif node is DocLine then
            if flat then
                remaining_width = remaining_width - #node.flat_text
            else
                return true
            end
        elseif node is DocTrimEnd and not flat then
            return true
        elseif node is DocIfBreak then
            local take_break_branch = should_take_break_branch(
                node.target_group_id, current_group_id, flat, broken_groups
            )
            local chosen = take_break_branch and node.break_child or node.flat_child
            table.insert(
                commands,
                RenderCommand.new(chosen, command.indent, flat, current_group_id)
            )
        elseif node is DocBreakParent then
            -- propagate_breaks already set group.should_break; nothing to measure here.
        elseif node is DocHardLine then
            return true
        elseif node is DocBlankLine then
            if not flat then
                return true
            end
        elseif node is DocClosed then
            if flat then
                remaining_width = remaining_width - #node.close_text - #node.close_flat_sep
            else
                return true
            end
        elseif node is DocConcat then
            push_concat_parts(
                commands, node.parts or {}, command.indent, flat, current_group_id
            )
        elseif node is DocIndent then
            table.insert(
                commands,
                RenderCommand.new(
                    node.child, command.indent + indent_width, flat, current_group_id
                )
            )
        elseif node is DocGroup then
            if flat and node.should_break then
                return false
            end
            local group_id = node.group_id or current_group_id
            table.insert(
                commands, RenderCommand.new(node.child, command.indent, flat, group_id)
            )
        end

        if remaining_width < 0 then
            return false
        end
    end

    return true
end

local function render_doc(root: Doc, state: RenderState)
    local commands: {RenderCommand} = {
        RenderCommand.new(root, 0, false, nil),
    }

    while #commands > 0 or #state.line_suffixes > 0 do
        if #commands == 0 then
            local suffix_count = push_pending_line_suffixes(commands, state)
            if suffix_count == 0 then
                break
            end
        end

        local command = table.remove(commands)
        local node = command.node
        local indent = command.indent
        local node_flat = command.flat
        local current_group_id = command.current_group_id

        if node is DocText then
            append_text(state, node.text or "")
        elseif node is DocRaw then
            write_raw_lines(state, node.raw_lines or {})
        elseif node is DocClosed then
            if node_flat then
                if
                    string.sub(
                        state.current_line, -#node.close_flat_sep
                    ) ~= node.close_flat_sep
                then
                    append_text(state, node.close_flat_sep)
                end
                append_text(state, node.close_text)
            else
                local indent_text = string.rep(" ", indent)
                if state.current_line:match("^%s*$") ~= nil then
                    state.current_line = indent_text
                    state.column = indent
                elseif state.current_line ~= indent_text then
                    local suffix_count = push_pending_line_suffixes(commands, state)
                    if suffix_count > 0 then
                        table.insert(commands, #commands - suffix_count + 1, command)
                    else
                        break_line(state, indent)
                    end
                end
                append_text(state, node.close_text)
            end
        elseif node is DocBreakText then
            if node_flat then
                append_text(state, node.flat_text or "")
            else
                append_text(state, node.broken_text or "")
            end
        elseif node is DocIfBreak then
            local take_break_branch = should_take_break_branch(
                node.target_group_id, current_group_id, node_flat, state.broken_groups
            )
            local chosen = take_break_branch and node.break_child or node.flat_child
            table.insert(
                commands, RenderCommand.new(chosen, indent, node_flat, current_group_id)
            )
        elseif node is DocBreakParent then
            if current_group_id ~= nil then
                state.broken_groups[current_group_id] = true
            end
        elseif node is DocLine then
            if node_flat then
                append_text(state, node.flat_text or "")
            else
                local suffix_count = push_pending_line_suffixes(commands, state)
                if suffix_count > 0 then
                    table.insert(commands, #commands - suffix_count + 1, command)
                else
                    break_line(state, indent)
                end
            end
        elseif node is DocTrimStart then
            state.marked_column = state.column
        elseif node is DocTrimEnd then
            if state.column > state.marked_column then
                if not node_flat then
                    local suffix_count = push_pending_line_suffixes(commands, state)
                    if suffix_count > 0 then
                        table.insert(commands, #commands - suffix_count + 1, command)
                    else
                        break_line(state, indent)
                    end
                end
            end
        elseif node is DocHardLine then
            local suffix_count = push_pending_line_suffixes(commands, state)
            if suffix_count > 0 then
                table.insert(commands, #commands - suffix_count + 1, command)
            else
                break_line(state, indent)
            end
        elseif node is DocBlankLine then
            if not node_flat then
                local suffix_count = push_pending_line_suffixes(commands, state)
                if suffix_count > 0 then
                    table.insert(commands, #commands - suffix_count + 1, command)
                else
                    table.insert(state.lines, state.current_line)
                    table.insert(state.lines, "")
                    state.current_line = string.rep(" ", indent)
                    state.column = indent
                end
            end
        elseif node is DocConcat then
            push_concat_parts(
                commands, node.parts or {}, indent, node_flat, current_group_id
            )
        elseif node is DocIndent then
            table.insert(
                commands,
                RenderCommand.new(
                    node.child, indent + state.indent_width, node_flat, current_group_id
                )
            )
        elseif node is DocGroup then
            local group_id = node.group_id or current_group_id
            if node_flat then
                table.insert(
                    commands, RenderCommand.new(node.child, indent, true, group_id)
                )
            elseif node.should_break then
                if group_id ~= nil and has_line_break_opportunity(node.child) then
                    state.broken_groups[group_id] = true
                end
                table.insert(
                    commands, RenderCommand.new(node.child, indent, false, group_id)
                )
            else
                local trial = clone_commands(commands)
                table.insert(
                    trial, RenderCommand.new(node.child, indent, true, group_id)
                )
                local fits_flat = fits(
                    state.max_width - state.column,
                    trial,
                    state.broken_groups,
                    state.indent_width
                )
                if
                    group_id ~= nil
                    and not fits_flat
                    and has_line_break_opportunity(node.child)
                then
                    state.broken_groups[group_id] = true
                end
                table.insert(
                    commands, RenderCommand.new(node.child, indent, fits_flat, group_id)
                )
            end
        end
    end
end

local function render(to_render: Doc, max_width: integer, indent_width: integer): string
    propagate_breaks(to_render)
    local state: RenderState = {
        lines = {},
        current_line = "",
        column = 0,
        max_width = max_width,
        indent_width = indent_width,
        broken_groups = {},
        line_suffixes = {},
    }

    render_doc(to_render, state)
    table.insert(state.lines, rstrip_whitespace(state.current_line))
    return table.concat(state.lines, "\n")
end

local function quote_literal(text: string): string
    return '"' .. text .. '"'
end

local function wrap_container(label: string, children: {string}): string
    return label .. "[ " .. table.concat(children, ", ") .. " ]"
end

local function group_ref(group_id: integer): string
    if group_id ~= nil then
        return "#" .. tostring(group_id)
    end
    return ""
end

local function group_label(node: DocGroup): string
    local label = node.should_break and "group!" or "group"
    return label .. group_ref(node.group_id)
end

local function if_break_label(node: DocIfBreak): string
    return "if_break" .. group_ref(node.target_group_id)
end

local function line_keyword(node: DocLine): string
    return "line(" .. quote_literal(node.flat_text or "") .. ")"
end

local function to_string_node(node: Doc, indent: string): string
    if node is DocText then
        return quote_literal(node.text or "")
    elseif node is DocRaw then
        local children: {string} = {}
        for _, raw_line in ipairs(node.raw_lines or {}) do
            table.insert(children, quote_literal(raw_line))
        end
        return wrap_container("raw", children)
    elseif node is DocClosed then
        return string.format(
            "close(text=%s, sep=%s)",
            quote_literal(node.close_text or ""),
            quote_literal(node.close_flat_sep or "")
        )
    elseif node is DocBreakText then
        return string.format(
            "break_text(flat=%s, broken=%s)",
            quote_literal(node.flat_text or ""),
            quote_literal(node.broken_text or "")
        )
    elseif node is DocLine then
        return line_keyword(node)
    elseif node is DocIndent then
        local indent_step = "  "
        local child = to_string_node(node.child, indent .. indent_step)
        return wrap_container("indent", {child})
    elseif node is DocIfBreak then
        local flat_child = to_string_node(node.flat_child, indent)
        local break_child = to_string_node(node.break_child, indent)
        local children = {"flat=" .. flat_child, "break=" .. break_child}
        return wrap_container(if_break_label(node), children)
    elseif node is DocGroup then
        local child = to_string_node(node.child, indent)
        return wrap_container(group_label(node), {child})
    elseif node is DocConcat then
        local parts: {string} = {}
        for index, part in ipairs(node.parts or {}) do
            if index > 1 then
                local prev = node.parts[index - 1]
                if is_line(prev) or part is DocClosed then
                    table.insert(parts, ",\n" .. indent)
                else
                    table.insert(parts, ", ")
                end
            end

            table.insert(parts, to_string_node(part, indent))
        end
        return "[ " .. table.concat(parts) .. " ]"
    end
    return node.kind
end

local function to_string(to_render: Doc): string
    return to_string_node(to_render, "")
end

local doc_mt <const>: metatable<Doc> = {__tostring = to_string}

local function new_doc(kind: string): Doc
    return setmetatable({kind = kind, render = render}, doc_mt)
end

function doc.text(text: string): Doc
    local result = new_doc("text") as DocText
    result.text = text
    return result
end

function doc.raw(lines: {string}): Doc
    local result = new_doc("raw") as DocRaw
    result.raw_lines = lines
    return result
end

function doc.close(text: string): Doc
    local result = new_doc("close") as DocClosed
    result.close_text = text
    result.close_flat_sep = " "
    return result
end

function doc.softclose(text: string): Doc
    local result = new_doc("close") as DocClosed
    result.close_text = text
    result.close_flat_sep = ""
    return result
end

local function new_doc_line(flat_text: string): Doc
    local result = new_doc("line") as DocLine
    result.flat_text = flat_text
    return result
end

function doc.line(): Doc
    return new_doc_line(" ")
end

-- Flat text is "; " so inlining a multi-statement body never fuses the end of
-- one statement with a leading "(" on the next into a spurious call expression.
function doc.stmt_sep_line(): Doc
    return new_doc_line("; ")
end

function doc.softline(): Doc
    return new_doc_line("")
end

function doc._break_text(broken_text: string, flat_text?: string): Doc
    local result = new_doc("break_text") as DocBreakText
    result.broken_text = broken_text
    result.flat_text = flat_text or ""
    return result
end

function doc.hardline(): Doc
    local result = new_doc("hardline") as DocHardLine
    return result
end

function doc.if_wrapped(text: string): Doc
    return doc._break_text(text, "")
end

local function build_if_break_doc(
    break_child: Doc, flat_child?: Doc, target_group_id?: integer
): Doc
    local result = new_doc("if_break") as DocIfBreak
    result.break_child = break_child
    result.flat_child = flat_child or doc.text("")
    result.target_group_id = target_group_id
    return result
end

function GroupRef:if_break(break_child: Doc, flat_child?: Doc): Doc
    return build_if_break_doc(break_child, flat_child, self.group_id)
end

function doc.break_parent(): Doc
    local result = new_doc("break_parent") as DocBreakParent
    return result
end

function doc.blankline(): Doc
    local result = new_doc("blankline") as DocBlankLine
    return result
end

function doc.concat(parts: {Doc}): Doc
    local flat_parts: {Doc} = {}
    local function add_if_non_empyt(part: Doc)
        if not (part is DocText and part.text == "") then
            table.insert(flat_parts, part)
        end
    end

    for _, part in ipairs(parts) do
        if part is DocConcat then
            for _, nested in ipairs(part.parts) do
                add_if_non_empyt(nested)
            end
        else
            add_if_non_empyt(part)
        end
    end
    local result = new_doc("concat") as DocConcat
    result.parts = flat_parts
    return result
end

function doc._trim_start(): Doc
    local result = new_doc("trim_start") as DocTrimStart
    return result
end

function doc._trim_end(): Doc
    local result = new_doc("trim_end") as DocTrimEnd
    return result
end

function doc.trim_lines(child: Doc): Doc
    return doc.concat({doc._trim_start(), child, doc._trim_end()})
end

function doc.indent(child: Doc): Doc
    local result = new_doc("indent") as DocIndent
    result.child = child
    return result
end

function doc.indent_line(child: Doc): Doc
    return doc.indent(doc.concat({doc.line(), child}))
end

function doc.indent_softline(child: Doc): Doc
    return doc.indent(doc.concat({doc.softline(), child}))
end

function doc.indent_hardline(child: Doc): Doc
    return doc.indent(doc.concat({doc.hardline(), child}))
end

local function build_group_doc(child: Doc, group_id?: integer): Doc
    local result = new_doc("group") as DocGroup
    result.child = child
    result.group_id = group_id
    result.should_break = false
    return result
end

function doc.group(child: Doc): Doc
    return build_group_doc(child, nil)
end

function GroupRef:group(child: Doc): Doc
    return build_group_doc(child, self.group_id)
end

function doc.group_ref(): GroupRef
    return GroupRef.new()
end

return doc
