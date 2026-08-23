-- Adapted from tl.tl (the teal-language/tl project), version 0.24.8.
-- Original work Copyright 2019 Hisham Muhammad, MIT License (see LICENSES/MIT-teal.txt).
-- Modifications Copyright (c) 2026 Emil Fredriksson, MIT License (see LICENSE).
-- This copy should be simplified and specialized over time.
local ast = require("cerulean.ast")
local tl = require("tl")

local type Error = tl.Error
local type Token = tl.Token

local record parser
    type Error = tl.Error

    parse: function(input: string, filename: string): ast.Node, {Error}, {Token}
    check_separator_ownership: function(root: ast.Node, tokens: {Token}): {string}
end

-- ── Local aliases for the ast data contract ─────────────────────────────────

local type Node = ast.Node

local type NodeKind = ast.NodeKind
local type TypeName = ast.TypeName
local type Type = ast.Type
local type GenericType = ast.GenericType
local type TupleType = ast.TupleType
local type TypeArgType = ast.TypeArgType
local type NominalType = ast.NominalType
local type FunctionType = ast.FunctionType
local type ArrayType = ast.ArrayType
local type RecordLikeType = ast.RecordLikeType
local type RecordType = ast.RecordType
local type InterfaceType = ast.InterfaceType
local type HasDeclName = ast.HasDeclName
local type NilType = ast.NilType
local type UnionType = ast.UnionType
local type TupleTableType = ast.TupleTableType
local type MapType = ast.MapType
local type EnumType = ast.EnumType
local type TokenKind = tl.TokenKind
local type InlineSlot = ast.InlineSlot
local type HasTokenSpan = ast.HasTokenSpan
local type Operator = ast.Operator
local type HasOpenerSlots = ast.HasOpenerSlots
local type FieldEntry = ast.FieldEntry

-- Record the opener token whose same-line trivia feeds a positional slot, so
-- the renderer can find it without re-deriving the grammar.
local function set_slot_tok(node: HasOpenerSlots, slot: InlineSlot, opener: integer)
    node.slot_tok = node.slot_tok or {}
    node.slot_tok[slot] = opener
end

-- ── pre-parser functions ─────────────────────────────────────────────────────
local type_mt: metatable<Type> = {
    __tostring = function(_t: Type): string return "?" end,
}

local simple_types = ast.simple_types

-- ── Parser block ─────────────────────────────────────────────────────────────

local record ParseState
    tokens: {Token}
    errs: {Error}
    filename: string
    -- Macros are file-local: only `local macro`, only invoked through a bare name,
    -- only after the declaration has been read. So one flat table filled during the
    -- single forward pass answers every lookup, with no scope stack.
    macro_params: {string: Node}
    -- A bare `record Foo ... end` is a statement only as a macro argument.
    -- Everywhere else it still has to ask for `local` or `global`.
    allow_bare_type: boolean
end

