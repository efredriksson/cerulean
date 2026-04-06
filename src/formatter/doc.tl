-- Wadler-Lindig document algebra. Build a Doc tree with text/line/concat/indent/group,
-- then call Doc:render to produce {string}.
local record Doc
    kind: string
    text: string
    close_text: string
    flat_text: string
    broken_text: string
    parts: {Doc}
    amount: integer
    child: Doc
    flat_child: Doc
    break_child: Doc
    group_id: integer
    target_group_id: integer
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
    broken_groups: {integer:boolean}
    line_suffixes: {RenderCommand}
end

local function new_doc(kind: string): Doc
    local self: Doc = setmetatable({}, {__index = Doc})
    self.kind = kind
    return self
end

function doc.text(text: string): Doc
    local result = new_doc("text")
    result.text = text
    return result
end

function doc.close(text: string): Doc
    local result = new_doc("close")
    result.close_text = text
    return result
end

function doc.line(flat_text: string): Doc
    local result = new_doc("line")
    result.flat_text = flat_text
    return result
end

function doc.softline(): Doc
    return doc.line("")
end

function doc.break_text(broken_text: string, flat_text?: string): Doc
    local result = new_doc("break_text")
    result.broken_text = broken_text
    result.flat_text = flat_text or ""
    return result
end

function doc.hardline(): Doc
    local result = new_doc("hardline")
    return result
end

function doc.if_wrapped(text: string): Doc
    return doc.break_text(text, "")
end

local function build_if_break_doc(
    break_child: Doc, flat_child?: Doc, target_group_id?: integer
): Doc
    local result = new_doc("if_break")
    result.break_child = break_child
    result.flat_child = flat_child or doc.text("")
    result.target_group_id = target_group_id
    return result
end

function GroupRef:if_break(break_child: Doc, flat_child?: Doc): Doc
    return build_if_break_doc(break_child, flat_child, self.group_id)
end

function doc.break_parent(): Doc
    return new_doc("break_parent")
end

function doc.line_suffix(child: Doc): Doc
    local result = new_doc("line_suffix")
    result.child = child
    return result
end

function doc.line_suffix_boundary(): Doc
    return new_doc("line_suffix_boundary")
end

function doc.blankline(): Doc
    local result = new_doc("blankline")
    return result
end

function doc.concat(parts: {Doc}): Doc
    local result = new_doc("concat")
    result.parts = parts
    return result
end

function doc.indent(amount: integer, child: Doc): Doc
    local result = new_doc("indent")
    result.amount = amount
    result.child = child
    return result
end

local function build_group_doc(child: Doc, group_id?: integer): Doc
    local result = new_doc("group")
    result.child = child
    result.group_id = group_id
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

local function append_text(state: RenderState, text: string)
    state.current_line = state.current_line .. text
    state.column = state.column + #text
end

local function break_line(state: RenderState, indent: integer)
    table.insert(state.lines, state.current_line)
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
    broken_groups: {integer:boolean}
): boolean
    if target_group_id ~= nil then
        return broken_groups[target_group_id] == true
    end

    if current_group_id ~= nil and broken_groups[current_group_id] == true then
        return true
    end

    return not flat
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

