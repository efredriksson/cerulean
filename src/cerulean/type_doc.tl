local ast = require("cerulean.ast")
local delimited_list_doc = require("cerulean.delimited_list_doc")
local doc = require("cerulean.doc")
local render_context = require("cerulean.render_context")
local trivia_doc = require("cerulean.trivia_doc")

local type RenderContext = render_context.RenderContext

local record TypeRenderOpts
    -- Generic doc forwarded into the inner function-type renderer
    generic_doc: doc.Doc
    -- True when the type is being rendered in a position where a trailing ','
    -- following the rendered type would be ambiguous with the outer context.
    wrap_multi_return_rets: boolean
end

function TypeRenderOpts.new(
    generic_doc?: doc.Doc, wrap_multi_return_rets?: boolean
): TypeRenderOpts
    local self: TypeRenderOpts = setmetatable({}, {__index = TypeRenderOpts})
    self.generic_doc = generic_doc
    self.wrap_multi_return_rets = wrap_multi_return_rets or false
    return self
end

local render_return: function(RenderContext, ast.TupleType): doc.Doc
local render_type: function(RenderContext, ast.Type, TypeRenderOpts): doc.Doc

local type_doc = {}

local type_doc_render: function(RenderContext, ast.Type, ?TypeRenderOpts): doc.Doc

local function render_argument_type(ctx: RenderContext, argtype: ast.Type): doc.Doc
    return render_type(ctx, argtype, TypeRenderOpts.new())
end

local function build_parameter_item_doc(ctx: RenderContext, arg_node: ast.Node): doc.Doc
    local parts: {doc.Doc} = {}

    if arg_node.is_va == true then
        if arg_node.tk ~= nil then
            -- A named variadic trails the `...` on the type: `name: T...`.
            table.insert(parts, doc.text(arg_node.tk .. ": "))
            table.insert(parts, render_argument_type(ctx, arg_node.argtype))
            table.insert(parts, doc.text("..."))
        elseif arg_node.argtype ~= nil then
            table.insert(parts, doc.text("...: "))
            table.insert(parts, render_argument_type(ctx, arg_node.argtype))
        else
            table.insert(parts, doc.text("..."))
        end
        return doc.concat(parts)
    end

    if arg_node.tk ~= nil then
        table.insert(parts, doc.text(arg_node.tk))
        if arg_node.opt == true then
            table.insert(parts, doc.text("?"))
        end
        if arg_node.argtype ~= nil then
            table.insert(parts, doc.text(": "))
            table.insert(parts, render_argument_type(ctx, arg_node.argtype))
        end
    else
        if arg_node.opt == true then
            table.insert(parts, doc.text("?"))
        end
        if arg_node.argtype ~= nil then
            table.insert(parts, render_argument_type(ctx, arg_node.argtype))
        end
    end

    return doc.concat(parts)
end

local function argument_nodes(args: ast.Node): {ast.Node}
    local result: {ast.Node} = {}
    for _, arg_node in ipairs(args) do
        if arg_node.kind == "argument" then
            table.insert(result, arg_node)
        end
    end
    return result
end

-- Parameter lists are paren-delimited with no trailing comma, shared by function
-- definitions (via function_doc/stmt_doc) and function types (via
-- function_type_render), so both parse to `argument` nodes and format identically.
function type_doc.render_parameter_list(ctx: RenderContext, args: ast.Node): doc.Doc
    local function render_item(arg_node: ast.Node): doc.Doc
        return build_parameter_item_doc(ctx, arg_node)
    end
    return delimited_list_doc.render_parens(
        ctx, args, argument_nodes(args), render_item
    )
end

function type_doc.render_typeargs(
    ctx: RenderContext, typeargs: {ast.TypeArgType}
): doc.Doc
    local typearg_docs: {doc.Doc} = {}
    for _, typearg in ipairs(typeargs) do
        table.insert(typearg_docs, render_type(ctx, typearg, TypeRenderOpts.new()))
    end
    return doc.concat(
        {
            doc.text("<"),
            delimited_list_doc.build_separated_docs(typearg_docs, ", "),
            doc.text(">"),
        }
    )
end

-- The `: rets` tail of a function type, parenthesized when a multi-return
-- annotation may wrap.
local function build_rets_doc(
    ctx: RenderContext, rets: ast.TupleType, opts: TypeRenderOpts
): doc.Doc
    if opts.wrap_multi_return_rets and #rets.tuple > 1 and not rets.paren then
        return doc.concat(
            {doc.text(": ("), render_type(ctx, rets, opts), doc.text(")")}
        )
    end
    return render_return(ctx, rets)