-- A statement `;` renders nothing, so it is deleted from the token array at
-- the moment it is consumed (the StyLua model: the formatter drops the token,
-- so it never reaches the renderer); any comments tl.lex parked on it move to
-- the following token, where the stream built from this array picks them up.
-- Already-stamped node indices all point at or before the parse frontier
-- where the removal happens, so they stay valid; everything parsed later is
-- stamped against the compacted array. A trial parse that removed a `;` is
-- safe to roll back: the retry walks the same grammar over the compacted
-- array and a statement `;` never re-parses as anything else.
local function remove_statement_semi(ps: ParseState, i: integer)
    local semi = ps.tokens[i]
    local following = ps.tokens[i + 1]
    if following ~= nil and semi.comments ~= nil and #semi.comments > 0 then
        local merged: {tl.LexerComment} = {}
        for k = 1, #semi.comments do
            merged[#merged + 1] = semi.comments[k]
        end
        for k = 1, #(following.comments or {}) do
            merged[#merged + 1] = following.comments[k]
        end
        following.comments = merged
    end
    table.remove(ps.tokens, i)
end

local enum ParseTypeListMode
    "rets"
    "decltuple"
    "casttype"
end

local enum BodyTypeName
    "interface"
    "record"
    "enum"
end

local enum FunctionKind
    "global"
    "record"
end

local enum SeparatorMode
    "sep"
    "term"
end

local parse_type_list: function(
    ParseState, integer, ParseTypeListMode, ?ast.HasTokenSpan
): integer, TupleType

local parse_typeargs_if_any: function(
    ps: ParseState, i: integer
): integer, {TypeArgType}

local parse_expression: function(ParseState, integer): integer, Node, integer
local parse_expression_and_tk: function(
    ps: ParseState, i: integer, tk: string
): integer, Node

local parse_statements: function(ParseState, integer, ?boolean): integer, Node
local parse_argument_list: function(ParseState, integer): integer, Node

local parse_type: function(ParseState, integer): integer, Type, integer
local parse_type_declaration: function(
    ps: ParseState, i: integer, node_name: NodeKind
): integer, Node

local parse_interface_name: function(ps: ParseState, i: integer): integer, Type, integer

local parse_enum_body: function(
    ps: ParseState, i: integer, def: EnumType
): integer, boolean

local parse_record_body: function(
    ps: ParseState, i: integer, def: RecordLikeType
): integer, boolean

-- The keywords that introduce a type body. Membership only: the body parsers
-- are dispatched per kind (parse_body_by_kind), each taking the type it
-- actually parses into.
local type_body_keywords: {BodyTypeName: boolean} = {
    ["interface"] = true,
    ["record"] = true,
    ["enum"] = true,
}

do
    -- Raised by fail and caught in exactly two places -- attempt (the one
    -- speculation primitive) and parser.parse (the fail-fast catch, the Lua
    -- lparser idiom); identity comparison keeps genuine runtime errors
    -- propagating. The formatter never renders a file with parse errors, so
    -- the parse aborts at the first one.
    local parse_abort <const>: any = {}

    -- Declared to return an integer so grammar paths can `return fail(...)`
    -- and typecheck, but it always raises.
    local function fail(ps: ParseState, i: integer, msg: string): integer
        local token = ps.tokens[i] or ps.tokens[#ps.tokens]
        table.insert(
            ps.errs,
            {
                filename = ps.filename,
                y = token.y,
                x = token.x,
                msg = assert(msg, "syntax error, but no error message provided"),
            }
        )
        error(parse_abort)
    end

    local function end_at(node: Node, ps: ParseState, i: integer)
        node.yend = ps.tokens[i].y
        node.tok_last = i
    end

    -- Closes a type's token span. Unlike end_at it stamps only tok_last: the
    -- render layer reads yend off nodes alone, so types carry none.
    local function end_span_at(span: HasTokenSpan, i: integer)
        span.tok_last = i
    end

    local function verify_tk(ps: ParseState, i: integer, tk: string): integer
        if ps.tokens[i].tk == tk then
            return i + 1
        end
        return fail(ps, i, "syntax error, expected '" .. tk .. "'")
    end

    local function verify_end(
        ps: ParseState, i: integer, istart: integer, node: Node
    ): integer
        if ps.tokens[i].tk == "end" then
            node.yend = ps.tokens[i].y
            node.tok_last = i
            return i + 1
        end
        end_at(node, ps, i)
        local location = ps.filename
            .. ":"
            .. ps.tokens[istart].y
            .. ":"
            .. ps.tokens[istart].x
            .. ":"
        return fail(
            ps,
            i,
            "syntax error, expected 'end' to close construct started at " .. location
        )
    end

    local node_mt: metatable<Node> = {
        __tostring = function(n: Node): string
            return n.f .. ":" .. n.y .. ":" .. n.x .. " " .. n.kind
        end,
    }

    local function new_node(ps: ParseState, i: integer, kind: NodeKind): Node
        local t = ps.tokens[i]
        return setmetatable(
            {
                f = ps.filename,
                y = t.y,
                x = t.x,
                tk = t.tk,
                kind = kind,
                tok_first = i,
            },
            node_mt
        )
    end

    local function new_type(ps: ParseState, i: integer, typename: TypeName): Type
        local token = ps.tokens[i]
        local t: Type = setmetatable({}, type_mt)
        t.f = ps.filename
        t.x = token.x
        t.y = token.y
        t.typename = typename
        t.tok_first = i
        return t
    end

    local function new_enum_body_type(ps: ParseState, i: integer): EnumType
        return new_type(ps, i, "enum") as EnumType
    end

    local function new_record_like_body_type(
        ps: ParseState, i: integer, tn: BodyTypeName
    ): RecordLikeType
        if tn == "interface" then
            return new_type(ps, i, "interface") as InterfaceType
        end
        return new_type(ps, i, "record") as RecordType
    end

    local function new_generic(
        ps: ParseState, i: integer, typeargs: {TypeArgType}, typ: Type
    ): GenericType
        local gt = new_type(ps, i, "generic") as GenericType
        gt.typeargs = typeargs
        gt.t = typ
        return gt
    end

    local function new_tuple(
        ps: ParseState, i: integer, types?: {Type}, is_va?: boolean
    ): TupleType, {Type}
        local t = new_type(ps, i, "tuple") as TupleType
        t.is_va = is_va
        t.tuple = types or {}
        return t, t.tuple
    end

    local function new_nominal(ps: ParseState, i: integer, name?: string): NominalType
        local t = new_type(ps, i, "nominal") as NominalType
        if name then
            t.names = {name}
        end
        return t
    end

    local function verify_kind(
        ps: ParseState, i: integer, kind: TokenKind, node_kind: NodeKind
    ): integer, Node
        if ps.tokens[i].kind == kind then
            return i + 1, new_node(ps, i, node_kind)
        end
        return fail(ps, i, "syntax error, expected " .. kind)
    end

    -- A sub-parse collects its own errors so a probe that fails leaks none of them.
    local function fork(ps: ParseState): ParseState
        return {
            filename = ps.filename,
            tokens = ps.tokens,
            errs = {},
            macro_params = ps.macro_params,
            allow_bare_type = ps.allow_bare_type,
        }
    end

    local type ParseItem = function<T>(
        ParseState, integer, ?integer
    ): integer, T, integer

    -- The parser's only speculation primitive: trial-parses one item on a forked
    -- state so a "does an X start here?" probe leaks neither errors nor the parse
    -- abort. On success returns the advanced index + item; on failure the
    -- original index and nil. Every grammar spot that needs backtracking routes
    -- through here -- the abort raised by fail is caught in exactly two places,
    -- this pcall and the one in parser.parse.
    local function attempt<T>(
        ps: ParseState, i: integer, parse_item: ParseItem<T>
    ): integer, T
        local ok, tryi, item = pcall(parse_item, fork(ps), i)
        if not ok then
            if tryi ~= parse_abort then
                error(tryi)
            end
            return i
        end
        if not item then
            return i
        end
        return tryi, item
    end

    -- Each body kind builds the type it parses into and hands it to the parser
    -- typed for it, so the pairing is checked rather than asserted through one
    -- homogeneous map.
    local function parse_body_by_kind(
        ps: ParseState, i: integer, istart: integer, tn: BodyTypeName
    ): integer, Type, boolean
        if tn == "enum" then
            local def = new_enum_body_type(ps, istart)
            local next_i, ok = parse_enum_body(ps, i, def)
            return next_i, def, ok
        end
        local def = new_record_like_body_type(ps, istart, tn)
        local next_i, ok = parse_record_body(ps, i, def)
        return next_i, def, ok
    end

    local function parse_type_body(
        ps: ParseState, i: integer, istart: integer, node: Node, tn: BodyTypeName
    ): integer, Type
        local typeargs: {TypeArgType}
        i, typeargs = parse_typeargs_if_any(ps, i)

        local def: Type
        local ok: boolean
        i, def, ok = parse_body_by_kind(ps, i, istart, tn)
        if not ok then
            return fail(ps, i, "expected a type")
        end

        i = verify_end(ps, i, istart, node)
        -- Span the body type over its closing `end`, so the renderer can route the
        -- body's own-line tail comments to its dangling slot.
        def.tok_last = i - 1

        if typeargs then
            return i, new_generic(ps, istart, typeargs, def)
        end

        return i, def
    end

    local function parse_table_value(ps: ParseState, i: integer): integer, Node, integer
        local next_word = ps.tokens[i].tk
        if next_word == "enum" and ps.tokens[i + 1].kind == "string" then
            return fail(
                ps,
                i,
                "syntax error: this syntax is no longer valid; declare nested enum inside a record"
            )
        end

        local e: Node
        i, e = parse_expression(ps, i)
        if not e then
            return fail(ps, i, "syntax error, expected an expression")
        end
        return i, e
    end

    local function token_yend(tk: Token): integer
        if tk.kind == "string" or tk.kind == "`" then
            local _, line_breaks = tk.tk:gsub("\n", "\n")
            return tk.y + line_breaks
        end
        return tk.y
    end

    -- Consuming a token that opens a positional trivia slot records which token
    -- it was, so the renderer can read that token's same-line comment for the
    -- slot. The comment stays on the token.
    local function verify_tk_into(
        ps: ParseState, i: integer, tk: string, node: HasOpenerSlots, slot: InlineSlot
    ): integer
        i = verify_tk(ps, i, tk)
        set_slot_tok(node, slot, i - 1)
        return i
    end

    local function close_stmt(
        ps: ParseState, i: integer, istart: integer, node: Node
    ): integer, Node
        i = verify_end(ps, i, istart, node)
        return i, node
    end

    -- The typed-key table item `key: Type = value`. `identifier :` also opens a
    -- method-call expression item (`x:method()`), so past the `:` this fails
    -- unless a type and an `= value` both follow; `attempt` rolls the trial back
    -- and the caller re-parses the item as an expression.
    local function parse_typed_key_item(
        ps: ParseState, i: integer
    ): integer, Node, integer
        local node = new_node(ps, i, "literal_table_item")
        node.key_parsed = "short"
        i, node.key = verify_kind(ps, i, "identifier", "string")
        node.key.conststr = node.key.tk
        node.key.tk = '"' .. node.key.tk .. '"'
        node.key.tok_bound = i
        i = verify_tk(ps, i, ":")
        i, node.itemtype = parse_type(ps, i)
        if not node.itemtype or ps.tokens[i].tk ~= "=" then
            return fail(ps, i, "expected '=' after the typed key")
        end
        node.itemtype.tok_bound = i
        i = verify_tk(ps, i, "=")
        i, node.value = parse_table_value(ps, i)
        if not node.value then
            return fail(ps, i, "expected a value")
        end
        node.yend = token_yend(ps.tokens[i - 1])
        node.tok_last = i - 1
        return i, node
    end

    local function parse_table_item(
        ps: ParseState, i: integer, n?: integer
    ): integer, Node, integer
        local node = new_node(ps, i, "literal_table_item")
        if ps.tokens[i].kind == "$EOF$" then
            return fail(ps, i, "unexpected eof")
        end

        if ps.tokens[i].tk == "[" then
            node.key_parsed = "long"
            i = i + 1
            i, node.key = parse_expression_and_tk(ps, i, "]")
            i = verify_tk(ps, i, "=")
            i, node.value = parse_table_value(ps, i)
            node.yend = token_yend(ps.tokens[i - 1])
            node.tok_last = i - 1
            return i, node, n
        elseif ps.tokens[i].kind == "identifier" then
            if ps.tokens[i + 1].tk == "=" then
                node.key_parsed = "short"
                i, node.key = verify_kind(ps, i, "identifier", "string")
                node.key.conststr = node.key.tk
                node.key.tk = '"' .. node.key.tk .. '"'
                node.key.tok_bound = i
                i = verify_tk_into(ps, i, "=", node, "after_opener")
                i, node.value = parse_table_value(ps, i)
                node.yend = token_yend(ps.tokens[i - 1])
                node.tok_last = i - 1
                return i, node, n
            elseif ps.tokens[i + 1].tk == ":" then
                local typed_i, typed = attempt(ps, i, parse_typed_key_item)
                if typed then
                    return typed_i, typed, n
                end
                -- backtracked: not a `key: type = value` item after all
            end
        end

        node.key = new_node(ps, i, "integer")
        node.key_parsed = "implicit"
        node.key.tk = tostring(n)
        i, node.value = parse_expression(ps, i)
        if not node.value then
            return fail(ps, i, "expected an expression")
        end
        node.yend = token_yend(ps.tokens[i - 1])
        node.tok_last = i - 1
        return i, node, n + 1
    end

    local function parse_list<T is Node>(
        ps: ParseState,
        i: integer,
        list: {T},
        close: {string: boolean},
        sep: SeparatorMode,
        parse_item: ParseItem<T>,
        owns_closer?: boolean
    ): integer, {T}
        local n = 1
        while ps.tokens[i].kind ~= "$EOF$" do
            if close[ps.tokens[i].tk] then
                end_at(list as Node, ps, i)
                if not owns_closer then
                    -- The closing token belongs to an enclosing construct (a
                    -- `do`/`in`/`end` terminator, not this list's own bracket), so
                    -- retract the span off it: a comment in the gap before that
                    -- token must resolve to the enclosing block, not this list.
                    local last = list[#list]
                    if last then
                        (list as Node).tok_last = last.tok_last
                    else
                        (list as Node).tok_first = nil
                        (list as Node).tok_last = nil
                    end
                end
                break
            end
            local item: T
            local oldn = n
            i, item, n = parse_item(ps, i, n)
            n = n or oldn
            table.insert(list, item)
            if ps.tokens[i].tk == "," then
                item.tok_sep = i
                i = i + 1
                if sep == "sep" and close[ps.tokens[i].tk] then
                    fail(ps, i, "unexpected '" .. ps.tokens[i].tk .. "'")
                    return i, list
                end
            elseif sep == "term" and ps.tokens[i].tk == ";" then
                item.tok_sep = i
                i = i + 1
            elseif not close[ps.tokens[i].tk] then
                local options: {string} = {}
                for k, _ in pairs(close) do
                    table.insert(options, "'" .. k .. "'")
                end
                table.sort(options)
                table.insert(options, "','")
                return fail(
                    ps,
                    i,
                    "syntax error, expected one of: " .. table.concat(options, ", ")
                )
            end
        end
        return i, list
    end

    local function parse_bracket_list<T is Node>(
        ps: ParseState,
        i: integer,
        list: {T},
        open: string,
        close: string,
        sep: SeparatorMode,
        parse_item: ParseItem<T>
    ): integer, {T}
        i = verify_tk(ps, i, open)
        i = parse_list(ps, i, list, {[close] = true}, sep, parse_item, true)
        i = verify_tk(ps, i, close)
        return i, list
    end

    local function parse_table_literal(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "literal_table")
        i, node = parse_bracket_list(ps, i, node, "{", "}", "term", parse_table_item)
        local last = node[#node]
        node.trailing_comma = last ~= nil and last.tok_sep ~= nil
        -- The place after the last item is a separator position whether or not
        -- the source filled it, so the closer bounds that item's claim just as a
        -- written separator would. Unbounded, a block comment there renders past
        -- the separator the formatter adds and the next parse reads across it.
        if last ~= nil and not node.trailing_comma then
            last.tok_bound = node.tok_last
        end
        return i, node
    end

    -- Walks the `sep`-separated tail of a list whose first element is already in
    -- `list`. `i` points at the first separator or the closer. `ret_lookahead`
    -- stops at a `,` that opens a named return tuple (`function(): (a, b: T)`).
    -- One walker for both node and type lists. The second return is false when a
    -- separator was consumed but the item after it failed to parse; parse_item
    -- does not always record an error (parse_expression fails silently), so
    -- callers that must reject the construct check this instead.
    local function thread_list<T is HasTokenSpan>(
        ps: ParseState,
        i: integer,
        list: {T},
        parse_item: ParseItem<T>,
        sep: string,
        ret_lookahead?: boolean
    ): integer, boolean
        while
            ps.tokens[i].tk == sep
            and (
                not ret_lookahead
                or not (
                    ps.tokens[i + 1].kind == "identifier"
                        and ps.tokens[i + 2]
                        and ps.tokens[i + 2].tk == ":"
                )
            )
        do
            list[#list].tok_sep = i
            i = i + 1
            local item: T
            i, item = parse_item(ps, i)
            if not item then
                return i, false
            end
            table.insert(list, item)
        end
        return i, true
    end

    -- Optional list: trial-parses the first element (so an absent list is not a
    -- hard error), then threads the comma tail. Serves both node lists
    -- (assignment / declaration variables) and type lists (interface lists).
    local function parse_trying_list<T is HasTokenSpan>(
        ps: ParseState, i: integer, list: {T}, parse_item: ParseItem<T>
    ): integer, {T}
        local item: T
        i, item = attempt(ps, i, parse_item)
        if not item then
            return i, list
        end
        table.insert(list, item)
        i = thread_list(ps, i, list, parse_item, ",")
        return i, list
    end

    local function parse_anglebracket_list<T is Type>(
        ps: ParseState, i: integer, parse_item: ParseItem<T>
    ): integer, {T}
        local second = ps.tokens[i + 1]
        if second.tk == ">" then
            return fail(ps, i + 1, "type argument list cannot be empty")
        elseif second.tk == ">>" then
            second.tk = ">"
            fail(ps, i + 1, "type argument list cannot be empty")
            return i + 1
        end

        i = verify_tk(ps, i, "<")
        local types: {T} = {}
        local first: T
        i, first = parse_item(ps, i)
        if first then
            table.insert(types, first)
            i = thread_list(ps, i, types, parse_item, ",")
        end
        if ps.tokens[i].tk == ">" then
            i = i + 1
        elseif ps.tokens[i].tk == ">>" then
            ps.tokens[i].tk = ">"
        else
            return fail(ps, i, "syntax error, expected '>'")
        end
        return i, types
    end

    local function parse_typearg(
        ps: ParseState, i: integer
    ): integer, TypeArgType, integer
        local name = ps.tokens[i].tk
        local constraint: Type
        local t = new_type(ps, i, "typearg") as TypeArgType
        i = verify_kind(ps, i, "identifier", "name")
        if ps.tokens[i].tk == "is" then
            i = i + 1
            i, constraint = parse_interface_name(ps, i)
        end
        t.typearg = name
        t.constraint = constraint
        return i, t
    end

    local function parse_return_types(
        ps: ParseState, i: integer, args: Node
    ): integer, TupleType
        local iprev = i - 1
        local t: TupleType
        i, t = parse_type_list(ps, i, "rets", args)
        if #t.tuple == 0 then
            t.x = ps.tokens[iprev].x
            t.y = ps.tokens[iprev].y
        end
        return i, t
    end

    parse_typeargs_if_any = function(ps: ParseState, i: integer): integer, {TypeArgType}
        if ps.tokens[i].tk == "<" then
            return parse_anglebracket_list(ps, i, parse_typearg)
        end
        return i
    end

    local function parse_function_type(
        ps: ParseState, i: integer
    ): integer, GenericType | FunctionType
        local istart = i
        local typeargs: {TypeArgType}
        local typ = new_type(ps, i, "function") as FunctionType
        i = i + 1

        i, typeargs = parse_typeargs_if_any(ps, i)
        if ps.tokens[i].tk == "(" then
            i, typ.args = parse_argument_list(ps, i)
            typ.maybe_method = #typ.args > 0 and typ.args[1].tk == "self"
            i, typ.rets = parse_return_types(ps, i, typ.args)
        else
            typ.bare = true
            typ.rets = new_tuple(ps, i, {new_type(ps, i, "any")}, true)
            typ.is_method = false
        end
        typ.yend = ps.tokens[i - 1].y
        typ.tok_last = i - 1

        if typeargs then
            return i, new_generic(ps, istart, typeargs, typ)
        end

        return i, typ
    end

    local function parse_simple_type_or_nominal(
        ps: ParseState, i: integer
    ): integer, Type
        local tk = ps.tokens[i].tk
        local st = simple_types[tk as TypeName]
        if st and ps.tokens[i + 1].tk ~= "." then
            return i + 1, new_type(ps, i, tk as TypeName)
        end

        -- A nominal starts with an identifier; anything else here (a keyword,
        -- EOF) is a syntax error, not a name to walk dots from.
        if ps.tokens[i].kind ~= "identifier" then
            return fail(ps, i, "expected a type")
        end

        local typ = new_nominal(ps, i, tk)
        i = i + 1
        while ps.tokens[i].tk == "." do
            i = i + 1
            if ps.tokens[i].kind == "identifier" then
                table.insert(typ.names, ps.tokens[i].tk)
                i = i + 1
            else
                return fail(ps, i, "syntax error, expected identifier")
            end
        end

        if ps.tokens[i].tk == "<" then
            i, typ.typevals = parse_anglebracket_list(ps, i, parse_type)
        end
        return i, typ
    end

    local function parse_base_type_core(
        ps: ParseState, i: integer
    ): integer, Type, integer
        local tk = ps.tokens[i].tk
        if ps.tokens[i].kind == "identifier" then
            return parse_simple_type_or_nominal(ps, i)
        elseif tk == "{" then
            local istart = i
            i = i + 1
            local t: Type
            i, t = parse_type(ps, i)
            if not t then
                return i
            end
            if ps.tokens[i].tk == "}" then
                local decl = new_type(ps, istart, "array") as ArrayType
                decl.elements = t
                end_span_at(decl, i)
                i = verify_tk(ps, i, "}")
                return i, decl
            elseif ps.tokens[i].tk == "," then
                local decl = new_type(ps, istart, "tupletable") as TupleTableType
                decl.types = {t}
                i = thread_list(ps, i, decl.types, parse_type, ",")
                end_span_at(decl, i)
                i = verify_tk(ps, i, "}")
                return i, decl
            elseif ps.tokens[i].tk == ":" then
                local decl = new_type(ps, istart, "map") as MapType
                decl.keys = t
                t.tok_bound = i
                i = i + 1
                i, decl.values = parse_type(ps, i)
                if not decl.values then
                    return i
                end
                end_span_at(decl, i)
                i = verify_tk(ps, i, "}")
                return i, decl
            end
            return fail(ps, i, "syntax error; did you forget a '}'?")
        elseif tk == "function" then
            return parse_function_type(ps, i)
        elseif tk == "nil" then
            return i + 1, new_type(ps, i, "nil") as NilType
        end
        return fail(ps, i, "expected a type")
    end

    local function parse_base_type(ps: ParseState, i: integer): integer, Type, integer
        local bt: Type
        local n: integer
        i, bt, n = parse_base_type_core(ps, i)
        -- Stamp the end token on every base type, including union members that
        -- thread_list parses straight through (the outer parse_type only records
        -- the whole union), so every type carries an accurate span.
        if bt then
            bt.tok_last = i - 1
        end
        return i, bt, n
    end

    parse_type = function(ps: ParseState, i: integer): integer, Type, integer
        if ps.tokens[i].tk == "(" then
            i = i + 1
            local t: Type
            i, t = parse_type(ps, i)
            i = verify_tk(ps, i, ")")
            if t then
                t.paren = true
                -- Extend the span over the wrapping ')' the type owns.
                t.tok_last = i - 1
            end
            return i, t
        end

        local bt: Type
        local istart = i
        i, bt = parse_base_type(ps, i)
        if not bt then
            return i
        end
        if ps.tokens[i].tk == "|" then
            local u = new_type(ps, istart, "union") as UnionType
            u.types = {bt}
            i = thread_list(ps, i, u.types, parse_base_type, "|")
            bt = u
        end
        -- Record the end token for every type the leaf constructors miss (simple
        -- and nominal types, unions); the structured kinds already set it and
        -- i - 1 is the same last-consumed token, so this stays consistent.
        bt.tok_last = i - 1
        return i, bt
    end

    -- `bound_owner` is the node whose last token directly precedes this list's
    -- `:` (the declared variables, a signature's `)`); the ':' bounds that
    -- node's same-line trivia claim, so it is stamped as its tok_bound.
    parse_type_list = function(
        ps: ParseState, i: integer, mode: ParseTypeListMode, bound_owner?: HasTokenSpan
    ): integer, TupleType
        local t, list = new_tuple(ps, i)

        local first_token = ps.tokens[i].tk
        if mode == "rets" or mode == "decltuple" then
            if first_token == ":" then
                if bound_owner ~= nil then
                    bound_owner.tok_bound = i
                end
                i = i + 1
            else
                -- Implicit (no `:`) return/decl tuple owns no tokens; drop its
                -- span so the renderer never resolves a comment onto this phantom
                -- that starts on the following construct's first token.
                t.tok_first = nil
                return i, t
            end
        end

        local optional_paren = false
        local open_paren_i = 0
        if ps.tokens[i].tk == "(" then
            optional_paren = true
            open_paren_i = i
            i = i + 1
        end

        -- Trial-parse the first type so an empty list (legal after ':' or '(')
        -- is not reported as a hard error.
        local first_type: Type
        i, first_type = attempt(ps, i, parse_type)
        if not first_type then
            if ps.tokens[i].tk ~= ")" then
                fail(ps, i - 1, "expected a type list")
            end
            -- No element to carry post-'(' comments (e.g. `as(--[[c]])`): record
            -- the '(' as the tuple's after_opener so the renderer reads them there.
            if optional_paren then
                set_slot_tok(t, "after_opener", open_paren_i)
            end
        else
            table.insert(list, first_type)
            i = thread_list(ps, i, list, parse_type, ",", mode == "rets")
        end

        if mode == "rets" and ps.tokens[i].tk == "..." then
            i = i + 1
            local nrets = #list
            if nrets > 0 then
                t.is_va = true
            else
                fail(ps, i, "unexpected '...'")
            end
        end

        if optional_paren then
            i = verify_tk(ps, i, ")")
            t.paren = true
            -- Span the tuple over the closing ')' it owns.
            t.tok_last = i - 1
        elseif #list > 0 then
            t.tok_last = list[#list].tok_last
        else
            -- An empty, unparenthesized tuple owns no tokens; drop its span.
            t.tok_first = nil
        end

        return i, t
    end

    local function parse_function_args_rets_body(
        ps: ParseState, i: integer, node: Node
    ): integer, Node
        local istart = i - 1
        i, node.typeargs = parse_typeargs_if_any(ps, i)
        i, node.args = parse_argument_list(ps, i)
        i, node.rets = parse_return_types(ps, i, node.args)
        set_slot_tok(node, "head", i - 1)
        i, node.body = parse_statements(ps, i)
        end_at(node, ps, i)
        i = verify_end(ps, i, istart, node)
        return i, node
    end

    local function parse_function_value(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "function")
        i = verify_tk(ps, i, "function")
        return parse_function_args_rets_body(ps, i, node)
    end

    local function unquote(str: string): string, boolean
        local f = str:sub(1, 1)
        if f == '"' or f == "'" then
            return str:sub(2, -2), false
        end
        f = str:match("^%[=*%[")
        local l = #f + 1
        return str:sub(l, -l), true
    end

    local function parse_literal(ps: ParseState, i: integer): integer, Node
        local tk = ps.tokens[i].tk
        local kind = ps.tokens[i].kind
        if kind == "identifier" then
            return verify_kind(ps, i, "identifier", "name")
        elseif kind == "string" then
            local node = new_node(ps, i, "string")
            node.conststr, node.is_longstring = unquote(tk)
            node.yend = token_yend(ps.tokens[i])
            node.tok_last = i
            return i + 1, node
        elseif kind == "`" then
            -- A macro quote lexes as one token, delimiters and newlines included,
            -- so the formatter carries it through untouched like a long string.
            local node = new_node(ps, i, "macro_quote")
            node.yend = token_yend(ps.tokens[i])
            return i + 1, node
        elseif kind == "number" then
            return verify_kind(ps, i, "number", "number")
        elseif kind == "integer" then
            return verify_kind(ps, i, "integer", "integer")
        elseif tk == "true" then
            return verify_kind(ps, i, "keyword", "boolean")
        elseif tk == "false" then
            return verify_kind(ps, i, "keyword", "boolean")
        elseif tk == "nil" then
            return verify_kind(ps, i, "keyword", "nil")
        elseif tk == "function" then
            return parse_function_value(ps, i)
        elseif tk == "{" then
            return parse_table_literal(ps, i)
        elseif kind == "..." then
            return verify_kind(ps, i, "...", "...")
        elseif kind == "$ERR$" then
            return fail(ps, i, "invalid token")
        end
        return fail(ps, i, "syntax error")
    end

    do
        local precedences: {integer: {string: integer}} = {
            [1] = {
                ["not"] = 11,
                ["#"] = 11,
                ["-"] = 11,
                ["~"] = 11,
            },
            [2] = {
                ["or"] = 1,
                ["and"] = 2,
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
                ["^"] = 12,
            },
        }

        local is_right_assoc: {string: boolean} = {
            ["^"] = true,
            [".."] = true,
        }

        local function new_operator(tk: Token, arity: integer, op: string): Operator
            return {
                y = tk.y,
                x = tk.x,
                arity = arity,
                op = op,
                prec = precedences[arity][op],
            }
        end

        local args_starters: {TokenKind: boolean} = {
            ["("] = true,
            ["{"] = true,
            ["string"] = true,
        }

        local E: function(ParseState, integer, Node, integer): integer, Node

        local function after_valid_prefixexp(
            ps: ParseState, prevnode: Node, i: integer
        ): boolean
            return ps.tokens[i - 1].kind == ")"
                or prevnode.kind == "field"
                or prevnode.kind == "method"
                or prevnode.kind == "index"
                or prevnode.kind == "call"
                or prevnode.kind == "name"
        end

        -- A top-level comma belongs to the statement itself unless another argument
        -- is still expected, as in `wrap!(a, b = 1, 2)`. Teal instead keeps the
        -- longest extent that parses, which is why `pair!(z = 3, 7)` reaches it as
        -- one argument.
        local function statement_argument_end(
            ps: ParseState, i: integer, more_arguments_follow: boolean
        ): integer
            local depth = 0
            while ps.tokens[i].kind ~= "$EOF$" do
                local tk = ps.tokens[i].tk
                if
                    depth == 0 and (tk == ")" or (tk == "," and more_arguments_follow))
                then
                    return i
                end
                if tk == "(" or tk == "[" or tk == "{" then
                    depth = depth + 1
                elseif tk == ")" or tk == "]" or tk == "}" then
                    depth = depth - 1
                end
                i = i + 1
            end
            return i
        end

        -- The statement-list trial for parse_statement_argument, shaped for
        -- `attempt`. Bare type names read as expressions here: a macroexp hands
        -- types where expressions go. The flag mutates only `attempt`'s fork.
        local function parse_statement_slice(
            ps: ParseState, i: integer
        ): integer, Node, integer
            ps.allow_bare_type = true
            local next_i, parsed = parse_statements(ps, i, true)
            return next_i, parsed
        end

        -- The argument parses as a statement list on the file's own token array, so
        -- every stamp it writes (tok_first/tok_last/tok_bound/slot_tok) addresses the
        -- array the renderer reads. Only the argument's end token is masked: a
        -- synthetic `$EOF$` standing in its place stops the list there, and the real
        -- token goes back once the parse returns. A statement `;` inside the argument
        -- is deleted from the array like any other, which shifts the mask left, so the
        -- restore finds the sentinel rather than trusting the original index.
        local function parse_statement_argument(
            ps: ParseState, i: integer, more_arguments_follow: boolean
        ): integer, Node
            local stop = statement_argument_end(ps, i, more_arguments_follow)
            local end_token = ps.tokens[stop]
            local last = ps.tokens[math.max(i, stop - 1)]
            local sentinel: Token = {
                y = last.y,
                x = last.x,
                tk = "$EOF$",
                kind = "$EOF$",
            }
            ps.tokens[stop] = sentinel

            local _, slice = attempt(ps, i, parse_statement_slice)

            local end_i = stop
            for k = stop, i, -1 do
                if ps.tokens[k] == sentinel then
                    ps.tokens[k] = end_token
                    end_i = k
                    break
                end
            end

            if slice ~= nil then
                return end_i, slice
            end

            -- Teal rejects a `Statement` parameter handed anything else, but a
            -- formatter still has to produce something.
            local next_i, exp = parse_expression(ps, i)
            return next_i, exp
        end

        -- A trailing `...` governs every argument from its own position on. Past a
        -- fixed list there is no parameter, which is also how the caller asks
        -- whether another argument is still expected.
        local function macro_param(params: Node, n: integer): Node
            local last = params[#params]
            if n > #params and last ~= nil and last.is_va then
                return last
            end
            return params[n]
        end

        -- Teal rejects any other annotation. A formatter stays permissive, so an
        -- unannotated parameter's argument reads as an expression.
        local function is_statement_param(param: Node): boolean
            local argtype = param ~= nil and param.argtype
            return argtype is NominalType and argtype.names[1] == "Statement"
        end

        -- `parse_list` keeps the index each item returns, so every branch has to
        -- advance it or the parameter lookup drifts.
        local function macro_arg_parser(params: Node): ParseItem<Node>
            return function(
                ps: ParseState, i: integer, n: integer
            ): integer, Node, integer
                if not is_statement_param(macro_param(params, n)) then
                    local next_i, exp = parse_expression(ps, i)
                    return next_i, exp, n + 1
                end
                local more_follow = macro_param(params, n + 1) ~= nil
                local next_i, node = parse_statement_argument(ps, i, more_follow)
                return next_i, node, n + 1
            end
        end

        local function P(ps: ParseState, i: integer): integer, Node
            if ps.tokens[i].kind == "$EOF$" then
                return i
            end
            local e1: Node
            local t1 = ps.tokens[i]
            local i_t1 = i
            if precedences[1][t1.tk] ~= nil then
                local op: Operator = new_operator(t1, 1, t1.tk)
                i = i + 1
                local prev_i = i
                i, e1 = P(ps, i)
                if not e1 then
                    fail(ps, prev_i, "expected an expression")
                    return i
                end
                e1 = {
                    f = ps.filename,
                    y = t1.y,
                    x = t1.x,
                    kind = "op",
                    op = op,
                    e1 = e1,
                    yend = e1.yend or e1.y,
                    tok_first = i_t1,
                    tok_last = e1.tok_last,
                    tok_op = i_t1,
                }
            elseif ps.tokens[i].tk == "(" then
                i = i + 1
                local prev_i = i
                i, e1 = parse_expression_and_tk(ps, i, ")")
                if not e1 then
                    fail(ps, prev_i, "expected an expression")
                    return i
                end
                e1 = {
                    f = ps.filename,
                    y = t1.y,
                    x = t1.x,
                    kind = "paren",
                    e1 = e1,
                    yend = ps.tokens[i - 1].y,
                    tok_first = i_t1,
                    tok_last = i - 1,
                }
            else
                i, e1 = parse_literal(ps, i)
            end

            if not e1 then
                return i
            end

            -- Set before the member/call loop below so operands wrapped into
            -- op nodes already carry yend; renderers then never need a
            -- `yend or y` fallback for expression nodes.
            e1.yend = e1.yend or token_yend(ps.tokens[i - 1])
            e1.tok_last = e1.tok_last or i - 1

            while true do
                local tkop = ps.tokens[i]
                if tkop.kind == "," or tkop.kind == ")" then
                    break
                end
                -- `!` only marks the call that follows it as a macro invocation. Its
                -- arguments take the same shapes a call's arguments do, so the
                -- branches below read them unchanged.
                local is_macro_invocation = tkop.tk == "!"
                -- Undeclared leaves this nil and the arguments stay expressions,
                -- which is what `f!(...)` got before and what Teal rejects outright.
                local macro_params: Node = nil
                if is_macro_invocation then
                    if e1.kind == "name" then
                        macro_params = ps.macro_params[e1.tk]
                    end
                    i = i + 1
                    tkop = ps.tokens[i]
                    if not args_starters[tkop.kind] then
                        return fail(ps, i, "expected macro arguments")
                    end
                end
                if tkop.tk == "." or tkop.tk == ":" then
                    local is_method = tkop.tk == ":"

                    local prev_i = i

                    local key: Node
                    i = i + 1
                    i, key = verify_kind(ps, i, "identifier", "name")

                    if is_method then
                        if not args_starters[ps.tokens[i].kind] then
                            return fail(ps, i, "expected a function call for a method")
                        end

                        if not after_valid_prefixexp(ps, e1, prev_i) then
                            return fail(
                                ps, prev_i, "cannot call a method on this expression"
                            )
                        end
                    end

                    e1 = {
                        f = ps.filename,
                        y = e1.y,
                        x = e1.x,
                        kind = is_method and "method" or "field",
                        op_y = tkop.y,
                        e1 = e1,
                        e2 = key,
                        yend = key.yend or key.y,
                        tok_first = e1.tok_first,
                        tok_last = key.tok_last or key.tok_first,
                        tok_op = prev_i,
                    }
                elseif tkop.tk == "(" then
                    local prev_tk = ps.tokens[i - 1]
                    if tkop.y > prev_tk.y then
                        -- A `(` opening a fresh line is a new statement, not a call
                        -- of the expression before it (Teal rejects the ambiguous
                        -- cross-line call). End the suffix chain here; the `(`
                        -- statement is parsed next. The chain end alone marks the
                        -- boundary, so the token array is left untouched and stays
                        -- index-aligned with the renderer's lossless token stream.
                        break
                    end

                    local prev_i = i

                    local args = new_node(ps, i, "expression_list")
                    local open_paren_i = i
                    local parse_arg: ParseItem<Node> = parse_expression
                    if macro_params then
                        parse_arg = macro_arg_parser(macro_params)
                    end
                    i, args = parse_bracket_list(
                        ps, i, args, "(", ")", "sep", parse_arg
                    )
                    -- The argument list's '(' opens its after_opener slot; the
                    -- renderer reads a same-line comment after it there, and
                    -- computes the args' blank lines and dangling/trailing from
                    -- their spans.
                    set_slot_tok(args, "after_opener", open_paren_i)

                    if not after_valid_prefixexp(ps, e1, prev_i) then
                        return fail(ps, prev_i, "cannot call this expression")
                    end

                    local funcall_yend = math.max(args.yend or args.y, args.y)
                    e1 = {
                        f = ps.filename,
                        y = e1.y,
                        x = e1.x,
                        yend = funcall_yend,
                        kind = "call",
                        e1 = e1,
                        e2 = args,
                        is_macro_invocation = is_macro_invocation,
                        tok_first = e1.tok_first,
                        tok_last = i - 1,
                    }
                elseif tkop.tk == "[" then
                    local prev_i = i

                    local idx: Node
                    i = i + 1
                    i, idx = parse_expression_and_tk(ps, i, "]")

                    if not after_valid_prefixexp(ps, e1, prev_i) then
                        return fail(ps, prev_i, "cannot index this expression")
                    end

                    e1 = {
                        f = ps.filename,
                        y = e1.y,
                        x = e1.x,
                        kind = "index",
                        e1 = e1,
                        e2 = idx,
                        yend = ps.tokens[i - 1].y,
                        tok_first = e1.tok_first,
                        tok_last = i - 1,
                    }
                elseif tkop.kind == "string" or tkop.kind == "{" then
                    local prev_i = i

                    local args = new_node(ps, i, "expression_list")
                    local argument: Node
                    if tkop.kind == "string" then
                        argument = new_node(ps, i, "string")
                        argument.conststr, argument.is_longstring = unquote(tkop.tk)
                        i = i + 1
                    else
                        i, argument = parse_table_literal(ps, i)
                    end

                    if not after_valid_prefixexp(ps, e1, prev_i) then
                        return fail(
                            ps,
                            prev_i,
                            tkop.kind == "string"
                                and "cannot use a string here; if you're trying to call the previous expression, wrap it in parentheses" or "cannot use a table here; if you're trying to call the previous expression, wrap it in parentheses"
                        )
                    end

                    table.insert(args, argument)
                    e1 = {
                        f = ps.filename,
                        y = e1.y,
                        x = e1.x,
                        kind = "call",
                        e1 = e1,
                        e2 = args,
                        is_macro_invocation = is_macro_invocation,
                        tok_first = e1.tok_first,
                        tok_last = i - 1,
                    }
                elseif tkop.tk == "as" or tkop.tk == "is" then
                    local cast_i = i
                    i = i + 1
                    local casttype: Type
                    if ps.tokens[i].tk == "(" then
                        i, casttype = parse_type_list(ps, i, "casttype")
                    else
                        i, casttype = parse_type(ps, i)
                    end
                    if not casttype then
                        return fail(ps, i, "expected a type")
                    end
                    e1 = {
                        f = ps.filename,
                        y = e1.y,
                        x = e1.x,
                        kind = "cast",
                        is_assertion = tkop.tk == "is",
                        op_y = tkop.y,
                        e1 = e1,
                        casttype = casttype,
                        yend = ps.tokens[i - 1].y,
                        tok_first = e1.tok_first,
                        tok_last = i - 1,
                        tok_op = cast_i,
                    }
                else
                    break
                end
            end

            return i, e1
        end

        E = function(
            ps: ParseState, i: integer, lhs: Node, min_precedence: integer
        ): integer, Node
            local lookahead = ps.tokens[i].tk
            while
                precedences[2][lookahead]
                and precedences[2][lookahead] >= min_precedence
            do
                local t1 = ps.tokens[i]
                local op: Operator = new_operator(t1, 2, t1.tk)
                local op_i = i
                i = i + 1
                local rhs: Node
                i, rhs = P(ps, i)
                if not rhs then
                    fail(ps, i, "expected an expression")
                    return i
                end
                lookahead = ps.tokens[i].tk
                while
                    precedences[2][lookahead]
                    and (
                        (precedences[2][lookahead] > (precedences[2][op.op]))
                        or (
                            is_right_assoc[lookahead]
                            and (precedences[2][lookahead] == precedences[2][op.op])
                        )
                    )
                do
                    i, rhs = E(ps, i, rhs, precedences[2][lookahead])
                    if not rhs then
                        fail(ps, i, "expected an expression")
                        return i
                    end
                    lookahead = ps.tokens[i].tk
                end
                lhs = {
                    f = ps.filename,
                    y = t1.y,
                    x = t1.x,
                    kind = "op",
                    op = op,
                    e1 = lhs,
                    e2 = rhs,
                    yend = rhs.yend or rhs.y,
                    tok_first = lhs.tok_first,
                    tok_last = rhs.tok_last or rhs.tok_first,
                    tok_op = op_i,
                }
            end
            return i, lhs
        end

        parse_expression = function(ps: ParseState, i: integer): integer, Node, integer
            local lhs: Node
            local istart = i
            i, lhs = P(ps, i)
            if lhs then
                i, lhs = E(ps, i, lhs, 0)
            end
            if lhs then
                return i, lhs, 0
            end
            if i == istart then
                i = fail(ps, i, "expected an expression")
            end
            return i
        end
    end

    parse_expression_and_tk = function(
        ps: ParseState, i: integer, tk: string
    ): integer, Node
        local e: Node
        i, e = parse_expression(ps, i)
        if not e then
            return fail(ps, i, "syntax error, expected an expression")
        end
        if ps.tokens[i].tk ~= tk then
            return fail(ps, i, "syntax error, expected '" .. tk .. "'")
        end
        return i + 1, e
    end

    local function parse_variable_name(
        ps: ParseState, i: integer
    ): integer, Node, integer
        local node: Node
        i, node = verify_kind(ps, i, "identifier", "name")
        if not node then
            return i
        end
        if ps.tokens[i].tk == "<" then
            i = i + 1
            local annotation: Node
            i, annotation = verify_kind(ps, i, "identifier", "name")
            if annotation then
                node.attribute = annotation.tk
            else
                fail(ps, i, "expected a variable annotation")
            end
            i = verify_tk(ps, i, ">")
        end
        -- Span the variable over its name (and any `<attribute>`) so the renderer
        -- can read same-line trivia that follows it before the next separator or
        -- `=`.
        end_at(node, ps, i - 1)
        return i, node
    end

    -- One parameter routine for both function definitions and function types.
    -- The forms are the union of what each used to accept; a bare argument is
    -- always a type (`tk` left unset), so a definition's untyped `function(a)`
    -- carries `a` as a nominal type that renders straight back to `a`.
    local function parse_argument(ps: ParseState, i: integer): integer, Node, integer
        local node = new_node(ps, i, "argument")
        node.tk = nil

        if ps.tokens[i].tk == "..." then
            node.is_va = true
            i = i + 1
            if ps.tokens[i].tk == ":" then
                i = i + 1
                i, node.argtype = parse_type(ps, i)
            end
        elseif
            ps.tokens[i].kind == "identifier"
            and (ps.tokens[i + 1].tk == "?" or ps.tokens[i + 1].tk == ":")
        then
            node.tk = ps.tokens[i].tk
            i = i + 1
            if ps.tokens[i].tk == "?" then
                node.opt = true
                i = i + 1
            end
            if ps.tokens[i].tk == ":" then
                i = i + 1
                i, node.argtype = parse_type(ps, i)
            end
        else
            if ps.tokens[i].tk == "?" then
                node.opt = true
                i = i + 1
            end
            i, node.argtype = parse_type(ps, i)
        end

        -- A `...` trailing the type makes it variadic (`T...`, `a: T...`).
        if not node.is_va and ps.tokens[i].tk == "..." then
            node.is_va = true
            i = i + 1
        end

        -- Span the argument over its `?` and type so the renderer can read a
        -- comment that follows it before the separator.
        end_at(node, ps, i - 1)
        return i, node, 0
    end

    parse_argument_list = function(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "argument_list")
        local open_paren_i = i
        i, node = parse_bracket_list(ps, i, node, "(", ")", "sep", parse_argument)
        set_slot_tok(node, "after_opener", open_paren_i)
        return i, node
    end

    local function parse_identifier(ps: ParseState, i: integer): integer, Node, integer
        if ps.tokens[i].kind == "identifier" then
            return i + 1, new_node(ps, i, "name")
        end
        return fail(ps, i, "syntax error, expected identifier")
    end

    local function parse_local_function(ps: ParseState, i: integer): integer, Node
        i = verify_tk(ps, i, "local")
        i = verify_tk(ps, i, "function")
        local node = new_node(ps, i - 2, "function_declaration")
        node.is_local = true
        i, node.name = parse_identifier(ps, i)
        return parse_function_args_rets_body(ps, i, node)
    end

    local function parse_local_macro(ps: ParseState, i: integer): integer, Node
        i = verify_tk(ps, i, "local")
        i = verify_tk(ps, i, "macro")
        local node = new_node(ps, i - 2, "local_macro")
        i, node.name = parse_identifier(ps, i)
        i = verify_tk(ps, i, "!")
        i, node = parse_function_args_rets_body(ps, i, node)
        if node.name ~= nil and node.args ~= nil then
            ps.macro_params[node.name.tk] = node.args
        end
        return i, node
    end

    local function parse_function(
        ps: ParseState, i: integer, fk: FunctionKind
    ): integer, Node
        local orig_i = i
        i = verify_tk(ps, i, "function")
        local fn = new_node(ps, i - 1, "function_declaration")
        local names: {Node} = {}
        i, names[1] = parse_identifier(ps, i)
        while ps.tokens[i].tk == "." do
            i = i + 1
            i, names[#names + 1] = parse_identifier(ps, i)
        end
        if ps.tokens[i].tk == ":" then
            names[#names].tok_bound = i
            i = i + 1
            i, names[#names + 1] = parse_identifier(ps, i)
            fn.is_method = true
        end

        if #names > 1 then
            local owner = names[1]
            owner.kind = "name"
            for i2 = 2, #names - 1 do
                names[i2].kind = "name"
                owner = {
                    f = ps.filename,
                    y = names[i2].y,
                    x = names[i2].x,
                    kind = "field",
                    e1 = owner,
                    e2 = names[i2],
                    tok_first = owner.tok_first,
                    tok_last = names[i2].tok_first,
                }
            end
            fn.fn_owner = owner
        end
        fn.name = names[#names]

        i = parse_function_args_rets_body(ps, i, fn)

        if not fn.name then
            return orig_i + 1
        end

        if fn.fn_owner ~= nil and fk == "global" then
            fail(ps, orig_i, "record functions cannot be annotated as 'global'")
        elseif fn.fn_owner == nil and fk == "record" then
            fn.implicit_global_function = true
        end

        return i, fn
    end

    local function parse_if_block(
        ps: ParseState, i: integer, node: Node, is_else?: boolean
    ): integer, Node
        local block = new_node(ps, i, "if_block")
        i = i + 1
        if not is_else then
            set_slot_tok(block, "after_opener", i - 1)
            i, block.exp = parse_expression_and_tk(ps, i, "then")
            if not block.exp then
                return i
            end
        end
        set_slot_tok(block, "head", i - 1)
        i, block.body = parse_statements(ps, i)
        if not block.body then
            return i
        end
        block.yend = block.body.yend
        block.tok_last = block.body.tok_last
        table.insert(node.if_blocks, block)
        return i, node
    end

    local function parse_if(ps: ParseState, i: integer): integer, Node
        local istart = i
        local node = new_node(ps, i, "if")
        node.if_blocks = {}
        i, node = parse_if_block(ps, i, node)
        if not node then
            return i
        end
        while ps.tokens[i].tk == "elseif" do
            i, node = parse_if_block(ps, i, node)
            if not node then
                return i
            end
        end
        if ps.tokens[i].tk == "else" then
            i, node = parse_if_block(ps, i, node, true)
            if not node then
                return i
            end
        end
        return close_stmt(ps, i, istart, node)
    end

    local function parse_while(ps: ParseState, i: integer): integer, Node
        local istart = i
        local node = new_node(ps, i, "while")
        i = verify_tk_into(ps, i, "while", node, "after_opener")
        i, node.exp = parse_expression_and_tk(ps, i, "do")
        set_slot_tok(node, "head", i - 1)
        i, node.body = parse_statements(ps, i)
        return close_stmt(ps, i, istart, node)
    end

    local function parse_fornum(ps: ParseState, i: integer): integer, Node
        local istart = i
        local node = new_node(ps, i, "fornum")
        i = i + 1
        i, node.var = parse_identifier(ps, i)
        node.var.tok_bound = i
        i = verify_tk_into(ps, i, "=", node, "after_opener")
        i, node.from = parse_expression_and_tk(ps, i, ",")
        node.from.tok_sep = i - 1
        i, node.to = parse_expression(ps, i)
        if ps.tokens[i].tk == "," then
            node.to.tok_sep = i
            i = i + 1
            i, node.step = parse_expression_and_tk(ps, i, "do")
        else
            i = verify_tk(ps, i, "do")
        end
        set_slot_tok(node, "head", i - 1)
        i, node.body = parse_statements(ps, i)
        return close_stmt(ps, i, istart, node)
    end

    local function parse_forin(ps: ParseState, i: integer): integer, Node
        local istart = i
        local node = new_node(ps, i, "forin")
        i = i + 1
        node.vars = new_node(ps, i, "variable_list")
        i, node.vars = parse_list(
            ps, i, node.vars, {["in"] = true}, "sep", parse_identifier
        )
        i = verify_tk_into(ps, i, "in", node, "after_opener")
        node.exps = new_node(ps, i, "expression_list")
        i = parse_list(ps, i, node.exps, {["do"] = true}, "sep", parse_expression)
        if #node.exps < 1 then
            return fail(ps, i, "missing iterator expression in generic for")
        elseif #node.exps > 3 then
            return fail(ps, i, "too many expressions in generic for")
        end
        i = verify_tk_into(ps, i, "do", node, "head")
        i, node.body = parse_statements(ps, i)
        return close_stmt(ps, i, istart, node)
    end

    local function parse_for(ps: ParseState, i: integer): integer, Node
        if ps.tokens[i + 1].kind == "identifier" and ps.tokens[i + 2].tk == "=" then
            return parse_fornum(ps, i)
        else
            return parse_forin(ps, i)
        end
    end

    local function parse_repeat(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "repeat")
        i = verify_tk_into(ps, i, "repeat", node, "head")
        i, node.body = parse_statements(ps, i)
        i = verify_tk_into(ps, i, "until", node, "after_opener")
        i, node.exp = parse_expression(ps, i)
        end_at(node, ps, i - 1)
        return i, node
    end

    local function parse_do(ps: ParseState, i: integer): integer, Node
        local istart = i
        local node = new_node(ps, i, "do")
        i = verify_tk(ps, i, "do")
        i, node.body = parse_statements(ps, i)
        return close_stmt(ps, i, istart, node)
    end

    local function parse_break(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "break")
        i = verify_tk(ps, i, "break")
        return i, node
    end

    local function parse_goto(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "goto")
        i = verify_tk(ps, i, "goto")
        node.label = ps.tokens[i].tk
        i = verify_kind(ps, i, "identifier", "name")
        return i, node
    end

    local function parse_label(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "label")
        i = verify_tk(ps, i, "::")
        node.label = ps.tokens[i].tk
        i = verify_kind(ps, i, "identifier", "name")
        i = verify_tk(ps, i, "::")
        return i, node
    end

    local stop_statement_list: {string: boolean} = {
        ["end"] = true,
        ["else"] = true,
        ["elseif"] = true,
        ["until"] = true,
    }

    local stop_return_list: {string: boolean} = {
        [";"] = true,
        ["$EOF$"] = true,
    }

    for k, v in pairs(stop_statement_list) do
        stop_return_list[k] = v
    end

    local function parse_return(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "return")
        i = verify_tk_into(ps, i, "return", node, "after_opener")
        node.exps = new_node(ps, i, "expression_list")
        i = parse_list(ps, i, node.exps, stop_return_list, "sep", parse_expression)
        if ps.tokens[i].kind == ";" then
            -- The statement's source extent still reaches the deleted `;` (an
            -- fmt:off region anchored only by that line must freeze this
            -- statement), so its line is kept as the node's yend.
            node.yend = ps.tokens[i].y
            remove_statement_semi(ps, i)
            if
                ps.tokens[i].kind ~= "$EOF$"
                and not stop_statement_list[ps.tokens[i].tk]
            then
                return fail(ps, i, "return must be the last statement of its block")
            end
        end
        return i, node
    end

    local function store_field_in_record(
        ps: ParseState,
        field_name: string,
        newt: Type,
        def: RecordLikeType,
        node: Node,
        start_i: integer,
        end_i: integer,
        meta?: string
    )
        local entry_line = node ~= nil and node.y or newt.y
        local entry = FieldEntry.new(field_name, newt, node, meta ~= nil, entry_line)
        entry.yend = ps.tokens[end_i - 1].y
        -- Span the entry from its first token (the field name / `type` keyword),
        -- where its leading comments sit, not from the type that follows the `:`.
        entry.tok_first = start_i
        entry.tok_last = end_i - 1
        table.insert(def.field_entries, entry)

        if meta and def.meta_fields[field_name] == nil then
            def.meta_fields[field_name] = newt
        end
    end

    -- Takes the interface that owns the field, so each narrowed branch below
    -- passes a type that declares `declname` instead of asserting it does.
    local function claim_declname(named: HasDeclName, declname: string)
        if not named.declname then
            named.declname = declname
        end
    end

    local function set_declname(def: Type, declname: string)
        if def is GenericType then
            def = def.t
        end

        if def is RecordLikeType then
            claim_declname(def, declname)
        elseif def is EnumType then
            claim_declname(def, declname)
        end
    end

    local function parse_nested_type(
        ps: ParseState, i: integer, def: RecordLikeType, tn: BodyTypeName
    ): integer, boolean
        local istart = i
        i = i + 1

        local v: Node
        i, v = verify_kind(ps, i, "identifier", "name")
        if not v then
            return fail(ps, i, "expected a variable name")
        end

        local nt: Node = new_node(ps, istart, "newtype")

        local ndef: Type
        i, ndef = parse_type_body(ps, i, istart, nt, tn)
        if not ndef then
            return i
        end

        set_declname(ndef, v.tk)

        nt.def = ndef

        store_field_in_record(ps, v.tk, ndef, def, nt, istart, i)
        return i
    end

    parse_enum_body = function(
        ps: ParseState, i: integer, def: EnumType
    ): integer, boolean
        def.enum_items = {}
        while ps.tokens[i].tk ~= "$EOF$" and ps.tokens[i].tk ~= "end" do
            local item: Node
            i, item = verify_kind(ps, i, "string", "string")
            if item then
                item.yend = token_yend(ps.tokens[i - 1])
                item.tok_last = i - 1
                table.insert(def.enum_items, item)
            end
        end
        return i, true
    end

    local metamethod_names: {string: boolean} = {
        ["__add"] = true,
        ["__sub"] = true,
        ["__mul"] = true,
        ["__div"] = true,
        ["__mod"] = true,
        ["__pow"] = true,
        ["__unm"] = true,
        ["__idiv"] = true,
        ["__band"] = true,
        ["__bor"] = true,
        ["__bxor"] = true,
        ["__bnot"] = true,
        ["__shl"] = true,
        ["__shr"] = true,
        ["__concat"] = true,
        ["__len"] = true,
        ["__eq"] = true,
        ["__lt"] = true,
        ["__le"] = true,
        ["__index"] = true,
        ["__newindex"] = true,
        ["__call"] = true,
        ["__tostring"] = true,
        ["__pairs"] = true,
        ["__gc"] = true,
        ["__close"] = true,
        ["__is"] = true,
    }

    local function parse_macroexp(
        ps: ParseState, istart: integer, iargs: integer
    ): integer, Node
        local node = new_node(ps, istart, "macroexp")

        local i: integer
        if ps.tokens[istart + 1].tk == "<" then
            i, node.typeargs = parse_anglebracket_list(ps, istart + 1, parse_typearg)
        else
            i = iargs
        end

        i, node.args = parse_argument_list(ps, i)
        i, node.rets = parse_return_types(ps, i, node.args)
        i = verify_tk(ps, i, "return")
        i, node.exp = parse_expression(ps, i)
        end_at(node, ps, i)
        i = verify_end(ps, i, istart, node)
        return i, node
    end

    local function parse_where_clause(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "macroexp")

        node.is_method = true
        node.args = new_node(ps, i, "argument_list")
        node.args[1] = new_node(ps, i, "argument")
        node.args[1].tk = "self"
        node.args[1].argtype = new_type(ps, i, "self")
        node.rets = new_tuple(ps, i)
        node.rets.tuple[1] = new_type(ps, i, "boolean")
        i, node.exp = parse_expression(ps, i)
        end_at(node, ps, i - 1)
        return i, node
    end

    parse_interface_name = function(ps: ParseState, i: integer): integer, Type, integer
        local istart = i
        local typ: Type
        i, typ = parse_simple_type_or_nominal(ps, i)
        if not typ then
            return i
        end
        if not (typ is NominalType) then
            return fail(ps, istart, "expected an interface")
        end
        -- Stamp the end token so the renderer can resolve a comment after an
        -- interface name (before its `,` or the body) to it.
        typ.tok_last = i - 1
        return i, typ
    end

    local function parse_array_interface_type(
        ps: ParseState, i: integer, def: RecordLikeType
    ): integer, ArrayType
        local first = def.interface_list[1]
        if first and first is ArrayType then
            return fail(ps, i, "duplicated declaration of array element type")
        end
        local t: Type
        i, t = parse_base_type(ps, i)
        if not t then
            return i
        end
        if not (t is ArrayType) then
            fail(ps, i, "expected an array declaration")
            return i
        end
        def.elements = t.elements
        return i, t
    end

    parse_record_body = function(
        ps: ParseState, i: integer, def: RecordLikeType
    ): integer, boolean
        def.field_entries = {}
        def.interface_list = {}

        if ps.tokens[i].tk == "{" then
            local atype: Type
            i, atype = parse_array_interface_type(ps, i, def)
            if atype then
                def.interface_list = {atype}
            end
        end

        if ps.tokens[i].tk == "is" then
            i = i + 1

            if ps.tokens[i].tk == "{" then
                local atype: Type
                i, atype = parse_array_interface_type(ps, i, def)
                if ps.tokens[i].tk == "," then
                    if atype then
                        atype.tok_sep = i
                    end
                    i = i + 1
                    i, def.interface_list = parse_trying_list(
                        ps, i, {}, parse_interface_name
                    )
                else
                    def.interface_list = {}
                end
                if atype then
                    table.insert(def.interface_list, 1, atype)
                end
            else
                i, def.interface_list = parse_trying_list(
                    ps, i, {}, parse_interface_name
                )
            end
        end

        if ps.tokens[i].tk == "where" then
            local wstart = i
            i = i + 1
            local where_macroexp: Node
            i, where_macroexp = parse_where_clause(ps, i)

            local typ = new_type(ps, wstart, "function") as FunctionType
            typ.is_method = true
            typ.args = where_macroexp.args
            typ.rets = new_tuple(ps, wstart, {new_type(ps, wstart, "boolean")})
            typ.macroexp = where_macroexp

            def.meta_fields = {}
            def.meta_fields["__is"] = typ
        end

        while not (ps.tokens[i].kind == "$EOF$" or ps.tokens[i].tk == "end") do
            local tn = ps.tokens[i].tk as BodyTypeName
            if ps.tokens[i].tk == "userdata" and ps.tokens[i + 1].tk ~= ":" then
                table.insert(def.interface_list, new_nominal(ps, i, "userdata"))
                i = i + 1
            elseif ps.tokens[i].tk == "{" then
                return fail(
                    ps,
                    i,
                    "syntax error: this syntax is no longer valid; declare array interface at the top with 'is {...}'"
                )
            elseif ps.tokens[i].tk == "type" and ps.tokens[i + 1].tk ~= ":" then
                local field_start = i
                i = i + 1

                local lt: Node
                i, lt = parse_type_declaration(ps, i, "local_type")
                if not lt then
                    return fail(ps, i, "expected a type definition")
                end

                local v = lt.var
                if not v then
                    return fail(ps, i, "expected a variable name")
                end

                local nt = lt.value
                nt.typeargs = lt.typeargs
                nt.is_type_declaration = lt.is_type_declaration
                if not nt or not nt.def then
                    return fail(ps, i, "expected a type definition")
                end

                -- parse_type_declaration spans this newtype over its value; as a
                -- record field it starts at the field's `type` keyword, like
                -- parse_nested_type.
                nt.tok_first = field_start
                store_field_in_record(ps, v.tk, nt.def, def, nt, field_start, i)
            elseif type_body_keywords[tn] and ps.tokens[i + 1].tk ~= ":" then
                if def.typename == "interface" and tn == "record" then
                    i = fail(ps, i, "interfaces cannot contain record definitions")
                else
                    i = parse_nested_type(ps, i, def, tn)
                end
            else
                local field_start = i
                local is_metamethod = false
                if ps.tokens[i].tk == "metamethod" and ps.tokens[i + 1].tk ~= ":" then
                    is_metamethod = true
                    i = i + 1
                end

                local v: Node
                local is_string_key = false
                if ps.tokens[i].tk == "[" then
                    is_string_key = true
                    i, v = parse_literal(ps, i + 1)
                    if v and not v.conststr then
                        return fail(ps, i, "expected a string literal")
                    end
                    i = verify_tk(ps, i, "]")
                else
                    i, v = verify_kind(ps, i, "identifier", "name")
                end
                if not v then
                    return fail(ps, i, "expected a variable name")
                end

                if ps.tokens[i].tk == ":" then
                    i = i + 1
                    local t: Type
                    i, t = parse_type(ps, i)
                    if not t then
                        return fail(ps, i, "expected a type")
                    end
                    if t is FunctionType and t.maybe_method then
                        t.is_method = true
                    end

                    local field_name = v.conststr or v.tk
                    if is_metamethod then
                        if not def.meta_fields then
                            def.meta_fields = {}
                        end
                        if not metamethod_names[field_name] then
                            fail(ps, i - 1, "not a valid metamethod: " .. field_name)
                        end
                    end

                    if ps.tokens[i].tk == "=" and ps.tokens[i + 1].tk == "macroexp" then
                        local tt: Type = t is GenericType and t.t or t

                        -- The '=' bounds the field type's same-line trivia claim,
                        -- the same way it does on an assignment's last variable.
                        t.tok_bound = i

                        if tt is FunctionType then
                            local macroexp_node: Node
                            i, macroexp_node = parse_macroexp(ps, i + 1, i + 2)
                            tt.macroexp = macroexp_node
                        else
                            fail(ps, i + 1, "macroexp must have a function type")
                        end
                    end

                    store_field_in_record(
                        ps,
                        field_name,
                        t,
                        def,
                        nil,
                        field_start,
                        i,
                        is_metamethod and "meta" or nil
                    )
                    if is_string_key then
                        local last_entry = def.field_entries[#def.field_entries]
                        last_entry.is_string_key = true
                        last_entry.string_key_token = v.tk
                        last_entry.is_longstring_key = v.is_longstring
                        last_entry.line = v.y
                    end
                elseif ps.tokens[i].tk == "=" then
                    local next_word = ps.tokens[i + 1].tk
                    if next_word == "record" or next_word == "enum" then
                        return fail(
                            ps,
                            i,
                            "syntax error: this syntax is no longer valid; use '"
                                .. next_word
                                .. " "
                                .. v.tk
                                .. "'"
                        )
                    elseif next_word == "functiontype" then
                        return fail(
                            ps,
                            i,
                            "syntax error: this syntax is no longer valid; use 'type "
                                .. v.tk
                                .. " = function('..."
                        )
                    else
                        return fail(
                            ps,
                            i,
                            "syntax error: this syntax is no longer valid; use 'type "
                                .. v.tk
                                .. " = '..."
                        )
                    end
                else
                    fail(
                        ps,
                        i,
                        "syntax error: expected ':' for an attribute or '=' for a nested type"
                    )
                end
            end
        end

        return i, true
    end

    local function parse_newtype(ps: ParseState, i: integer): integer, Node
        local node: Node = new_node(ps, i, "newtype")
        local def: Type
        local tn = ps.tokens[i].tk as BodyTypeName
        local istart = i

        if type_body_keywords[tn] then
            i, def = parse_type_body(ps, i + 1, istart, node, tn)
        else
            i, def = parse_type(ps, i)
        end
        if not def then
            return fail(ps, i, "expected a type")
        end

        node.def = def

        return i, node
    end

    local function parse_assignment_expression_list(
        ps: ParseState, i: integer, asgn: Node, bound_owner: HasTokenSpan
    ): integer, Node
        -- The '=' bounds the same-line trivia claim of whichever node precedes
        -- it: the last variable, or the last annotation type when one is
        -- declared.
        bound_owner.tok_bound = i
        asgn.exps = new_node(ps, i, "expression_list")
        i = i + 1
        -- The '=' opens the RHS list's after_opener; the renderer reads a
        -- same-line comment after it there.
        set_slot_tok(asgn, "after_opener", i - 1)
        local first: Node
        i, first = parse_expression(ps, i)
        if not first then
            asgn.exps = nil
            return i
        end
        table.insert(asgn.exps, first)
        local ok: boolean
        i, ok = thread_list(ps, i, asgn.exps, parse_expression, ",")
        if not ok then
            return i
        end
        return i, asgn
    end

    local parse_call_or_assignment: function(ps: ParseState, i: integer): integer, Node
    do
        local function is_lvalue(node: Node): boolean
            return node.kind == "name" or node.kind == "index" or node.kind == "field"
        end

        local function parse_variable(
            ps: ParseState, i: integer
        ): integer, Node, integer
            local node: Node
            i, node = parse_expression(ps, i)
            if not (node and is_lvalue(node)) then
                return fail(ps, i, "expected a variable")
            end
            return i, node
        end

        -- Trial-parses so a non-variable after a comma (e.g. a call mistaken
        -- for an assignment LHS) does not commit the consumed tokens; the
        -- statement loop then resumes at the comma, like parse_trying_list.
        local function attempt_parse_variable(
            ps: ParseState, i: integer
        ): integer, Node, integer
            local node: Node
            i, node = attempt(ps, i, parse_variable)
            return i, node
        end

        parse_call_or_assignment = function(ps: ParseState, i: integer): integer, Node
            local exp: Node
            local istart = i
            i, exp = parse_expression(ps, i)
            if not exp then
                return i
            end

            if exp.kind == "call" then
                return i, exp
            end

            if not is_lvalue(exp) then
                return fail(ps, i, "syntax error")
            end

            local asgn: Node = new_node(ps, istart, "assignment")
            asgn.vars = new_node(ps, istart, "variable_list")
            asgn.vars[1] = exp
            if ps.tokens[i].tk == "," then
                i = thread_list(ps, i, asgn.vars, attempt_parse_variable, ",")
                if #asgn.vars < 2 then
                    return fail(ps, i, "syntax error")
                end
            end

            if ps.tokens[i].tk ~= "=" then
                verify_tk(ps, i, "=")
                return i
            end

            i, asgn = parse_assignment_expression_list(
                ps, i, asgn, asgn.vars[#asgn.vars]
            )
            return i, asgn
        end
    end

    local function parse_variable_declarations(
        ps: ParseState, i: integer, node_name: NodeKind
    ): integer, Node
        local asgn: Node = new_node(ps, i, node_name)

        asgn.vars = new_node(ps, i, "variable_list")
        i = parse_trying_list(ps, i, asgn.vars, parse_variable_name)
        if #asgn.vars == 0 then
            return fail(ps, i, "expected a local variable definition")
        end

        i, asgn.decltuple = parse_type_list(ps, i, "decltuple", asgn.vars[#asgn.vars])

        if ps.tokens[i].tk == "=" then
            local next_word = ps.tokens[i + 1].tk
            local tn = next_word as BodyTypeName
            if type_body_keywords[tn] then
                local scope = node_name == "local_declaration" and "local" or "global"
                return fail(
                    ps,
                    i + 1,
                    "syntax error: this syntax is no longer valid; use '"
                        .. scope
                        .. " "
                        .. next_word
                        .. " "
                        .. asgn.vars[1].tk
                        .. "'"
                )
            elseif next_word == "functiontype" then
                local scope = node_name == "local_declaration" and "local" or "global"
                return fail(
                    ps,
                    i + 1,
                    "syntax error: this syntax is no longer valid; use '"
                        .. scope
                        .. " type "
                        .. asgn.vars[1].tk
                        .. " = function('..."
                )
            end

            local bound_owner: HasTokenSpan = asgn.vars[#asgn.vars]
            if asgn.decltuple and #asgn.decltuple.tuple > 0 then
                bound_owner = asgn.decltuple.tuple[#asgn.decltuple.tuple]
            end
            i, asgn = parse_assignment_expression_list(ps, i, asgn, bound_owner)
        end
        return i, asgn
    end

    local function parse_special_type_declaration(
        ps: ParseState, i: integer, asgn: Node
    ): boolean, integer, Node
        if ps.tokens[i].tk == "require" then
            i, asgn.value = parse_expression(ps, i)
            if not asgn.value then
                return true, i
            end
            return true, i, asgn
        end
        return false, i, asgn
    end

    parse_type_declaration = function(
        ps: ParseState, i: integer, node_name: NodeKind
    ): integer, Node
        local asgn: Node = new_node(ps, i, node_name)
        local var: Node

        i, var = verify_kind(ps, i, "identifier", "name")
        if not var then
            return fail(ps, i, "expected a type name")
        end
        local typeargs: {TypeArgType}
        local itypeargs = i
        i, typeargs = parse_typeargs_if_any(ps, i)

        asgn.var = var
        asgn.is_type_declaration = true

        if node_name == "global_type" and ps.tokens[i].tk ~= "=" then
            return i, asgn
        end

        i = verify_tk(ps, i, "=")
        local istart = i

        if ps.tokens[i].kind == "identifier" then
            local is_done: boolean
            is_done, i, asgn = parse_special_type_declaration(ps, i, asgn)
            if is_done then
                return i, asgn
            end
        end

        i, asgn.value = parse_newtype(ps, i)
        if not asgn.value then
            return i
        end

        local nt = asgn.value
        if typeargs then
            local def = nt.def
            if def is GenericType then
                fail(
                    ps,
                    itypeargs,
                    "cannot declare type arguments twice in type declaration"
                )
            else
                nt.def = new_generic(ps, istart, typeargs, def)
                asgn.typeargs = typeargs
            end
        end

        set_declname(nt.def, asgn.var.tk)

        return i, asgn
    end

    local function parse_type_constructor(
        ps: ParseState, i: integer, node_name: NodeKind, tn: BodyTypeName
    ): integer, Node
        local asgn: Node = new_node(ps, i, node_name)
        local nt: Node = new_node(ps, i, "newtype")
        asgn.value = nt
        asgn.is_type_declaration = false
        local istart = i
        local def: Type

        -- `local record Foo` and `global record Foo` put two tokens before the name;
        -- the bare `record Foo` that only a macro argument may hold puts one.
        i = i + (node_name == "bare_type" and 1 or 2)

        i, asgn.var = verify_kind(ps, i, "identifier", "name")
        if not asgn.var then
            return fail(ps, i, "expected a type name")
        end

        i, def = parse_type_body(ps, i, istart, nt, tn)
        if not def then
            return i
        end

        set_declname(def, asgn.var.tk)

        nt.def = def

        return i, asgn
    end

    local function at_bare_type(ps: ParseState, i: integer): boolean
        return ps.allow_bare_type
            and type_body_keywords[ps.tokens[i].tk as BodyTypeName] ~= nil
            and ps.tokens[i + 1].kind == "identifier"
    end

    local function parse_bare_type(ps: ParseState, i: integer): integer, Node
        local tn = ps.tokens[i].tk as BodyTypeName
        return parse_type_constructor(ps, i, "bare_type", tn)
    end

    local function parse_local_macroexp(ps: ParseState, i: integer): integer, Node
        local istart = i
        i = i + 2
        local node = new_node(ps, i, "local_macroexp")
        i, node.name = parse_identifier(ps, i)
        i, node.macrodef = parse_macroexp(ps, istart, i)
        end_at(node, ps, i - 1)
        return i, node
    end

    local function parse_local(ps: ParseState, i: integer): integer, Node
        local keyword = ps.tokens[i]
        local keyword_i = i
        local ntk = ps.tokens[i + 1].tk
        local tn = ntk as TypeName

        local node: Node
        if ntk == "function" then
            i, node = parse_local_function(ps, i)
        elseif ntk == "type" and ps.tokens[i + 2].kind == "identifier" then
            i, node = parse_type_declaration(ps, i + 2, "local_type")
        elseif ntk == "macro" and ps.tokens[i + 2].kind == "identifier" then
            i, node = parse_local_macro(ps, i)
        elseif ntk == "macroexp" and ps.tokens[i + 2].kind == "identifier" then
            i, node = parse_local_macroexp(ps, i)
        elseif
            type_body_keywords[tn as BodyTypeName]
            and ps.tokens[i + 2].kind == "identifier"
        then
            i, node = parse_type_constructor(ps, i, "local_type", tn as BodyTypeName)
        else
            i, node = parse_variable_declarations(ps, i + 1, "local_declaration")
        end
        if node then
            -- Anchor the statement at the `local` keyword, not the declared
            -- name, so source positions are consistent across declaration
            -- kinds. The name stays available on node.var / node.vars.
            node.y, node.x = keyword.y, keyword.x
            node.tok_first = keyword_i
        end
        return i, node
    end

    local function parse_global(ps: ParseState, i: integer): integer, Node
        local keyword = ps.tokens[i]
        local keyword_i = i
        local ntk = ps.tokens[i + 1].tk
        local tn = ntk as TypeName

        local node: Node
        if ntk == "function" then
            i, node = parse_function(ps, i + 1, "global")
        elseif ntk == "type" and ps.tokens[i + 2].kind == "identifier" then
            i, node = parse_type_declaration(ps, i + 2, "global_type")
        elseif
            type_body_keywords[tn as BodyTypeName]
            and ps.tokens[i + 2].kind == "identifier"
        then
            i, node = parse_type_constructor(ps, i, "global_type", tn as BodyTypeName)
        elseif ps.tokens[i + 1].kind == "identifier" then
            i, node = parse_variable_declarations(ps, i + 1, "global_declaration")
        else
            return parse_call_or_assignment(ps, i)
        end
        if node then
            -- Anchor the statement at the `global` keyword, not the declared
            -- name, so source positions are consistent across declaration
            -- kinds. The name stays available on node.var / node.vars.
            node.y, node.x = keyword.y, keyword.x
            node.tok_first = keyword_i
        end
        return i, node
    end

    local function parse_record_function(ps: ParseState, i: integer): integer, Node
        local node: Node
        i, node = parse_function(ps, i, "record")
        return i, node
    end

    -- The node spans from the `--#pragma` token itself: stamping tok_first at
    -- the name token instead would put the pragma's leading comments outside
    -- its span, where no leading read or sweep can reach them.
    local function parse_pragma(ps: ParseState, i: integer): integer, Node
        local pragma = new_node(ps, i, "pragma")
        i = i + 1

        if ps.tokens[i].kind ~= "pragma_identifier" then
            return fail(ps, i, "expected pragma name")
        end
        pragma.pkey = ps.tokens[i].tk
        i = i + 1

        if ps.tokens[i].kind ~= "pragma_identifier" then
            return fail(ps, i, "expected pragma value")
        end
        pragma.pvalue = ps.tokens[i].tk
        i = i + 1

        pragma.tok_last = i - 1
        return i, pragma
    end

    local parse_statement_fns: {string: function(
        ParseState, integer
    ): (integer, Node)} = {
        ["--#pragma"] = parse_pragma,
        ["::"] = parse_label,
        ["do"] = parse_do,
        ["if"] = parse_if,
        ["for"] = parse_for,
        ["goto"] = parse_goto,
        ["local"] = parse_local,
        ["while"] = parse_while,
        ["break"] = parse_break,
        ["global"] = parse_global,
        ["repeat"] = parse_repeat,
        ["return"] = parse_return,
        ["function"] = parse_record_function,
    }

    local function type_needs_local_or_global(ps: ParseState, i: integer): integer, Node
        local tk = ps.tokens[i].tk
        return fail(
            ps,
            i,
            ("%s needs to be declared with 'local %s' or 'global %s'"):format(
                tk, tk, tk
            )
        )
    end

    local needs_local_or_global: {string: function(
        ParseState, integer
    ): (integer, Node)} = {
        ["type"] = function(ps: ParseState, i: integer): integer, Node
            return fail(
                ps, i, "types need to be declared with 'local type' or 'global type'"
            )
        end,
        ["record"] = type_needs_local_or_global,
        ["enum"] = type_needs_local_or_global,
    }

    parse_statements = function(
        ps: ParseState, i: integer, toplevel?: boolean
    ): integer, Node
        local node = new_node(ps, i, "statements")
        local item: Node
        while true do
            while ps.tokens[i].kind == ";" do
                remove_statement_semi(ps, i)
            end

            if ps.tokens[i].kind == "$EOF$" then
                break
            end
            local token = ps.tokens[i]
            local tk = token.tk
            if (not toplevel) and stop_statement_list[tk] then
                break
            end

            local fn = parse_statement_fns[tk]
            if not fn then
                local skip_fn = needs_local_or_global[tk]
                if at_bare_type(ps, i) then
                    fn = parse_bare_type
                elseif skip_fn and ps.tokens[i + 1].kind == "identifier" then
                    fn = skip_fn
                else
                    fn = parse_call_or_assignment
                end
            end

            i, item = fn(ps, i)

            if item then
                -- Set yend from last consumed token. For block stmts (function, if, etc.)
                -- this matches what end_at already wrote; for simple stmts it was nil.
                -- A return that consumed a `;` on a later line already carries that
                -- line (the token is deleted), so only ever extend.
                local consumed_yend = token_yend(ps.tokens[i - 1])
                if item.yend == nil or item.yend < consumed_yend then
                    item.yend = consumed_yend
                end
                item.tok_last = i - 1
                table.insert(node, item)
            elseif i > 1 then
                local lasty = ps.tokens[i - 1].y
                while ps.tokens[i].kind ~= "$EOF$" and ps.tokens[i].y == lasty do
                    i = i + 1
                end
            end
        end

        end_at(node, ps, i)
        -- `end_at` set the closing keyword's line; record its start column too, so a
        -- frozen run sharing that line can stop before the closer. EOF (the top-level
        -- block) is not a closer, so close_x stays nil there.
        if stop_statement_list[ps.tokens[i].tk] then
            node.close_x = ps.tokens[i].x
        end
        return i, node
    end

    local function parse_program(tokens: {Token}, errs: {Error}, filename: string): Node
        local ps: ParseState = {
            tokens = tokens,
            errs = errs,
            filename = filename,
            macro_params = {},
            allow_bare_type = false,
        }
        local i = 1
        local hashbang: string
        if ps.tokens[i].kind == "hashbang" then
            hashbang = ps.tokens[i].tk
            i = i + 1
        end
        local _, node = parse_statements(ps, i, true)
        if hashbang then
            node.hashbang = hashbang
        end

        return node
    end

    local SEPARATOR_TK: {string: boolean} = {
        [","] = true, [";"] = true, ["|"] = true, ["="] = true, [":"] = true
    }

    -- Verification of the single-grammar-authority guarantee (strict mode only,
    -- never routing): on a committed parse, every surviving list separator must
    -- be owned by a node stamp (statement `;`s were already deleted from the
    -- array at consumption), and every `=`/`:` directly following some node's
    -- last token -- the only positions a trailing read can observe -- must be
    -- owned by a tok_bound, slot_tok, or tok_op stamp. The walk is reflective
    -- (every table reachable from the root) so stamps on nodes, types, and
    -- field entries are all found without maintaining a field list.
    parser.check_separator_ownership = function(
        root: ast.Node, tokens: {Token}
    ): {string}
        local owned: {integer: boolean} = {}
        local claim_ends: {integer: boolean} = {}
        local seen: {any: boolean} = {}

        local function mark(value: any)
            if type(value) == "number" then
                owned[value as integer] = true
            end
        end

        local function visit(value: any)
            if type(value) ~= "table" or seen[value] then
                return
            end
            seen[value] = true
            local fields = value as {any: any}
            mark(fields["tok_sep"])
            mark(fields["tok_bound"])
            mark(fields["tok_op"])
            local slots = fields["slot_tok"]
            if type(slots) == "table" then
                for _, slot_index in pairs(slots as {any: any}) do
                    mark(slot_index)
                end
            end
            local tok_last = fields["tok_last"]
            if type(tok_last) == "number" then
                claim_ends[tok_last as integer] = true
            end
            for _, child in pairs(fields) do
                visit(child)
            end
        end

        visit(root)
        local violations: {string} = {}
        for index, token in ipairs(tokens) do
            local tk = token.tk
            if
                SEPARATOR_TK[tk]
                and token.kind ~= "string"
                and not owned[index]
                and ((tk ~= "=" and tk ~= ":") or claim_ends[index - 1])
            then
                table.insert(
                    violations,
                    string.format("unowned '%s' at %d:%d", tk, token.y, token.x)
                )
            end
        end
        return violations
    end

    -- Lexes and parses `input`, returning the AST, the accumulated lex+parse
    -- errors, and the token array the parse consumed. The parse mutates that
    -- array -- statement `;` tokens are deleted (their comments moved to the
    -- next token) and `>>` closer tokens are rewritten to `>` -- so the caller
    -- builds any further view (token_stream.from_tokens) from the returned
    -- array, and node token indices address it directly. The grammar leaves
    -- every comment on its token; the renderer reads them off the stream built
    -- from these tokens at its emit points (see token_stream + RenderContext),
    -- keyed by the ownership indices the parser stamps.
    parser.parse = function(input: string, filename: string): Node, {Error}, {Token}
        -- tl.lex loses a trailing comment when the file has no final newline
        local lex_input = input:sub(-1) == "\n" and input or input .. "\n"
        local tokens, errs = tl.lex(lex_input, filename)
        local ok, node = pcall(parse_program, tokens, errs, filename)
        if not ok then
            if node ~= parse_abort then
                error(node)
            end
            return nil, errs, tokens
        end
        return node, errs, tokens
    end
end

return parser
