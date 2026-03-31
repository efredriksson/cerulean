local record Doc
    kind: string
    text: string
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

local function flat_length(node: Doc): integer
    if node.kind == "text" then
        return #(node.text or "")
    elseif node.kind == "break_text" then
        return #(node.flat_text or "")
    elseif node.kind == "line" then
        return #(node.flat_text or "")
    elseif node.kind == "concat" then
        local total = 0
        for _, part in ipairs(node.parts or {}) do
            total = total + flat_length(part)
        end
        return total
    elseif node.kind == "indent" or node.kind == "group" then
        return flat_length(node.child)
    end
    return 0
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

local function render_node(
    node: Doc, state: RenderState, flat: boolean, indent: integer
)
    if node.kind == "text" then
        append_text(state, node.text or "")
    elseif node.kind == "break_text" then
        if flat then
            append_text(state, node.flat_text or "")
        else
            append_text(state, node.broken_text or "")
        end
    elseif node.kind == "line" then
        if flat then
            append_text(state, node.flat_text or "")
        else
            break_line(state, indent)
        end
    elseif node.kind == "concat" then
        for _, part in ipairs(node.parts or {}) do
            render_node(part, state, flat, indent)
        end
    elseif node.kind == "indent" then
        render_node(node.child, state, flat, indent + (node.amount or 0))
    elseif node.kind == "group" then
        local child = node.child
        if state.column + flat_length(child) <= state.max_width then
            render_node(child, state, true, indent)
        else
            render_node(child, state, false, indent)
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

    render_node(self, state, not force_break, base_indent)
    table.insert(state.lines, state.current_line)
    return state.lines
end

return doc
