-- Single AST statement → doc.Doc. Returns nil for unsupported statement shapes.
local ast = require("cerulean.ast")
local construct_layout = require("cerulean.construct_layout")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local function_doc = require("cerulean.function_doc")
local inline_stmt_doc = require("cerulean.inline_stmt_doc")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")
local type_body_doc = require("cerulean.type_body_doc")
local type_doc = require("cerulean.type_doc")

local type RenderContext = render_context.RenderContext

local stmt_doc = {}

local function render_function_name(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    local function render_function_owner(owner: ast.Node): string | nil
        if owner.kind == "name" then
            return owner.tk
        elseif owner.kind == "field" and owner.e1 ~= nil and owner.e2 ~= nil then
            local left = render_function_owner(owner.e1)
            if left == nil then
                return nil
            end
            return left .. "." .. owner.e2.tk
        end

        return nil
    end

    local function render_function_typeargs(fn_node: ast.Node): doc.Doc
        if fn_node.typeargs == nil then
            return doc.text("")
        end
        return type_doc.render_typeargs(ctx, fn_node.typeargs)
    end

    if node.name == nil then
        return nil
    end

    if node.kind == "local_macro" then
        return doc.concat(
            {
                doc.text("local macro " .. node.name.tk .. "!"),
                render_function_typeargs(node),
            }
        )
    end

    if node.fn_owner ~= nil then
        local owner = render_function_owner(node.fn_owner)
        if owner == nil then
            return nil
        end
        local separator = node.is_method and ":" or "."
        return doc.concat(
            {
                doc.text("function " .. owner .. separator .. node.name.tk),
                render_function_typeargs(node),
            }
        )
    elseif node.is_local then
        return doc.concat(
            {
                doc.text("local function " .. node.name.tk),
                render_function_typeargs(node),
            }
        )
    end

    local function global_header(): string
        if node.implicit_global_function then
            return "function " .. node.name.tk
        end
        return "global function " .. node.name.tk
    end
    return doc.concat({doc.text(global_header()), render_function_typeargs(node)})
end

local function render_function_definition_doc(
    ctx: RenderContext, node: ast.Node
): doc.Doc | nil
    local name_prefix = render_function_name(ctx, node)
    if name_prefix is nil then
        return nil
    end
    return function_doc.render(ctx, node, name_prefix)
end

local function render_local_macroexp_doc(ctx: RenderContext, node: ast.Node): doc.Doc
    assert(
        node.name ~= nil and node.macrodef ~= nil and node.macrodef.exp ~= nil,
        "bad local_macroexp node"
    )
    local header = doc.group(
        doc.concat(
            {
                doc.text("local macroexp " .. node.name.tk),
                type_body_doc.macroexp_signature_doc(ctx, node.macrodef),
            }
        )
    )
    return doc.concat(
        {
            header,
            doc.indent_line(type_body_doc.macroexp_body_doc(ctx, node.macrodef)),
            doc.close("end"),
        }
    )
end

local function render_if_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.if_blocks == nil then
        return nil
    end

    local parts: {doc.Doc} = {doc.break_parent()}
    for index, if_block in ipairs(node.if_blocks) do
        if if_block.body == nil then
            return nil
        end
        local body_doc = ctx.render_block(if_block.body)
        if body_doc == nil then
            return nil
        end

        local function get_head_text(): doc.Doc
            if if_block.exp == nil then
                return doc.text("else")
            end
            local keyword = index == 1 and "if" or "elseif"
            if construct_layout.should_wrap_condition(ctx, if_block, if_block.exp) then
                return construct_layout.wrap_keyword_around(
                    doc.text(keyword),
                    ctx.render_expr(if_block.exp, true),
                    doc.text("then")
                )
            end
            local with_comment = trivia_doc.with_leading_inline_trivia(
                ctx.slots:opener_comments(if_block, "after_opener"),
                doc.text(keyword .. " "),
                ctx.render_expr(if_block.exp)
            )
            return doc.group(doc.concat({with_comment, doc.text(" then")}))
        end

        if index > 1 then
            table.insert(parts, doc.line())
        end
        table.insert(parts, get_head_text())
        table.insert(
            parts,
            trivia_doc.head_trivia_doc(ctx.slots:opener_comments(if_block, "head"))
        )
        table.insert(parts, doc.indent_line(body_doc))
    end

    table.insert(parts, doc.close("end"))
    return doc.concat(parts)
end

local function render_while_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.exp == nil or node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local should_wrap_around = construct_layout.should_wrap_condition(
        ctx, node, node.exp
    )

    local function build_head_group(): doc.Doc
        if should_wrap_around then
            return construct_layout.wrap_keyword_around(
                doc.text("while"), ctx.render_expr(node.exp, true), doc.text("do")
            )
        end
        local while_and_exp_doc = trivia_doc.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("while "),
            ctx.render_expr(node.exp)
        )
        return doc.group(doc.concat({while_and_exp_doc, doc.text(" do")}))
    end

    local header = doc.concat(
        {
            build_head_group(),
            trivia_doc.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )
    return construct_layout.block_with_close(header, body_doc, "end")
end

local function build_fornum_range_doc(node: ast.Node, ctx: RenderContext): doc.Doc
    local range_parts: {doc.Doc} = {
        ctx.render_expr(node.from),
        doc.text(", "),
        ctx.render_expr(node.to),
    }
    if node.step ~= nil then
        table.insert(range_parts, doc.text(", "))
        table.insert(range_parts, ctx.render_expr(node.step))
    end
    return doc.concat(range_parts)
end

local function render_fornum_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.var == nil or node.from == nil or node.to == nil or node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    local tail = doc.concat(
        {
            build_fornum_range_doc(node, ctx),
            doc.text(" do"),
            trivia_doc.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )
    return construct_layout.block_with_close(
        trivia_doc.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("for " .. node.var.tk .. " = "),
            tail
        ),
        body_doc,
        "end"
    )
end

local function render_forin_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.vars == nil or node.exps == nil or node.body == nil then
        return nil
    end

    local var_docs: {doc.Doc} = {}
    for _, var_node in ipairs(node.vars) do
        table.insert(var_docs, doc.text(var_node.tk))
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    -- A comment-free multi-expression list always wraps around the keywords (its
    -- commas need the hanging indent); a single expression only when it is a bare
    -- binary chain.
    local single_exp_wraps = #node.exps == 1
        and construct_layout.should_wrap_condition(ctx, node, node.exps[1])
    local multi_exp_wraps = #node.exps > 1
        and #ctx.slots:opener_comments(node, "after_opener") == 0
    local should_wrap_around = single_exp_wraps or multi_exp_wraps

    local for_in_keyword = doc.concat(
        {
            doc.text("for "),
            delimited_list_doc.build_comma_separated_docs(var_docs),
            doc.text(" in"),
        }
    )

    local function build_wrapped_exps(): doc.Doc
        if #node.exps == 1 then
            return ctx.render_expr(node.exps[1], true)
        end
        return delimited_list_doc.build_mapped_comma_separated_docs(ctx, node.exps)
    end

    local function build_header(): doc.Doc
        if should_wrap_around then
            return doc.concat(
                {
                    construct_layout.wrap_keyword_around(
                        for_in_keyword, build_wrapped_exps(), doc.text("do")
                    ),
                    trivia_doc.head_trivia_doc(
                        ctx.slots:opener_comments(node, "head")
                    ),
                }
            )
        end
        local tail_doc = doc.concat(
            {
                doc.text(" do"),
                trivia_doc.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
            }
        )
        local exps_and_tail = doc.concat(
            {
                delimited_list_doc.build_mapped_comma_separated_docs(ctx, node.exps),
                tail_doc,
            }
        )
        return trivia_doc.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.concat({for_in_keyword, doc.text(" ")}),
            exps_and_tail
        )
    end

    return construct_layout.block_with_close(build_header(), body_doc, "end")
