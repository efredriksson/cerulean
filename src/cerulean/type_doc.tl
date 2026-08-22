local ast = require("cerulean.ast")
local doc = require("cerulean.doc")
local render_builders = require("cerulean.render_builders")
local trivia_doc = require("cerulean.trivia_doc")

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

local render_return: function(ast.TupleType): doc.Doc
local render_type: function(ast.Type, TypeRenderOpts): doc.Doc
-- Renders one element of a separated type list, wrapping it with its inline
-- trivia: `leading` before it and `before_separator` after it.
local render_type_element: function(ast.Type, TypeRenderOpts): doc.Doc

local function arg_name_doc(
    arg_name: string, is_optional: boolean, is_variadic: boolean
): doc.Doc, doc.Doc
    local function type_suffix(): doc.Doc
        if is_variadic and arg_name ~= nil then
            return doc.text("...")
        else
            return doc.text("")
        end
    end

    if arg_name ~= nil then
        local optional_str = is_optional and "?: " or ": "
        return doc.text(arg_name .. optional_str), type_suffix()
    elseif is_variadic then
        return doc.text("...: "), type_suffix()
    else
        local optional_str = is_optional and "?" or ""
        return doc.text(optional_str), type_suffix()
    end
end

local function is_optional_arg(type_def: ast.FunctionType, index: integer): boolean
    local is_variadic_tail = type_def.args.is_va and index == #type_def.args.tuple
    return not is_variadic_tail and type_def.args.is_optional[index]
end

local type_doc = {}

local type_doc_render: function(type_def: ast.Type, ?TypeRenderOpts): doc.Doc

function type_doc.render_typeargs(typeargs: {ast.TypeArgType}): doc.Doc
    local typearg_docs: {doc.Doc} = {}
    for _, typearg in ipairs(typeargs) do
        table.insert(typearg_docs, render_type_element(typearg, TypeRenderOpts.new()))
    end
    return doc.concat(
        {
            doc.text("<"),
            render_builders.build_separated_docs(typearg_docs, ", "),
            doc.text(">"),
        }
    )
end

local function function_type_render(
    type_def: ast.FunctionType, opts: TypeRenderOpts
): doc.Doc
    if type_def.bare then
        return doc.text("function")
    end
    local arg_docs: {doc.Doc} = {}
    local argnames = type_def.args.argnames or {}
    for index, arg_type in ipairs(type_def.args.tuple) do
        local is_variadic = type_def.args.is_va and index == #type_def.args.tuple
        local arg_name, type_suffix = arg_name_doc(
            argnames[index], is_optional_arg(type_def, index), is_variadic
        )
        local rendered_type = render_type(arg_type, TypeRenderOpts.new())
        -- A comment between the binding ':' and the type sits right before it.
        local after_colon = ast.inline_trivia(arg_type, "head")
        if #after_colon > 0 then
            rendered_type = trivia_doc.wrap_element(rendered_type, after_colon, {})
        end
        local arg_doc = doc.concat({arg_name, rendered_type, type_suffix})
        -- `leading`/`before_separator` wrap the whole argument (name + type).
        local leading = ast.inline_trivia(arg_type, "leading")
        local trailing = ast.inline_trivia(arg_type, "before_separator")
        if #leading > 0 or #trailing > 0 then
            arg_doc = trivia_doc.wrap_element(arg_doc, leading, trailing)
        end
        table.insert(arg_docs, arg_doc)
    end
    local delim_opts = render_builders.DelimitedSequenceOptions.new("(", ")")
    local rets = type_def.rets
    local wrap_rets = opts.wrap_multi_return_rets and #rets.tuple > 1 and not rets.paren
    local rets_doc: doc.Doc
    if wrap_rets then
        rets_doc = doc.concat({doc.text(": ("), render_type(rets, opts), doc.text(")")})
    else
        rets_doc = render_return(rets)
    end
    local generic_doc = opts and opts.generic_doc or doc.text("")
    return doc.concat(
        {
            doc.text("function"),
            generic_doc,
            render_builders.build_delimited_sequence_doc(arg_docs, delim_opts),
            rets_doc,
        }
    )
end

