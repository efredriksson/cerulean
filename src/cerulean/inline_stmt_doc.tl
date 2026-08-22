local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local inline_stmt_doc = {}

function inline_stmt_doc.render_return_doc(ctx: RenderContext, stmt: ast.Node): doc.Doc
    if stmt.exps == nil or #stmt.exps == 0 then
        local parts: {doc.Doc} = {doc.text("return")}
        trivia_doc.append_inline(parts, ast.inline_trivia(stmt, "after_opener"))
        return doc.concat(parts)
    end

    local return_exp_doc = render_builders.build_return_exp_list_doc(ctx, stmt.exps)
    local last_exp = stmt.exps[#stmt.exps]
    local last_tc = render_builders.trailing_comment_doc(last_exp)
    local stmt_doc = render_builders.with_leading_inline_trivia(
        stmt, doc.text("return "), return_exp_doc
    )
    return doc.concat({stmt_doc, last_tc})
end

-- The value list breaks in the two stages a delimited list uses: it drops below the
-- `=` first, and only then do its commas give.
local function build_init_doc(
    stmt: ast.Node, prefix_doc: doc.Doc, value_doc: doc.Doc
): doc.Doc
    local last_var = stmt.vars[#stmt.vars]
    if #(last_var.trailing_comments or {}) > 0 then
        local eq_prefix = doc.concat(
            {
                prefix_doc,
                render_builders.trailing_comment_doc(last_var),
                doc.indent_hardline(doc.text("= ")),
            }
        )
        return render_builders.with_leading_inline_trivia(stmt, eq_prefix, value_doc)
    end
    if
        #ast.inline_trivia(stmt, "after_opener") == 0
        and render_builders.exp_list_can_break(stmt.exps)
    then
        -- The `=` sheds its trailing space; the wrap's line puts it back when flat.
        return render_builders.wrap_keyword_before(
            doc.concat({prefix_doc, doc.text(" =")}), value_doc
        )
    end
    return render_builders.with_leading_inline_trivia(
        stmt, doc.concat({prefix_doc, doc.text(" = ")}), value_doc
    )
end

function inline_stmt_doc.render_assignment_doc(
    ctx: RenderContext, stmt: ast.Node
): doc.Doc
    local function build_var_doc(var: ast.Node): doc.Doc
        local parts: {doc.Doc} = {}
        trivia_doc.append_leading(parts, ast.inline_trivia(var, "leading"))
        table.insert(parts, ctx.render_expr(var))
        trivia_doc.append_inline(parts, ast.inline_trivia(var, "before_separator"))
        return doc.concat(parts)
    end
    local var_docs: {doc.Doc} = {}
    for _, var in ipairs(stmt.vars) do
        table.insert(var_docs, build_var_doc(var))
    end
    local vars_doc = render_builders.build_comma_separated_docs(var_docs)
    return build_init_doc(
        stmt, vars_doc, render_builders.build_exp_list_doc(ctx, stmt.exps)
    )
end

local function build_var_text(var_node: ast.Node): string
    local var_text = var_node.tk
    if var_node.attribute ~= nil then
        var_text = var_text .. " <" .. var_node.attribute .. ">"
    end
    return var_text
end

local function build_vars_doc(stmt: ast.Node, keyword: string): doc.Doc
    local parts: {doc.Doc} = {doc.text(keyword .. " ")}
    for index, var_node in ipairs(stmt.vars) do
        trivia_doc.append_leading(parts, ast.inline_trivia(var_node, "leading"))
        table.insert(parts, doc.text(build_var_text(var_node)))
        trivia_doc.append_inline(parts, ast.inline_trivia(var_node, "before_separator"))
        if index < #stmt.vars then
            table.insert(parts, doc.text(", "))
        end
    end
    return doc.concat(parts)
end

function inline_stmt_doc.render_declaration_doc(
    ctx: RenderContext, stmt: ast.Node, keyword: string
): doc.Doc
    local vars_doc = build_vars_doc(stmt, keyword)
    local last_var = stmt.vars[#stmt.vars]
    local prefix_doc: doc.Doc
    if stmt.decltuple == nil or #stmt.decltuple.tuple == 0 then
        prefix_doc = vars_doc
    else
        prefix_doc = doc.concat(
            {vars_doc, doc.text(": "), type_doc.render(stmt.decltuple)}
        )
    end

    if stmt.exps == nil or #stmt.exps == 0 then
        if #(last_var.trailing_comments or {}) > 0 then
            return doc.concat(
                {prefix_doc, render_builders.trailing_comment_doc(last_var)}
            )
        end
        return prefix_doc
    end

    if #stmt.exps == 1 then
        return build_init_doc(stmt, prefix_doc, ctx.render_expr(stmt.exps[1]))
    end

    return build_init_doc(
        stmt, prefix_doc, render_builders.build_exp_list_doc(ctx, stmt.exps)
    )
end

return inline_stmt_doc
