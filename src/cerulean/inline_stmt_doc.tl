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

    local return_exp_doc = render_builders.build_exp_list_doc(ctx, stmt.exps)
    local last_exp = stmt.exps[#stmt.exps]
    local last_tc = render_builders.trailing_comment_doc(last_exp)
    local stmt_doc = render_builders.with_leading_inline_comment(
        stmt, doc.text("return "), return_exp_doc
    )
    return doc.concat({stmt_doc, last_tc})
end

function inline_stmt_doc.render_assignment_doc(
    ctx: RenderContext, stmt: parser.Node
): doc.Doc
    local function build_var_doc(var: parser.Node): doc.Doc
        local var_doc = ctx.render_expr(var)
        local trivia = var.trailing_trivia
        if trivia == nil or #trivia == 0 then
            return var_doc
        end
        local parts: {doc.Doc} = {var_doc}
        for _, c in ipairs(trivia) do
            table.insert(parts, doc.text(" " .. c.text))
        end
        return doc.concat(parts)
    end
    local var_docs: {doc.Doc} = {}
    for _, var in ipairs(stmt.vars) do
        table.insert(var_docs, build_var_doc(var))
    end
    local vars_doc = render_builders.build_comma_separated_docs(var_docs)
    local exps_doc = render_builders.build_exp_list_doc(ctx, stmt.exps)
    return render_builders.with_leading_inline_comment(
        stmt, doc.concat({vars_doc, doc.text(" = ")}), exps_doc
    )
end

local function build_var_text(var_node: parser.Node): string
    local var_text = var_node.tk
    if var_node.attribute ~= nil then
        var_text = var_text .. " <" .. var_node.attribute .. ">"
    end
    return var_text
end

local function append_trailing_trivia(parts: {doc.Doc}, var_node: parser.Node)
    for _, c in ipairs(var_node.trailing_trivia or {}) do
        table.insert(parts, doc.text(" " .. c.text))
    end
end

local function build_vars_doc(stmt: parser.Node, keyword: string): doc.Doc
    local parts: {doc.Doc} = {doc.text(keyword .. " ")}
    for index, var_node in ipairs(stmt.vars) do
        table.insert(parts, doc.text(build_var_text(var_node)))
        append_trailing_trivia(parts, var_node)
        if index < #stmt.vars then
            table.insert(parts, doc.text(", "))
        end
    end
    return doc.concat(parts)
end

function inline_stmt_doc.render_declaration_doc(
    ctx: RenderContext, stmt: parser.Node, keyword: string
): doc.Doc
    local vars_doc = build_vars_doc(stmt, keyword)
    local prefix_doc: doc.Doc
    if stmt.decltuple == nil or #stmt.decltuple.tuple == 0 then
        prefix_doc = vars_doc
    else
        prefix_doc = doc.concat(
            {vars_doc, doc.text(": "), type_doc.render(stmt.decltuple)}
        )
    end

    if stmt.exps == nil or #stmt.exps == 0 then
        return prefix_doc
    end

    local function build_init_doc(exp_doc: doc.Doc): doc.Doc
        return render_builders.with_leading_inline_comment(
            stmt, doc.concat({prefix_doc, doc.text(" = ")}), exp_doc
        )
    end

    if #stmt.exps == 1 then
        return build_init_doc(ctx.render_expr(stmt.exps[1]))
    end

    return build_init_doc(
        render_builders.build_mapped_comma_separated_docs(ctx, stmt.exps)
    )
end

return inline_stmt_doc