end

local function function_type_render(
    ctx: RenderContext, type_def: ast.FunctionType, opts: TypeRenderOpts
): doc.Doc
    if type_def.bare then
        return doc.text("function")
    end
    local rets_doc = build_rets_doc(ctx, type_def.rets, opts)
    local generic_doc = opts and opts.generic_doc or doc.text("")
    -- measure_flat: same argument-list-before-return-annotation priority as
    -- function_doc.render, cascading through nested function types.
    return doc.concat(
        {
            doc.text("function"),
            generic_doc,
            type_doc.render_parameter_list(ctx, type_def.args),
            doc.measure_flat(rets_doc),
        }
    )
end

local function nominal_type_render(
    ctx: RenderContext, type_def: ast.NominalType, opts: TypeRenderOpts
): doc.Doc
    local parts: {doc.Doc} = {doc.text(table.concat(type_def.names, "."))}
    if type_def.typevals ~= nil and #type_def.typevals > 0 then
        local typeval_docs: {doc.Doc} = {}
        for _, typeval in ipairs(type_def.typevals) do
            table.insert(typeval_docs, render_type(ctx, typeval, opts))
        end
        table.insert(parts, doc.text("<"))
        table.insert(parts, delimited_list_doc.build_separated_docs(typeval_docs, ", "))
        table.insert(parts, doc.text(">"))
    end
    return doc.concat(parts)
end

local function array_type_render(
    ctx: RenderContext, type_def: ast.ArrayType, opts: TypeRenderOpts
): doc.Doc
    return doc.concat(
        {
            doc.text("{"),
            render_type(ctx, type_def.elements, opts),
            doc.text("}"),
        }
    )
end

local function typearg_type_render(
    ctx: RenderContext, type_def: ast.TypeArgType, opts: TypeRenderOpts
): doc.Doc
    local typearg_text = doc.text(type_def.typearg)
    if type_def.constraint ~= nil then
        local constraint_text = render_type(ctx, type_def.constraint, opts)
        typearg_text = doc.concat({typearg_text, doc.text(" is "), constraint_text})
    end
    return typearg_text
end

local function union_type_render(
    ctx: RenderContext, type_def: ast.UnionType, opts: TypeRenderOpts
): doc.Doc
    local type_docs: {doc.Doc} = {}
    local last = #type_def.types
    for index, t in ipairs(type_def.types) do
        local branch_opts = (index == last) and opts or TypeRenderOpts.new()
        table.insert(type_docs, render_type(ctx, t, branch_opts))
    end
    return delimited_list_doc.build_separated_docs(type_docs, " | ")
end