local function fits(
    remaining_width: integer,
    commands: {RenderCommand},
    broken_groups: {integer:boolean}
): boolean
    if remaining_width < 0 then
        return false
    end

    while #commands > 0 do
        local command = table.remove(commands)
        local node = command.node
        local flat = command.flat
        local current_group_id = command.current_group_id

        if node.kind == "text" then
            remaining_width = remaining_width - #(node.text or "")
        elseif node.kind == "break_text" then
            if flat then
                remaining_width = remaining_width - #(node.flat_text or "")
            else
                remaining_width = remaining_width - #(node.broken_text or "")
            end
        elseif node.kind == "line" then
            if flat then
                remaining_width = remaining_width - #(node.flat_text or "")
            else
                return true
            end
        elseif node.kind == "if_break" then
            local take_break_branch = should_take_break_branch(
                node.target_group_id, current_group_id, flat, broken_groups
            )
            local chosen = take_break_branch and node.break_child or node.flat_child
            table.insert(
                commands,
                RenderCommand.new(chosen, command.indent, flat, current_group_id)
            )
        elseif node.kind == "break_parent" then
            return false
        elseif node.kind == "line_suffix" or node.kind == "line_suffix_boundary" then

            -- Line suffixes are rendered at boundaries and do not consume inline width.
        elseif node.kind == "hardline" then
            return true
        elseif node.kind == "blankline" then
            if not flat then
                return true
            end
        elseif node.kind == "close" then
            return true
        elseif node.kind == "concat" then
            push_concat_parts(
                commands, node.parts or {}, command.indent, flat, current_group_id
            )
        elseif node.kind == "indent" then
            table.insert(
                commands,
                RenderCommand.new(
                    node.child,
                    command.indent + (node.amount or 0),
                    flat,
                    current_group_id
                )
            )
        elseif node.kind == "group" then
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

local function render_doc(
    root: Doc, state: RenderState, base_indent: integer, flat: boolean
)
    local commands: {RenderCommand} = {
        RenderCommand.new(root, base_indent, flat, nil),
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

        if node.kind == "text" then
            append_text(state, node.text or "")
        elseif node.kind == "close" then
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
            append_text(state, node.close_text or "")
        elseif node.kind == "break_text" then
            if node_flat then
                append_text(state, node.flat_text or "")
            else
                append_text(state, node.broken_text or "")
            end
        elseif node.kind == "if_break" then
            local take_break_branch = should_take_break_branch(
                node.target_group_id, current_group_id, node_flat, state.broken_groups
            )
            local chosen = take_break_branch and node.break_child or node.flat_child
            table.insert(
                commands, RenderCommand.new(chosen, indent, node_flat, current_group_id)
            )
        elseif node.kind == "break_parent" then
            if current_group_id ~= nil then
                state.broken_groups[current_group_id] = true
            end
        elseif node.kind == "line_suffix" then
            table.insert(
                state.line_suffixes,
                RenderCommand.new(node.child, indent, node_flat, current_group_id)
            )
        elseif node.kind == "line_suffix_boundary" then
            push_pending_line_suffixes(commands, state)
        elseif node.kind == "line" then
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
        elseif node.kind == "hardline" then
            local suffix_count = push_pending_line_suffixes(commands, state)
            if suffix_count > 0 then
                table.insert(commands, #commands - suffix_count + 1, command)
            else
                break_line(state, indent)
            end
        elseif node.kind == "blankline" then
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
        elseif node.kind == "concat" then
            push_concat_parts(
                commands, node.parts or {}, indent, node_flat, current_group_id
            )
        elseif node.kind == "indent" then
            table.insert(
                commands,
                RenderCommand.new(
                    node.child, indent + (node.amount or 0), node_flat, current_group_id
                )
            )
        elseif node.kind == "group" then
            local group_id = node.group_id or current_group_id
            if node_flat then
                table.insert(
                    commands, RenderCommand.new(node.child, indent, true, group_id)
                )
            else
                local trial = clone_commands(commands)
                table.insert(
                    trial, RenderCommand.new(node.child, indent, true, group_id)
                )
                local fits_flat = fits(
                    state.max_width - state.column, trial, state.broken_groups
                )
                if group_id ~= nil and not fits_flat then
                    state.broken_groups[group_id] = true
                end
                table.insert(
                    commands, RenderCommand.new(node.child, indent, fits_flat, group_id)
                )
            end
        end
    end
end

function Doc:render(
    max_width: integer,
    initial_column: integer,
    base_indent: integer,
    force_break: boolean
): {string}
    local state: RenderState = {
        lines = {},
        current_line = "",
        column = initial_column,
        max_width = max_width,
        broken_groups = {},
        line_suffixes = {},
    }

    render_doc(self, state, base_indent, not force_break)
    table.insert(state.lines, state.current_line)
    return state.lines
end

return doc