type_doc_render = function(type_def: ast.Type, opts: TypeRenderOpts): doc.Doc
    if type_def is ast.NominalType then
        local parts: {doc.Doc} = {doc.text(table.concat(type_def.names, "."))}
        if type_def.typevals ~= nil and #type_def.typevals > 0 then
            local typeval_docs: {doc.Doc} = {}
            for _, typeval in ipairs(type_def.typevals) do
                table.insert(typeval_docs, render_type_element(typeval, opts))
            end
            table.insert(parts, doc.text("<"))
            table.insert(
                parts, render_builders.build_separated_docs(typeval_docs, ", ")
            )
            table.insert(parts, doc.text(">"))
        end
        return doc.concat(parts)
    elseif type_def is ast.ArrayType then
        return doc.concat(
            {
                doc.text("{"),
                render_type_element(type_def.elements, opts),
                doc.text("}"),
            }
        )
    elseif type_def is ast.TypeArgType then
        local typearg_text = doc.text(type_def.typearg)
        if type_def.constraint ~= nil then
            local constraint_text = render_type(type_def.constraint, opts)
            typearg_text = doc.concat({typearg_text, doc.text(" is "), constraint_text})
        end
        return typearg_text
    elseif type_def is ast.UnionType then
        local type_docs: {doc.Doc} = {}
        local last = #type_def.types
        for index, t in ipairs(type_def.types) do
            local branch_opts = (index == last) and opts or TypeRenderOpts.new()
            table.insert(type_docs, render_type_element(t, branch_opts))
        end
        return render_builders.build_separated_docs(type_docs, " | ")
    elseif type_def is ast.TupleType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.tuple) do
            table.insert(type_docs, render_type_element(t, opts))
        end
        local result = render_builders.build_separated_docs(type_docs, ", ")
        if type_def.is_va then
            return doc.concat({result, doc.text("...")})
        end
        return result
    elseif type_def is ast.MapType then
        return doc.concat(
            {
                doc.text("{"),
                render_type_element(type_def.keys, opts),
                doc.text(": "),
                render_type_element(type_def.values, opts),
                doc.text("}"),
            }
        )
    elseif type_def is ast.FunctionType then
        return function_type_render(type_def, opts)
    elseif type_def is ast.TypeDeclType then
        assert(false, "implementation error, does not support enum/interface/...")
    elseif type_def is ast.TupleTableType then
        local type_docs: {doc.Doc} = {}
        for _, t in ipairs(type_def.types) do
            table.insert(type_docs, render_type_element(t, opts))
        end
        return doc.concat(
            {
                doc.text("{"),
                render_builders.build_separated_docs(type_docs, ", "),
                doc.text("}"),
            }
        )
    elseif type_def is ast.GenericType then
        local typeargs_doc = type_doc.render_typeargs(type_def.typeargs)
        local inner_opts = TypeRenderOpts.new(typeargs_doc, opts.wrap_multi_return_rets)
        return type_doc_render(type_def.t, inner_opts)
    elseif ast.simple_types[type_def.typename] then
        return doc.text(type_def.typename)
    end

    assert(false, "unhandled type: " .. tostring(type_def.typename))
end

render_type = function(type_def: ast.Type, opts: TypeRenderOpts): doc.Doc
    local inner_opts = opts
    if type_def.paren and opts.wrap_multi_return_rets then
        -- Outer paren already disambiguate trailing ',' so drop flag.
        inner_opts = TypeRenderOpts.new(opts.generic_doc, false)
    end
    local result = type_doc_render(type_def, inner_opts)
    if type_def.paren then
        -- An empty paren list (`as(--[[c]])`) has no element to carry its
        -- comments; they live on the container's `after_opener` slot.
        if type_def is ast.TupleType and #type_def.tuple == 0 then
            local after_opener = ast.inline_trivia(type_def, "after_opener")
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

render_type_element = function(type_def: ast.Type, opts: TypeRenderOpts): doc.Doc
    local element = render_type(type_def, opts)
    local leading = ast.inline_trivia(type_def, "leading")
    local trailing = ast.inline_trivia(type_def, "before_separator")
    if #leading == 0 and #trailing == 0 then
        return element
    end
    return trivia_doc.wrap_element(element, leading, trailing)
end

function type_doc.render(type_def: ast.Type, generic_doc?: doc.Doc): doc.Doc
    return render_type_element(type_def, TypeRenderOpts.new(generic_doc))
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

render_return = function(type_def: ast.TupleType): doc.Doc
    if type_def == nil or #type_def.tuple == 0 then
        return doc.text("")
    end
    return doc.concat({doc.text(": "), type_doc.render(type_def)})
end

function type_doc.render_return(type_def: ast.TupleType): doc.Doc
    return render_return(type_def)
end

return type_doc
