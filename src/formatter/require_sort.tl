-- Alphabetically re-orders consecutive top-level local require declarations.
-- Only sorts contiguous groups; stops at the first non-require statement.
local ast_traversal = require("formatter.ast_traversal")
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_context = require("formatter.render_context")
local source = require("formatter.source")

local type RenderContext = render_context.RenderContext

local require_sort = {}

local record RequireDecl
    first_line: integer
    last_line: integer
    module_path: string
    node: parser.Node
end

function RequireDecl.new(
    first_line: integer, last_line: integer, module_path: string, node: parser.Node
): RequireDecl
    local self: RequireDecl = setmetatable({}, {__index = RequireDecl})
    self.first_line = first_line
    self.last_line = last_line
    self.module_path = module_path
    self.node = node
    return self
end

local record RequireBlock
    first_line: integer
    last_line: integer
    decls: {RequireDecl}
end

function RequireBlock.new(
    first_line: integer, last_line: integer, decls: {RequireDecl}
): RequireBlock
    local self: RequireBlock = setmetatable({}, {__index = RequireBlock})
    self.first_line = first_line
    self.last_line = last_line
    self.decls = decls
    return self
end

local function render_require_decl(
    ctx: RenderContext, decl: RequireDecl, indent: string
): doc.Doc
    local node = decl.node
    if node.kind == "local_declaration"
        and node.vars ~= nil
        and #node.vars == 1
        and node.exps ~= nil
        and #node.exps == 1 then
        local text = "local " .. node.vars[1].tk
        if node.vars[1].attribute ~= nil then
            text = text .. " <" .. node.vars[1].attribute .. ">"
        end
        if node.decltuple ~= nil and node.decltuple.source_text ~= nil then
            text = text .. node.decltuple.source_text
        end
        return doc.concat(
            {doc.text(indent .. text .. " = "), ctx.render_expr(node.exps[1])}
        )
    elseif node.kind == "local_type" and node.var ~= nil and node.value ~= nil then
        local lhs = doc.text(indent .. "local type " .. node.var.tk .. " = ")
        return doc.concat({lhs, ctx.render_expr(node.value)})
    end

    error("unsupported require declaration kind: " .. node.kind)
end

local function collect_require_decls(ast: parser.Node): {RequireDecl}
    local result: {RequireDecl} = {}
    for _, node in ipairs(ast) do
        local call_node: parser.Node
        if node.kind == "local_declaration"
            and node.vars ~= nil
            and #node.vars == 1
            and node.exps ~= nil
            and #node.exps == 1
            and node.exps[1] ~= nil then
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
            and call_node.e2[1].kind == "string" then
            local module_path = call_node.e2[1].conststr or ""
            local last_line = call_node.e2.yend or call_node.e2.y or node.y
            table.insert(result, RequireDecl.new(node.y, last_line, module_path, node))
        end
    end
    return result
end

local function has_comment(
    lines: {string}, first_line: integer, last_line: integer
): boolean
    for line = first_line, last_line do
        if lines[line] and lines[line]:find("%-%-") then
            return true
        end
    end
    return false
end

local function collect_require_blocks(
    ast: parser.Node, lines: {string}, fmt_off_regions: source.Regions
): {RequireBlock}
    local decls = collect_require_decls(ast)
    local result: {RequireBlock} = {}
    local current_block: {RequireDecl} = {}

    local function push_block()
        if #current_block == 0 then
            return
        end
        table.insert(
            result,
            RequireBlock.new(
                current_block[1].first_line,
                current_block[#current_block].last_line,
                current_block
            )
        )

        current_block = {}
    end

    local previous_decl: RequireDecl | nil = nil
    for _, decl in ipairs(decls) do
        local has_fmt_off = fmt_off_regions:includes_range(
            decl.first_line, decl.last_line
        )
        local decl_has_comment = has_comment(lines, decl.first_line, decl.last_line)

        if has_fmt_off or decl_has_comment then
            push_block()
            previous_decl = nil
        elseif not (previous_decl is nil) then
            if decl.first_line == previous_decl.last_line + 1 then
                table.insert(current_block, decl)
                previous_decl = decl
            else
                push_block()
                table.insert(current_block, decl)
                previous_decl = decl
            end
        else
            push_block()
            table.insert(current_block, decl)
            previous_decl = decl
        end
    end

    push_block()
    return result
end

local function sort_require_blocks(
    ctx: RenderContext, lines: {string}, require_blocks: {RequireBlock}
): {string}
    local result: {string} = {}
    local next_line = 1

    local function by_module_path(first: RequireDecl, second: RequireDecl): boolean
        return first.module_path < second.module_path
    end

    for _, block in ipairs(require_blocks) do
        for line = next_line, block.first_line - 1 do
            table.insert(result, lines[line])
        end

        local sorted_decls: {RequireDecl} = {}
        for _, decl in ipairs(block.decls) do
            table.insert(sorted_decls, decl)
        end
        table.sort(sorted_decls, by_module_path)

        for _, decl in ipairs(sorted_decls) do
            local indent = (lines[decl.first_line] or ""):match("^(%s*)") or ""
            table.insert(result, render_require_decl(ctx, decl, indent):render(88, 4))
        end

        next_line = block.last_line + 1
    end

    for line = next_line, #lines do
        table.insert(result, lines[line])
    end

    return result
end

function require_sort.rewrite(
    ctx: RenderContext, source_: string, filename: string
): string, {parser.Error}
    local ast, parse_errors = parser.parse(source_, filename)
    if #parse_errors > 0 then
        return source_, parse_errors
    end

    local source_text = source.Text.new(source_)
    local lines = source_text.lines
    local source_blocks = ast_traversal.collect_block_ranges(ast)
    local fmt_off_regions = source.collect_fmt_off_regions(source_text, source_blocks)
    local require_blocks = collect_require_blocks(ast, lines, fmt_off_regions)
    local output_lines = sort_require_blocks(ctx, lines, require_blocks)

    return table.concat(output_lines, "\n"), {}
end

return require_sort
