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
        -- With no expression the after-`return` comment trails the whole statement,
        -- so emit it through the statement-trailing path: a line comment there must
        -- break the enclosing (possibly flat) function group or it swallows `end`.
        local after_return = ctx.slots:opener_comments(stmt, "after_opener")
        return doc.concat(
            {doc.text("return"), render_builders.trailing_comment_doc(after_return)}
        )
    end

    local return_exp_doc = render_builders.build_return_exp_list_doc(ctx, stmt.exps)
    local stmt_doc = render_builders.with_leading_inline_trivia(
        ctx.slots:opener_comments(stmt, "after_opener"),
        doc.text("return "),
        return_exp_doc
    )
    return doc.concat({stmt_doc})
end

-- The `<lhs> = ` prefix of an assignment or declaration. A single-line block
-- comment before the `=` may sit flush, so it stays inline in place (plain text,
-- no break point -- the trivia_doc.emit_transition inline-block model); a line
-- comment there runs to end of line, so the `= ` breaks out below it.
local function build_eq_prefix(
    lhs_doc: doc.Doc, inline_blocks: {ast.Comment}, last_var_trailing: {ast.Comment}
): doc.Doc
    if #inline_blocks > 0 then
        local parts: {doc.Doc} = {lhs_doc}
        trivia_doc.append_inline(parts, inline_blocks)
        table.insert(parts, doc.text(" = "))
        return doc.concat(parts)
    end
    if #last_var_trailing > 0 then
        return doc.concat(
            {
                lhs_doc,
                render_builders.trailing_comment_doc(last_var_trailing),
                doc.indent_hardline(doc.text("= ")),
            }
        )
    end
    return doc.concat({lhs_doc, doc.text(" = ")})
end

-- The last var is left out: its trailing run belongs to the `=` slot, read above.
local function earlier_var_has_trailing_comment(
    ctx: RenderContext, vars: {ast.Node}
): boolean
    for k = 1, #vars - 1 do
        if #ctx.slots:trailing_comments(vars[k]) > 0 then
            return true
        end
    end
    return false
end

-- The value list breaks in the two stages a delimited list uses: it drops below the
-- `=` first, and only then do its commas give.
local function build_init_doc(
    ctx: RenderContext, stmt: ast.Node, prefix_doc: doc.Doc, value_doc: doc.Doc
): doc.Doc
    local after_opener = ctx.slots:opener_comments(stmt, "after_opener")
    local inline_blocks = ctx.slots:pre_opener_block_comments(stmt, "after_opener")
    local last_var_trailing = ctx.slots:pre_opener_trailing_comments(
        stmt, "after_opener", stmt.vars[#stmt.vars]
    )
    -- Any comment around the `=` already pins it to a line of its own, and the
    -- two-stage wrap would then break the value list along with it. These reads
    -- consume and the branch below discards its doc, but safely: a non-empty run
    -- is what steers the render off that branch.
    local eq_carries_comments = #after_opener > 0
        or #inline_blocks > 0
        or #last_var_trailing > 0
        or earlier_var_has_trailing_comment(ctx, stmt.vars)
    if
        not eq_carries_comments and render_builders.exp_list_can_break(ctx, stmt.exps)
    then
        -- The `=` sheds its trailing space; the wrap's line puts it back when flat.
        return render_builders.wrap_keyword_before(
            doc.concat({prefix_doc, doc.text(" =")}), value_doc
        )
    end
    local eq_prefix = build_eq_prefix(prefix_doc, inline_blocks, last_var_trailing)
    return render_builders.with_leading_inline_trivia(
        after_opener, eq_prefix, value_doc
    )
end

function inline_stmt_doc.render_assignment_doc(
    ctx: RenderContext, stmt: ast.Node
): doc.Doc
    local var_docs: {doc.Doc} = {}
    for _, var in ipairs(stmt.vars) do
        table.insert(var_docs, ctx.render_expr(var))
    end
    local vars_doc = render_builders.build_comma_separated_with_trailing(
        ctx, stmt.vars, var_docs
    )
    return build_init_doc(
        ctx, stmt, vars_doc, render_builders.build_exp_list_doc(ctx, stmt.exps)
    )
end

local function build_var_text(var_node: ast.Node): string
    local var_text = var_node.tk
    if var_node.attribute ~= nil then
        var_text = var_text .. " <" .. var_node.attribute .. ">"
    end
    return var_text
end

local function build_vars_doc(
    ctx: RenderContext, stmt: ast.Node, keyword: string
): doc.Doc
    local item_docs: {doc.Doc} = {}
    for _, var_node in ipairs(stmt.vars) do
        table.insert(item_docs, doc.text(build_var_text(var_node)))
    end
    return doc.concat(
        {
            doc.text(keyword .. " "),
            render_builders.build_comma_separated_with_trailing(
                ctx, stmt.vars, item_docs
            ),
        }
    )
end

function inline_stmt_doc.render_declaration_doc(
    ctx: RenderContext, stmt: ast.Node, keyword: string
): doc.Doc
    local vars_doc = build_vars_doc(ctx, stmt, keyword)
    local prefix_doc: doc.Doc
    if stmt.decltuple == nil or #stmt.decltuple.tuple == 0 then
        prefix_doc = vars_doc
    else
        prefix_doc = doc.concat(
            {vars_doc, doc.text(": "), type_doc.render(ctx, stmt.decltuple)}
        )
    end

    if stmt.exps == nil or #stmt.exps == 0 then
        -- With no initializer nothing follows the vars on the line, so their
        -- trailing comments are the statement's own (block walker) or the sweep's;
        -- reading them here would consume without emitting and drop them.
        return prefix_doc
    end

    if #stmt.exps == 1 then
        return build_init_doc(ctx, stmt, prefix_doc, ctx.render_expr(stmt.exps[1]))
    end

    return build_init_doc(
        ctx, stmt, prefix_doc, render_builders.build_exp_list_doc(ctx, stmt.exps)
    )
end

return inline_stmt_doc