end

local function render_repeat_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.body == nil or node.exp == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc is nil then
        return nil
    end

    local header = doc.concat(
        {
            doc.text("repeat"),
            trivia_doc.head_trivia_doc(ctx.slots:opener_comments(node, "head")),
        }
    )

    -- block_with_indent always emits a newline into the body, which produces a
    -- spurious blank line when the body is empty. Skip it in that case.
    local is_empty_body = #node.body == 0
        and #ctx.slots:dangling_comments(node.body) == 0
    local should_wrap_around = construct_layout.should_wrap_condition(
        ctx, node, node.exp
    )

    local function build_until_doc(): doc.Doc
        if should_wrap_around then
            return construct_layout.wrap_keyword_before(
                doc.text("until"), ctx.render_expr(node.exp, true)
            )
        end
        return trivia_doc.with_leading_inline_trivia(
            ctx.slots:opener_comments(node, "after_opener"),
            doc.text("until "),
            ctx.render_expr(node.exp)
        )
    end

    local until_doc = build_until_doc()
    if is_empty_body then
        return doc.concat({header, doc.line(), until_doc})
    end
    return construct_layout.block_with_indent(header, body_doc, until_doc)
end

local function render_do_doc(ctx: RenderContext, node: ast.Node): doc.Doc | nil
    if node.body == nil then
        return nil
    end

    local body_doc = ctx.render_block(node.body)
    if body_doc == nil then
        return nil
    end

    return construct_layout.block_with_close(doc.text("do"), body_doc, "end")
end

function stmt_doc.render_statement_doc(
    ctx: RenderContext, node: ast.Node
): doc.Doc | nil
    if node.kind == "return" then
        return inline_stmt_doc.render_return_doc(ctx, node)
    elseif node.kind == "assignment" then
        return inline_stmt_doc.render_assignment_doc(ctx, node)
    elseif node.kind == "local_declaration" then
        return inline_stmt_doc.render_declaration_doc(ctx, node, "local")
    elseif node.kind == "global_declaration" then
        return inline_stmt_doc.render_declaration_doc(ctx, node, "global")
    elseif node.kind == "local_type" then
        return type_body_doc.render_type_doc(ctx, node, "local")
    elseif node.kind == "global_type" then
        return type_body_doc.render_type_doc(ctx, node, "global")
    elseif node.kind == "bare_type" then
        return type_body_doc.render_type_doc(ctx, node)
    elseif node.kind == "function_declaration" or node.kind == "local_macro" then
        return render_function_definition_doc(ctx, node)
    elseif node.kind == "local_macroexp" then
        return render_local_macroexp_doc(ctx, node)
    elseif node.kind == "if" then
        return render_if_doc(ctx, node)
    elseif node.kind == "while" then
        return render_while_doc(ctx, node)
    elseif node.kind == "fornum" then
        return render_fornum_doc(ctx, node)
    elseif node.kind == "forin" then
        return render_forin_doc(ctx, node)
    elseif node.kind == "repeat" then
        return render_repeat_doc(ctx, node)
    elseif node.kind == "do" then
        return render_do_doc(ctx, node)
    elseif node.kind == "break" then
        return doc.text("break")
    elseif node.kind == "goto" then
        return doc.text("goto " .. node.label)
    elseif node.kind == "label" then
        return doc.text("::" .. node.label .. "::")
    elseif node.kind == "call" then
        return ctx.render_expr(node, true)
    elseif node.kind == "pragma" then
        return doc.text("--#pragma " .. node.pkey .. " " .. node.pvalue)
    end

    return nil
end

return stmt_doc
