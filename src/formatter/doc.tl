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
end

local doc = { Doc = Doc }

local record RenderState
    lines: {string}
    current_line: string
    column: integer
    max_width: integer
end

local record RenderCommand
    node: Doc
    indent: integer
    flat: boolean
end

function RenderCommand.new(
    node: Doc, indent: integer, flat: boolean
): RenderCommand
    local self: RenderCommand = setmetatable({}, { __index = RenderCommand })
    self.node = node
    self.indent = indent
    self.flat = flat
    return self
end

local function new_doc(kind: string): Doc
    local self: Doc = setmetatable({}, { __index = Doc })
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

function doc.group(child: Doc): Doc
    local result = new_doc("group")
    result.child = child
    return result
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
    commands: {RenderCommand}, parts: {Doc}, indent: integer, flat: boolean
)
    for index = #parts, 1, -1 do
        table.insert(commands, RenderCommand.new(parts[index], indent, flat))
    end
end

local function fits(
    remaining_width: integer, commands: {RenderCommand}
): boolean
    if remaining_width < 0 then
        return false
    end

    while #commands > 0 do
        local command = table.remove(commands)
        local node = command.node
        local flat = command.flat

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
        elseif node.kind == "hardline" then
            return true
        elseif node.kind == "blankline" then
            if not flat then
                return true
            end
        elseif node.kind == "close" then
            return true
        elseif node.kind == "concat" then
            push_concat_parts(commands, node.parts or {}, command.indent, flat)
        elseif node.kind == "indent" then
            table.insert(commands, RenderCommand.new(
                node.child, command.indent + (node.amount or 0), flat
            ))
        elseif node.kind == "group" then
            if flat then
                table.insert(commands, RenderCommand.new(node.child, command.indent, true))
            else
                table.insert(commands, RenderCommand.new(node.child, command.indent, false))
            end
        end

        if remaining_width < 0 then
            return false
        end
    end

    return true
end

local function render_doc(root: Doc, state: RenderState, base_indent: integer, flat: boolean)
    local commands: {RenderCommand} = {
        RenderCommand.new(root, base_indent, flat),
    }

    while #commands > 0 do
        local command = table.remove(commands)
        local node = command.node
        local indent = command.indent
        local node_flat = command.flat

        if node.kind == "text" then
            append_text(state, node.text or "")
        elseif node.kind == "close" then
            local indent_text = string.rep(" ", indent)
            if state.current_line:match("^%s*$") ~= nil then
                state.current_line = indent_text
                state.column = indent
            elseif state.current_line ~= indent_text then
                break_line(state, indent)
            end
            append_text(state, node.close_text or "")
        elseif node.kind == "break_text" then
            if node_flat then
                append_text(state, node.flat_text or "")
            else
                append_text(state, node.broken_text or "")
            end
        elseif node.kind == "line" then
            if node_flat then
                append_text(state, node.flat_text or "")
            else
                break_line(state, indent)
            end
        elseif node.kind == "hardline" then
            break_line(state, indent)
        elseif node.kind == "blankline" then
            if not node_flat then
                table.insert(state.lines, state.current_line)
                table.insert(state.lines, "")
                state.current_line = string.rep(" ", indent)
                state.column = indent
            end
        elseif node.kind == "concat" then
            push_concat_parts(commands, node.parts or {}, indent, node_flat)
        elseif node.kind == "indent" then
            table.insert(commands, RenderCommand.new(
                node.child, indent + (node.amount or 0), node_flat
            ))
        elseif node.kind == "group" then
            if node_flat then
                table.insert(commands, RenderCommand.new(node.child, indent, true))
            else
                local trial = clone_commands(commands)
                table.insert(trial, RenderCommand.new(node.child, indent, true))
                local fits_flat = fits(state.max_width - state.column, trial)
                table.insert(commands, RenderCommand.new(node.child, indent, fits_flat))
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
    }

    render_doc(self, state, base_indent, not force_break)
    table.insert(state.lines, state.current_line)
    return state.lines
end

return doc
