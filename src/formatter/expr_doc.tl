-- AST expression node → compact single-line string. Now never produces wrapping or line breaks.
-- Use call_doc.build_call_expr_doc / table_doc.build_table_doc when wrapping is needed.
local doc = require("formatter.doc")
local parser = require("formatter.parser")
local signature_doc = require("formatter.signature_doc")
local table_doc = require("formatter.table_doc")

local expr_doc = {}

local record DelimitedSequenceOptions
    open_delim: string
    close_delim: string
    compact_indent_amount: integer
end

function DelimitedSequenceOptions.new(
    open_delim: string, close_delim: string, compact_indent_amount: integer
): DelimitedSequenceOptions
    local self: DelimitedSequenceOptions = setmetatable(
        {}, { __index = DelimitedSequenceOptions }
    )
    self.open_delim = open_delim
    self.close_delim = close_delim
    self.compact_indent_amount = compact_indent_amount
    return self
end

local PRECEDENCE: {string: integer} = {
    ["or"] = 1,
    ["and"] = 2,
    ["is"] = 3,
    ["<"] = 3,
    [">"] = 3,
    ["<="] = 3,
    [">="] = 3,
    ["~="] = 3,
    ["=="] = 3,
    ["|"] = 4,
    ["~"] = 5,
    ["&"] = 6,
    ["<<"] = 7,
    [">>"] = 7,
    [".."] = 8,
    ["+"] = 9,
    ["-"] = 9,
    ["*"] = 10,
    ["/"] = 10,
    ["//"] = 10,
    ["%"] = 10,
    ["not"] = 11,
    ["#"] = 11,
    ["unary-"] = 11,
    ["unary~"] = 11,
    ["^"] = 12,
    ["as"] = 50,
    ["@funcall"] = 100,
    ["@index"] = 100,
    ["."] = 100,
    [":"] = 100,
}

local RIGHT_ASSOC: {string: boolean} = {
    ["^"] = true,
    [".."] = true,
}

local render_expr: function(parser.Node, integer): doc.Doc

local function precedence_for_op(op: string, arity: integer): integer
    if arity == 1 and op == "-" then
        return PRECEDENCE["unary-"]
    elseif arity == 1 and op == "~" then
        return PRECEDENCE["unary~"]
    end
    return PRECEDENCE[op]
end

local function maybe_parenthesize(
    rendered: doc.Doc,
    child: parser.Node,
    parent_op: string,
    parent_arity: integer,
    is_right_child: boolean
): doc.Doc
    if child.kind ~= "op" or child.op == nil then
        return rendered
    end

    local child_prec = precedence_for_op(child.op.op, child.op.arity)
    local parent_prec = precedence_for_op(parent_op, parent_arity)
    if child_prec == nil or parent_prec == nil then
        return rendered
    end

    local needs = child_prec < parent_prec
    if not needs and child_prec == parent_prec and parent_arity == 2 then
        if is_right_child then
            needs = not RIGHT_ASSOC[parent_op]
        else
            needs = RIGHT_ASSOC[parent_op]
        end
    end

    if needs then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end

    return rendered
end

local function build_item_docs(item_docs: {doc.Doc}): {doc.Doc}
    local result: {doc.Doc} = {}

    for i, item_doc in ipairs(item_docs) do
        table.insert(result, item_doc)
        if i < #item_docs then
            table.insert(result, doc.text(","))
            table.insert(result, doc.line(" "))
        end
    end

    return result
end

local function build_comment_lines_doc(comments: {parser.Comment}): {doc.Doc}
    local parts: {doc.Doc} = {}
    for index, comment in ipairs(comments) do
        if index > 1 then
            table.insert(parts, doc.hardline())
        end
        if index > 1 and comment.blank_line_before then
            table.insert(parts, doc.hardline())
        end
        table.insert(parts, doc.text(comment.text))
    end
    return parts
end

local function node_end_line(node: parser.Node): integer
    return node.yend or node.y
end

local function call_arg_effective_end_line(node: parser.Node): integer
    local end_line = node_end_line(node)
    if node.kind == "op"
        and node.op ~= nil
        and node.op.op == "@funcall"
        and node.e2 ~= nil
        and node.e2.yend ~= nil
        and node.e2.yend > end_line
    then
        end_line = node.e2.yend
    end
    return end_line
end

local function classify_arg_comments(
    node: parser.Node, prev_arg_end_line: integer
): {parser.Comment}, {parser.Comment}
    local trailing: {parser.Comment} = {}
    local leading: {parser.Comment} = {}
    if node.comments ~= nil then
        for _, comment in ipairs(node.comments) do
            if comment.y <= prev_arg_end_line then
                table.insert(trailing, comment)
            else
                table.insert(leading, comment)
            end
        end
    end
    return trailing, leading
end