-- Grouped with breakable separators so a return tuple wider than the
-- line wraps at its commas instead of overflowing. The indent rides on
-- each separator, not around the items: an item wrapped in indent would
-- nest the whole type one level deeper, visible on any single-entry
-- tuple (a declaration's type list is one).
local function tuple_type_render(
    ctx: RenderContext, type_def: ast.TupleType, opts: TypeRenderOpts
): doc.Doc
    local parts: {doc.Doc} = {}
    for index, t in ipairs(type_def.tuple) do
        table.insert(parts, render_type(ctx, t, opts))
        if index < #type_def.tuple then
            table.insert(parts, doc.text(","))
            table.insert(parts, doc.indent(doc.line()))
        end
    end
    local result = doc.group(doc.concat(parts))
    if type_def.is_va then
        return doc.concat({result, doc.text("...")})
    end
    return result
end

local function map_type_render(
    ctx: RenderContext, type_def: ast.MapType, opts: TypeRenderOpts
): doc.Doc
    return doc.concat(
        {
            doc.text("{"),
            render_type(ctx, type_def.keys, opts),
            doc.text(": "),
            render_type(ctx, type_def.values, opts),
            doc.text("}"),
        }
    )
end

local function tupletable_type_render(
    ctx: RenderContext, type_def: ast.TupleTableType, opts: TypeRenderOpts
): doc.Doc
    local type_docs: {doc.Doc} = {}
    for _, t in ipairs(type_def.types) do
        table.insert(type_docs, render_type(ctx, t, opts))
    end
    return doc.concat(
        {
            doc.text("{"),
            delimited_list_doc.build_separated_docs(type_docs, ", "),
            doc.text("}"),
        }
    )
end

local function generic_type_render(
    ctx: RenderContext, type_def: ast.GenericType, opts: TypeRenderOpts
): doc.Doc
    local typeargs_doc = type_doc.render_typeargs(ctx, type_def.typeargs)
    local inner_opts = TypeRenderOpts.new(typeargs_doc, opts.wrap_multi_return_rets)
    return type_doc_render(ctx, type_def.t, inner_opts)
end

type_doc_render = function(
    ctx: RenderContext, type_def: ast.Type, opts: TypeRenderOpts
): doc.Doc
    if type_def is ast.NominalType then
        return nominal_type_render(ctx, type_def, opts)
    elseif type_def is ast.ArrayType then
        return array_type_render(ctx, type_def, opts)
    elseif type_def is ast.TypeArgType then
        return typearg_type_render(ctx, type_def, opts)
    elseif type_def is ast.UnionType then
        return union_type_render(ctx, type_def, opts)
    elseif type_def is ast.TupleType then
        return tuple_type_render(ctx, type_def, opts)
    elseif type_def is ast.MapType then
        return map_type_render(ctx, type_def, opts)
    elseif type_def is ast.FunctionType then
        return function_type_render(ctx, type_def, opts)
    elseif type_def is ast.TupleTableType then
        return tupletable_type_render(ctx, type_def, opts)
    elseif type_def is ast.GenericType then
        return generic_type_render(ctx, type_def, opts)
    elseif ast.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    assert(false, "unhandled type: " .. tostring(type_def.typename))
end

render_type = function(
    ctx: RenderContext, type_def: ast.Type, opts: TypeRenderOpts
): doc.Doc
    local inner_opts = opts
    if type_def.paren and opts.wrap_multi_return_rets then
        -- Outer paren already disambiguate trailing ',' so drop flag.
        inner_opts = TypeRenderOpts.new(opts.generic_doc, false)
    end
    local result = type_doc_render(ctx, type_def, inner_opts)
    if type_def.paren then
        -- An empty paren list (`as(--[[c]])`) has no element to carry its
        -- comments; they live on the container's `after_opener` slot.
        if type_def is ast.TupleType and #type_def.tuple == 0 then
            local after_opener = ctx.slots:opener_comments(type_def, "after_opener")
            if #after_opener > 0 then
                local parts: {doc.Doc} = {}
                trivia_doc.append_inline_joined(parts, after_opener)
                result = doc.concat(parts)
            end
        end
        result = doc.concat({doc.text("("), result, doc.text(")")})
    end
    return result
end

function type_doc.render(
    ctx: RenderContext, type_def: ast.Type, generic_doc?: doc.Doc
): doc.Doc
    return render_type(ctx, type_def, TypeRenderOpts.new(generic_doc))
end

-- `x as function(): T, next_field` re-parses as `function(): (T, next_field)` —
-- the `,` is greedily consumed as a return-type separator. Callers that emit a
-- separator after an as/is cast must use `;` when this returns true.
function type_doc.cast_absorbs_trailing_comma(casttype: ast.Type): boolean
    if casttype.paren then
        return false
    end
    if casttype is ast.GenericType then
        return type_doc.cast_absorbs_trailing_comma(casttype.t)
    end
    if casttype is ast.FunctionType then
        return #casttype.rets.tuple > 0 and not casttype.rets.paren
    end
    if casttype is ast.UnionType then
        local types = casttype.types
        return #types > 0 and type_doc.cast_absorbs_trailing_comma(types[#types])
    end
    return false
end

-- An empty tuple with no explicit parens (`function()`, no `:` at all) has no
-- return annotation to print. An explicit `(): ()` keeps its parens: dropping
-- them would fuse into whatever follows -- a map key's `(): (value)` would
-- reparse with `(value)` absorbed as the key's own return type instead.
render_return = function(ctx: RenderContext, type_def: ast.TupleType): doc.Doc
    if type_def == nil or (#type_def.tuple == 0 and not type_def.paren) then
        return doc.text("")
    end
    return doc.concat({doc.text(": "), type_doc.render(ctx, type_def)})
end

function type_doc.render_return(ctx: RenderContext, type_def: ast.TupleType): doc.Doc
    return render_return(ctx, type_def)
end

return type_doc
