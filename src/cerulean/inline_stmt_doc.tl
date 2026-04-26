local doc = require("cerulean.doc")
local parser = require("cerulean.parser")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local inline_stmt_doc = {}

function inline_stmt_doc.render_return_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        return doc.text("return")
    end

    local return_exp_doc = render_builders.build_mapped_comma_separated_docs(
        stmt.exps, ctx.render_expr
    )
    local last_exp = stmt.exps[#stmt.exps]
    local last_tc = render_builders.trailing_comment_doc(last_exp)
    local parts: {doc.Doc} = {doc.text("return ")}
    if stmt.leading_inline_comment then
        table.insert(parts, doc.text(stmt.leading_inline_comment.text))
        table.insert(parts, doc.indent_hardline(return_exp_doc))
    else
        table.insert(parts, return_exp_doc)
    end
    table.insert(parts, last_tc)
    return doc.concat(parts)
end

function inline_stmt_doc.render_assignment_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc
    local vars_doc = render_builders.build_mapped_comma_separated_docs(
        stmt.vars, ctx.render_expr
    )
    local exps_doc = render_builders.build_mapped_comma_separated_docs(
        stmt.exps, ctx.render_expr
    )
    local parts: {doc.Doc} = {vars_doc, doc.text(" = ")}
    if stmt.leading_inline_comment then
        table.insert(parts, doc.text(stmt.leading_inline_comment.text))
        table.insert(parts, doc.indent_hardline(exps_doc))
    else
        table.insert(parts, exps_doc)
    end
    return doc.concat(parts)
end

local function build_prefix_doc(vars_text: string, stmt: parser.Node): doc.Doc
    if stmt.decltuple == nil or #stmt.decltuple.tuple == 0 then
        return doc.text(vars_text)
    end

    return doc.concat({doc.text(vars_text .. ": "), type_doc.render(stmt.decltuple)})
end

function inline_stmt_doc.render_declaration_doc(
    ctx: RenderContext, stmt: parser.Node, keyword: string
): doc.Doc
    local vars: {string} = {}

    for _, var_node in ipairs(stmt.vars) do
        local var_text = var_node.tk
        if var_node.attribute ~= nil then
            var_text = var_text .. " <" .. var_node.attribute .. ">"
        end
        table.insert(vars, var_text)
    end

    local prefix_doc = build_prefix_doc(
        keyword .. " " .. table.concat(vars, ", "), stmt
    )

    if stmt.exps == nil or #stmt.exps == 0 then
        return prefix_doc
    end

    local function build_init_doc(exp_doc: doc.Doc): doc.Doc
        local parts: {doc.Doc} = {prefix_doc, doc.text(" = ")}
        if stmt.leading_inline_comment then
            table.insert(parts, doc.text(stmt.leading_inline_comment.text))
            table.insert(parts, doc.indent_hardline(exp_doc))
        else
            table.insert(parts, exp_doc)
        end
        return doc.concat(parts)
    end

    if #stmt.exps == 1 then
        return build_init_doc(ctx.render_expr(stmt.exps[1]))
    end

    return build_init_doc(
        render_builders.build_mapped_comma_separated_docs(stmt.exps, ctx.render_expr)
    )
end

return inline_stmt_doc
