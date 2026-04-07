local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")

local inline_stmt_doc = {}

local type RenderExpr = function(parser.Node): doc.Doc

function inline_stmt_doc.render_return_doc(
    stmt: parser.Node, render_expr: RenderExpr
): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text("return")
    end

    return doc.concat(
        {
            doc.text("return "),
            render_builders.build_mapped_comma_separated_docs(stmt.exps, render_expr),
        }
    )
end

function inline_stmt_doc.render_assignment_doc(
    stmt: parser.Node, render_expr: RenderExpr
): doc.Doc
    return doc.concat(
        {
            render_builders.build_mapped_comma_separated_docs(stmt.vars, render_expr),
            doc.text(" = "),
            render_builders.build_mapped_comma_separated_docs(stmt.exps, render_expr),
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
            render_builders.build_mapped_comma_separated_docs(stmt.exps, render_expr),
        }
    )
end

return inline_stmt_doc