local function build_broken_delimited_sequence_doc_from_items(
    items_doc: doc.Doc, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.concat({
        doc.text(opts.open_delim),
        doc.indent(opts.compact_indent_amount, doc.concat({
            doc.line(""),
            items_doc,
        })),
        doc.line(""),
        doc.text(opts.close_delim),
    })
end

local function build_broken_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    if #item_docs == 0 then
        return doc.text(opts.open_delim .. opts.close_delim)
    end

    return build_broken_delimited_sequence_doc_from_items(
        doc.group(doc.concat(build_item_docs(item_docs))), opts
    )
end

local function build_delimited_sequence_doc(
    item_docs: {doc.Doc}, opts: DelimitedSequenceOptions
): doc.Doc
    return doc.group(build_broken_delimited_sequence_doc(item_docs, opts))
end

local function build_call_arg_doc(node: parser.Node): doc.Doc
    if node.kind == "literal_table" then
        return doc.group(table_doc.build_table_doc(
            node, function(child: parser.Node): doc.Doc
                return render_expr(child, 0)
            end
        ))
    end
    return render_expr(node, 0)
end

local function build_call_arg_items_doc(args: parser.Node): doc.Doc
    local parts: {doc.Doc} = {}
    local prev_arg_end_line: integer | nil = nil

    for index, arg_node in ipairs(args) do
        local trailing_comments: {parser.Comment} = {}
        local leading_comments: {parser.Comment} = arg_node.comments or {}
        if not (prev_arg_end_line is nil) then
            local non_nil_prev_arg_end_line = prev_arg_end_line
            trailing_comments, leading_comments = classify_arg_comments(
                arg_node, non_nil_prev_arg_end_line
            )
        end

        if index > 1 then
            table.insert(parts, doc.text(","))
            if #trailing_comments > 0 then
                for _, comment in ipairs(trailing_comments) do
                    table.insert(parts, doc.text(" " .. comment.text))
                end
                table.insert(parts, doc.hardline())
            elseif #leading_comments > 0 then
                table.insert(parts, doc.hardline())
            else
                table.insert(parts, doc.line(" "))
            end
        end

        if #leading_comments > 0 then
            for _, comment_part in ipairs(build_comment_lines_doc(leading_comments)) do
                table.insert(parts, comment_part)
            end
            table.insert(parts, doc.hardline())
        end

        table.insert(parts, build_call_arg_doc(arg_node))
        prev_arg_end_line = call_arg_effective_end_line(arg_node)
    end

    return doc.concat(parts)
end

local function build_call_expr_doc(node: parser.Node): doc.Doc
    local callee_doc = render_expr(node.e1, PRECEDENCE["@funcall"])
    local opts = DelimitedSequenceOptions.new("(", ")", 4)
    local has_trailing_comment = node.e2.trailing_comment ~= nil
    local call_args_doc: doc.Doc

    if #node.e2 == 0 then
        call_args_doc = build_delimited_sequence_doc({}, opts)
    else
        call_args_doc = build_broken_delimited_sequence_doc_from_items(
            doc.group(build_call_arg_items_doc(node.e2)), opts
        )
    end
    local call_node = doc.concat({
        callee_doc,
        call_args_doc,
    })
    if has_trailing_comment then
        return doc.concat({
            call_node,
            doc.text(" " .. node.e2.trailing_comment.text),
        })
    end
    return doc.group(call_node)
end

local function render_call_aware_expr(
    node: parser.Node, parent_prec: integer
): doc.Doc
    if node.kind == "op"
        and node.op ~= nil
        and node.op.op == "@funcall"
    then
        return build_call_expr_doc(node)
    end

    return render_expr(node, parent_prec)
end

local function wrap_for_parent_precedence(
    rendered: doc.Doc, op: string, arity: integer, parent_prec: integer
): doc.Doc
    if precedence_for_op(op, arity) < parent_prec then
        return doc.concat({doc.text("("), rendered, doc.text(")")})
    end
    return rendered
end

local function append_return_type(
    signature: doc.Doc, rets_source_text: string
): doc.Doc
    if rets_source_text ~= "" then
        return doc.concat({signature, doc.text(rets_source_text)})
    end
    return signature
end

local function render_statement(stmt: parser.Node): doc.Doc
    if stmt.kind == "return" then
        local parts: {doc.Doc} = {}
        if stmt.exps ~= nil then
            for i, exp_node in ipairs(stmt.exps) do
                table.insert(parts, render_expr(exp_node, 0))
                if i < #stmt.exps then
                    table.insert(parts, doc.text(","))
                end
            end
        end
        if #parts == 0 then
            return doc.text("return")
        end
        return doc.concat({doc.text("return "), doc.concat(parts)})
    elseif stmt.kind == "assignment" then
        local vars: {doc.Doc} = {}
        local exps: {doc.Doc} = {}
        for i, var_node in ipairs(stmt.vars) do
            table.insert(vars, render_expr(var_node, 0))
            if i < #stmt.vars then
                table.insert(vars, doc.text(", "))
            end
        end
        for i, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
            if i < #stmt.exps then
                table.insert(exps, doc.text(", "))
            end
        end
        return doc.concat({doc.concat(vars), doc.text(" = "), doc.concat(exps)})
    elseif stmt.kind == "local_declaration" then
        local vars: {doc.Doc} = {}
        local exps: {doc.Doc} = {}
        for i, var_node in ipairs(stmt.vars) do
            table.insert(vars, doc.text(var_node.tk))
            if i < #stmt.vars then
                table.insert(vars, doc.text(", "))
            end
        end
        for i, exp_node in ipairs(stmt.exps) do
            table.insert(exps, render_expr(exp_node, 0))
            if i < #stmt.exps then
                table.insert(exps, doc.text(", "))
            end
        end
        local result = doc.concat({doc.text("local "), doc.concat(vars)})
        if stmt.decltuple ~= nil and stmt.decltuple.source_text ~= nil then
            result = doc.concat({result, doc.text(stmt.decltuple.source_text)})
        end
        if #exps > 0 then
            result = doc.concat({result, doc.text(" = "), doc.concat(exps)})
        end
        return result
    end

    error("unsupported anonymous function statement: " .. stmt.kind)
end

local function render_function_expr(node: parser.Node): doc.Doc
    local rets_source_text = ""
    if node.rets ~= nil and node.rets.source_text ~= nil then
        rets_source_text = node.rets.source_text
    end

    local signature = append_return_type(
        signature_doc.render_signature_doc(node.args, false), rets_source_text
    )

    if node.body == nil or #node.body == 0 then
        return doc.group(doc.concat({
            doc.text("function"),
            signature,
            doc.line(" "),
            doc.text("end"),
        }))
    elseif #node.body == 1 then
        return doc.group(doc.concat({
            doc.text("function"),
            signature,
            doc.indent(4, doc.concat({
                doc.line(" "),
                render_statement(node.body[1]),
            })),
            doc.line(" "),
            doc.text("end"),
        }))
    end

    error("unsupported anonymous function body shape")
end

local function render_op(node: parser.Node, parent_prec: integer): doc.Doc
    local op = node.op.op
    if op == "." or op == ":" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]), doc.text(op), doc.text(node.e2.tk)
        })
    elseif op == "@index" then
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]),
            doc.text("["),
            render_expr(node.e2, 0),
            doc.text("]"),
        })
    elseif op == "@funcall" then
        return build_call_expr_doc(node)
    elseif op == "as" or op == "is" then
        assert(node.e2.casttype.source_text, "missing source_text for cast type")
        return doc.concat({
            render_expr(node.e1, PRECEDENCE[op]),
            doc.text(" " .. op .. " "),
            doc.text(node.e2.casttype.source_text),
        })
    elseif node.op.arity == 1 then
        local op_prec = precedence_for_op(op, 1)
        local child = maybe_parenthesize(
            render_call_aware_expr(node.e1, op_prec), node.e1, op, 1, true
        )
        local rendered = doc.concat({doc.text(op == "not" and "not " or op), child})
        return wrap_for_parent_precedence(rendered, op, 1, parent_prec)
    else
        local op_prec = precedence_for_op(op, 2)
        local left_doc = render_call_aware_expr(node.e1, op_prec)
        local right_doc = render_call_aware_expr(node.e2, op_prec)

        local left = maybe_parenthesize(left_doc, node.e1, op, 2, false)
        local right = maybe_parenthesize(right_doc, node.e2, op, 2, true)
        local separator = doc.text(" " .. op .. " ")
        local rendered = doc.concat({left, separator, right})
        if parent_prec == 0 then
            rendered = doc.group(rendered)
        end
        return wrap_for_parent_precedence(rendered, op, 2, parent_prec)
    end
end

render_expr = function(node: parser.Node, parent_prec: integer): doc.Doc
    if node.kind == "variable" or node.kind == "identifier" or node.kind == "..." then
        return doc.text(node.tk)
    elseif node.kind == "string" or node.kind == "number" or node.kind == "integer" then
        return doc.text(node.tk)
    elseif node.kind == "boolean" or node.kind == "nil" then
        return doc.text(node.tk)
    elseif node.kind == "paren" then
        return doc.concat({doc.text("("), render_expr(node.e1, 0), doc.text(")")})
    elseif node.kind == "literal_table" then
        return table_doc.build_table_doc(
            node, function(child: parser.Node): doc.Doc
                return render_expr(child, 0)
            end
        )
    elseif node.kind == "function" then
        return render_function_expr(node)
    elseif node.kind == "op" and node.op ~= nil then
        return render_op(node, parent_prec)
    end

    error("unsupported expression kind: " .. node.kind)
end

function expr_doc.render_expr(node: parser.Node): doc.Doc
    return render_expr(node, 0)
end

return expr_doc
