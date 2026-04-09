local doc = require("formatter.doc")
local parser = require("formatter.parser")
local render_builders = require("formatter.render_builders")
local type_doc = require("formatter.type_doc")

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

local function build_prefix_doc(vars_text: string, stmt: parser.Node): doc.Doc
    if stmt.decltuple == nil or #stmt.decltuple.tuple == 0 then
        return doc.text(vars_text)
    end

    return doc.concat({doc.text(vars_text .. ": "), type_doc.render(stmt.decltuple)})
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

    local prefix_doc = build_prefix_doc("local " .. table.concat(vars, ", "), stmt)

    if stmt.exps == nil or #stmt.exps == 0 then
        return prefix_doc
    end

    if #stmt.exps == 1 then
        return doc.concat({prefix_doc, doc.text(" = "), render_expr(stmt.exps[1])})
    end

    return doc.concat(
        {
            prefix_doc,
            doc.text(" = "),
            render_builders.build_mapped_comma_separated_docs(stmt.exps, render_expr),
        }
    )
end

return inline_stmt_doc
