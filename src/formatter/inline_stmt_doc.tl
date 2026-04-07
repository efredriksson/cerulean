local doc = require("formatter.doc")
local parser = require("formatter.parser")

local inline_stmt_doc = {}

local type RenderExpr = function(parser.Node): doc.Doc

local function build_comma_separated_docs(item_docs: {doc.Doc}): doc.Doc
    local parts: {doc.Doc} = {}
    for index, item_doc in ipairs(item_docs) do
        table.insert(parts, item_doc)
        if index < #item_docs then
            table.insert(parts, doc.text(", "))
        end
    end
    return doc.concat(parts)
end

local function build_comma_separated_node_docs(
    nodes: {parser.Node}, render_node: function(parser.Node): doc.Doc
): doc.Doc
    local item_docs: {doc.Doc} = {}
    for _, node in ipairs(nodes) do
        table.insert(item_docs, render_node(node))
    end
    return build_comma_separated_docs(item_docs)
end

function inline_stmt_doc.render_return_doc(
    stmt: parser.Node, render_expr: RenderExpr
): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text("return")
    end

    return doc.concat(
        {
            doc.text("return "),
            build_comma_separated_node_docs(stmt.exps, render_expr),
        }
    )
end

function inline_stmt_doc.render_assignment_doc(
    stmt: parser.Node, render_expr: RenderExpr
): doc.Doc
    return doc.concat(
        {
            build_comma_separated_node_docs(stmt.vars, render_expr),
            doc.text(" = "),
            build_comma_separated_node_docs(stmt.exps, render_expr),
        }
    )
end

function inline_stmt_doc.render_local_declaration_doc(
    stmt: parser.Node, render_expr: RenderExpr
): doc.Doc
    local vars: {string} = {}

    for _, var_node in ipairs(stmt.vars) do
        local var_text = var_node.tk
        if var_node.attribute ~= nil then
            var_text = var_text .. " <" .. var_node.attribute .. ">"
        end
        table.insert(vars, var_text)
    end

    local prefix = "local " .. table.concat(vars, ", ")
    if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
        prefix = prefix .. stmt.decltuple.source_text
    end

    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text(prefix)
    end

    if #stmt.exps == 1 then
        return doc.concat({doc.text(prefix .. " = "), render_expr(stmt.exps[1])})
    end

    return doc.concat(
        {
            doc.text(prefix .. " = "),
            build_comma_separated_node_docs(stmt.exps, render_expr),
        }
    )
end

return inline_stmt_doc
