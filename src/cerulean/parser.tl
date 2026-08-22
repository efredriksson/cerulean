-- Adapted from tl.tl (the teal-language/tl project), version 0.24.8.
-- Original work Copyright 2019 Hisham Muhammad, MIT License (see LICENSES/MIT-teal.txt).
-- Modifications Copyright (c) 2026 Emil Fredriksson, MIT License (see LICENSE).
-- This copy should be simplified and specialized over time.
local ast = require("cerulean.ast")
local fmt_logger = require("cerulean.fmt_logger")
local tl = require("tl")

local type Error = tl.Error
local type Token = tl.Token

local record parser
    type Error = tl.Error

    parse: function(input: string, filename: string): ast.Node, {Error}, integer
end

-- ── Local aliases for the ast data contract ─────────────────────────────────

local type Node = ast.Node

local type NodeKind = ast.NodeKind
local type Where = ast.Where
local type TypeName = ast.TypeName
local type Type = ast.Type
local type GenericType = ast.GenericType
local type TupleType = ast.TupleType
local type TypeArgType = ast.TypeArgType
local type NominalType = ast.NominalType
local type FunctionType = ast.FunctionType
local type ArrayType = ast.ArrayType
local type RecordLikeType = ast.RecordLikeType
local type NilType = ast.NilType
local type UnionType = ast.UnionType
local type TupleTableType = ast.TupleTableType
local type MapType = ast.MapType
local type EnumType = ast.EnumType
local type SelfType = ast.SelfType
local type TokenKind = tl.TokenKind
local type Comment = ast.Comment
local type InlineSlot = ast.InlineSlot
local type Operator = ast.Operator
local type HasInlineTrivia = ast.HasInlineTrivia
local type FieldEntry = ast.FieldEntry

local function set_inline_trivia(
    node: HasInlineTrivia, slot: InlineSlot, trivia: {Comment}
)
    if trivia == nil or #trivia == 0 then
        return
    end
    node.inline_trivia = node.inline_trivia or {}
    node.inline_trivia[slot] = trivia
end

-- ── pre-parser functions ─────────────────────────────────────────────────────
local type_mt: metatable<Type> = {
    __tostring = function(_t: Type): string return "?" end,
}

local function a_type<T is Type>(w: Where, typename: TypeName, t: T): T
    t.f = w.f
    t.x = w.x
    t.y = w.y
    t.typename = typename
    do
        local ty: Type = t
        setmetatable(ty, type_mt)
    end
    return t
end

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

-- Implements HasInlineTrivia so thread_list can route comments around an
-- argument whose type is still unparsed; the trivia is transferred onto the
-- argument's type once the tuple is built.
local record ArgumentInfo is ast.HasInlineTrivia
    i: integer
    type: Type
    name: string
    is_va: boolean
    is_self: boolean
    opt: boolean
end

local parse_type_list: function(
    ParseState, integer, ParseTypeListMode
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
local parse_argument_type_list: function(
    ParseState, integer
): integer, TupleType, boolean

local parse_type: function(ParseState, integer): integer, Type, integer
local parse_type_declaration: function(
    ps: ParseState, i: integer, node_name: NodeKind
): integer, Node

local parse_interface_name: function(ps: ParseState, i: integer): integer, Type, integer

local type ParseBody = function(ps: ParseState, i: integer, def: Type): integer, boolean
local parse_enum_body: function(
    ps: ParseState, i: integer, def: EnumType
): integer, boolean

local parse_record_body: function(
    ps: ParseState, i: integer, def: RecordLikeType
): integer, boolean

local parse_type_body_fns: {BodyTypeName: ParseBody}

do
    -- Raised by fail and caught at trial-parse boundaries (skip, attempt) and
    -- in parser.parse; identity comparison keeps genuine runtime errors
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

    local function new_node(ps: ParseState, i: integer, kind?: NodeKind): Node
        local t = ps.tokens[i]
        return setmetatable(
            {
                f = ps.filename,
                y = t.y,
                x = t.x,
                tk = t.tk,
                kind = kind or (t.kind as NodeKind),
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

    local function new_body_type(ps: ParseState, i: integer, tn: BodyTypeName): Type
        return new_type(ps, i, tn as TypeName)
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
        ps: ParseState, i: integer, kind: TokenKind, node_kind?: NodeKind
    ): integer, Node
        if ps.tokens[i].kind == kind then
            return i + 1, new_node(ps, i, node_kind)
        end
        return fail(ps, i, "syntax error, expected " .. kind)
    end

    local type SkipFunction = function(ParseState, integer): integer, Node | boolean

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

    -- Pure lookahead for grammar disambiguation: trial-runs skip_fn on a
    -- throwaway state so neither recorded errors nor a parse abort escape.
    -- Reports the trial as not-parsing instead.
    local function skip(
        ps: ParseState, i: integer, skip_fn: SkipFunction
    ): integer, Node | boolean
        local trial_ps = fork(ps)
        local skip_i: integer
        local skipped: Node | boolean
        local function run_trial(): any
            skip_i, skipped = skip_fn(trial_ps, i)
            return nil
        end
        local ok, raised = pcall(run_trial)
        if not ok then
            if raised ~= parse_abort then
                error(raised)
            end
            return i, nil
        end
        return skip_i, skipped
    end

    local function parse_type_body(
        ps: ParseState, i: integer, istart: integer, node: Node, tn: BodyTypeName
    ): integer, Type
        local typeargs: {TypeArgType}
        local def: Type
        i, typeargs = parse_typeargs_if_any(ps, i)

        def = new_body_type(ps, istart, tn)

        local ok: boolean
        i, ok = parse_type_body_fns[tn](ps, i, def)
        if not ok then
            return fail(ps, i, "expected a type")
        end

        i = verify_end(ps, i, istart, node)

        if typeargs then
            return i, new_generic(ps, istart, typeargs, def)
        end

        return i, def
    end

    local function skip_type_body(ps: ParseState, i: integer): integer, boolean
        local tn = ps.tokens[i].tk as BodyTypeName
        i = i + 1
        assert(parse_type_body_fns[tn], tn .. " has no parse body function")
        local ii, tt = parse_type_body(ps, i, i - 1, {} as Node, tn)
        return ii, not not tt
    end

    local function parse_table_value(ps: ParseState, i: integer): integer, Node, integer
        local next_word = ps.tokens[i].tk
        if next_word == "record" or next_word == "interface" then
            local _, e = skip(ps, i, skip_type_body as SkipFunction)
            if e then
                return fail(
                    ps,
                    i,
                    next_word == "record"
                        and "syntax error: this syntax is no longer valid; declare nested record inside a record" or "syntax error: cannot declare interface inside a table; use a statement"
                )
            end
        elseif next_word == "enum" and ps.tokens[i + 1].kind == "string" then
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

    local get_attached_comments: function(
        token: Token, previous_token?: Token
    ): {Comment}
    local take_same_line_comments: function(token: Token, line: integer): {Comment}
    local take_all_token_comments: function(token: Token): {Comment}
    local partition_separator_trivia: function(
        sep_token: Token, next_token?: Token, item_line: integer
    ): {Comment}, {Comment}

    local function token_yend(tk: Token): integer
        if tk.kind == "string" or tk.kind == "`" then
            local _, line_breaks = tk.tk:gsub("\n", "\n")
            return tk.y + line_breaks
        end
        return tk.y
    end

    local function parse_table_item(
        ps: ParseState, i: integer, n?: integer
    ): integer, Node, integer
        local node = new_node(ps, i, "literal_table_item")
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        if comments then
            node.leading_comments = comments
        end
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
                i = verify_tk(ps, i, "=")
                set_inline_trivia(
                    node,
                    "after_opener",
                    take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
                )
                i, node.value = parse_table_value(ps, i)
                node.yend = token_yend(ps.tokens[i - 1])
                node.tok_last = i - 1
                return i, node, n
            elseif ps.tokens[i + 1].tk == ":" then
                node.key_parsed = "short"
                local orig_i = i
                local try_ps = fork(ps)
                local trial_i: integer
                local function try_typed_key_item(): any
                    local ti = orig_i
                    ti, node.key = verify_kind(try_ps, ti, "identifier", "string")
                    node.key.conststr = node.key.tk
                    node.key.tk = '"' .. node.key.tk .. '"'
                    ti = verify_tk(try_ps, ti, ":")
                    ti, node.itemtype = parse_type(try_ps, ti)
                    if node.itemtype and try_ps.tokens[ti].tk == "=" then
                        ti = verify_tk(try_ps, ti, "=")
                        ti, node.value = parse_table_value(try_ps, ti)
                        if node.value then
                            trial_i = ti
                        end
                    end
                    return nil
                end
                local ok, raised = pcall(try_typed_key_item)
                if not ok and raised ~= parse_abort then
                    error(raised)
                end
                if trial_i then
                    i = trial_i
                    node.yend = token_yend(ps.tokens[i - 1])
                    node.tok_last = i - 1
                    return i, node, n
                end
                -- backtrack: not a `key: type = value` item after all
                node.itemtype = nil
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

    local type ParseItem = function<T>(
        ParseState, integer, ?integer
    ): integer, T, integer

    local function is_block_comment(comment: Comment): boolean
        return comment.text:match("^%-%-%[=*%[") ~= nil
    end

    local function all_block_comments(comments: {Comment}): boolean
        for _, comment in ipairs(comments) do
            if not is_block_comment(comment) then
                return false
            end
        end
        return true
    end

    local function append_trailing_comments(node: Node, comments: {Comment})
        if #comments == 0 then
            return
        end
        if node.trailing_comments == nil then
            node.trailing_comments = comments
        else
            for _, comment in ipairs(comments) do
                table.insert(node.trailing_comments, comment)
            end
        end
    end

    local function parse_list<T is Node>(
        ps: ParseState,
        i: integer,
        list: {T},
        close: {string: boolean},
        sep: SeparatorMode,
        parse_item: ParseItem<T>
    ): integer, {T}
        local n = 1
        local pending_leading: {Comment} = {}
        while ps.tokens[i].kind ~= "$EOF$" do
            if close[ps.tokens[i].tk] then
                end_at(list as Node, ps, i)
                break
            end
            local item: T
            local oldn = n
            i, item, n = parse_item(ps, i, n)
            n = n or oldn
            if item then
                if #pending_leading > 0 then
                    set_inline_trivia(item, "leading", pending_leading)
                    pending_leading = {}
                end
                -- Comments rendered "after this item":
                --   `x --[[c]],`  → drained from the separator token
                --   `x, -- c`     → line comment / no next item: trailing here
                -- A same-line block-comment run after the separator that has a
                -- real next item to receive it instead becomes that item's
                -- `leading` (renders flush, never forces a wrap). Only drain on a
                -- separator; a closing bracket's comments belong to the
                -- bracket-list's end_comments, not to this item.
                local is_separator = ps.tokens[i].tk == "," or ps.tokens[i].tk == ";"
                local item_line = item.yend or item.y
                local sep_trailing: {Comment} = {}
                if is_separator then
                    local before_sep: {Comment}
                    sep_trailing, before_sep = partition_separator_trivia(
                        ps.tokens[i], ps.tokens[i + 1], item_line
                    )
                    set_inline_trivia(item, "before_separator", before_sep)
                end
                local comment_token = (is_separator and ps.tokens[i + 1])
                    or ps.tokens[i]
                local next_same_line = take_same_line_comments(comment_token, item_line)
                local next_token = ps.tokens[i + 1]
                local has_next_item = is_separator
                    and next_token.kind ~= "$EOF$"
                    and not close[next_token.tk]
                if
                    has_next_item
                    and #sep_trailing == 0
                    and #next_same_line > 0
                    and all_block_comments(next_same_line)
                then
                    pending_leading = next_same_line
                elseif #sep_trailing == 0 then
                    item.trailing_comments = next_same_line
                else
                    item.trailing_comments = sep_trailing
                    for _, c in ipairs(next_same_line) do
                        table.insert(item.trailing_comments, c)
                    end
                end
            end
            table.insert(list, item)
            if ps.tokens[i].tk == "," then
                i = i + 1
                if sep == "sep" and close[ps.tokens[i].tk] then
                    fail(ps, i, "unexpected '" .. ps.tokens[i].tk .. "'")
                    return i, list
                end
            elseif sep == "term" and ps.tokens[i].tk == ";" then
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
        i = parse_list(ps, i, list, {[close] = true}, sep, parse_item)
        i = verify_tk(ps, i, close)
        return i, list
    end

    local function parse_table_literal(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "literal_table")
        node.leading_comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        i, node = parse_bracket_list(ps, i, node, "{", "}", "term", parse_table_item)
        node.dangling_comments = get_attached_comments(
            ps.tokens[i - 1], ps.tokens[i - 2]
        )
        node.trailing_comma = #node > 0
            and (ps.tokens[i - 2].tk == "," or ps.tokens[i - 2].tk == ";")
        local items = node
        local previous_end: integer | nil = nil
        for _, item in ipairs(items) do
            local leading = item.leading_comments or {}
            if #leading > 0 then
                previous_end = leading[#leading].yend
            end
            if previous_end ~= nil then
                item.blank_line_before = item.y > previous_end + 1
            end
            previous_end = item.yend
        end
        return i, node
    end

    -- Trial-parses one item on a throwaway state so a "is there even an item
    -- here?" probe never leaks errors or a parse abort. On success returns the
    -- advanced index + item; on failure returns the original index and nil.
    local function attempt<T>(
        ps: ParseState, i: integer, parse_item: ParseItem<T>
    ): integer, T
        local try_ps = fork(ps)
        local tryi: integer
        local item: T
        local function run_trial(): any
            tryi, item = parse_item(try_ps, i)
            return nil
        end
        local ok, raised = pcall(run_trial)
        if not ok then
            if raised ~= parse_abort then
                error(raised)
            end
            return i
        end
        if not item then
            return i
        end
        return tryi, item
    end

    -- Captures the inline comments around the separator at `i` for `current` (the
    -- element just parsed) and returns the same-line block run that should become
    -- the *next* element's `leading`. The one place Node and Type lists diverge:
    -- a Node can render own-line / line comments, so it routes them to
    -- `trailing_comments` (which force a wrap) via partition; a Type only ever
    -- carries same-line block comments, so it takes them verbatim.
    local function thread_separator<T is HasInlineTrivia>(
        ps: ParseState, i: integer, current: T
    ): {Comment}
        local item_line = ps.tokens[i - 1].y
        if current is Node then
            local sep_trailing, before_sep = partition_separator_trivia(
                ps.tokens[i], ps.tokens[i + 1], item_line
            )
            set_inline_trivia(current, "before_separator", before_sep)
            -- A same-line block-comment run after the separator (with a real next
            -- element to receive it) becomes that element's `leading`; a line
            -- comment stays trailing here and forces the wrap it requires.
            local next_same_line = take_same_line_comments(ps.tokens[i + 1], item_line)
            if
                #sep_trailing == 0
                and #next_same_line > 0
                and all_block_comments(next_same_line)
                and ps.tokens[i + 1].kind ~= "$EOF$"
            then
                return next_same_line
            end
            append_trailing_comments(current, sep_trailing)
            append_trailing_comments(current, next_same_line)
            return {}
        end
        set_inline_trivia(
            current,
            "before_separator",
            take_same_line_comments(ps.tokens[i], item_line)
        )
        return take_same_line_comments(ps.tokens[i + 1], ps.tokens[i].y)
    end

    -- Threads inline comments through the `sep`-separated tail of a list whose
    -- first element is already in `list`. Each element gets `before_separator`
    -- (before the upcoming `sep`) and the next gets `leading` (after it), routed
    -- per element kind by thread_separator. `i` points at the first separator or
    -- the closer. `ret_lookahead` stops at a `,` that opens a named return tuple
    -- (`function(): (a, b: T)`). One walker for both node and type lists.
    -- The second return is false when a separator was consumed but the item
    -- after it failed to parse; parse_item does not always record an error
    -- (parse_expression fails silently), so callers that must reject the
    -- construct check this instead.
    local function thread_list<T is HasInlineTrivia>(
        ps: ParseState,
        i: integer,
        list: {T},
        parse_item: ParseItem<T>,
        sep: string,
        ret_lookahead?: boolean
    ): integer, boolean
        local pending_leading: {Comment} = {}
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
            pending_leading = thread_separator(ps, i, list[#list])
            i = i + 1
            local item: T
            i, item = parse_item(ps, i)
            if not item then
                local last = list[#list]
                if #pending_leading > 0 and last is Node then
                    append_trailing_comments(last, pending_leading)
                end
                return i, false
            end
            if #pending_leading > 0 then
                set_inline_trivia(item, "leading", pending_leading)
            end
            pending_leading = {}
            table.insert(list, item)
        end
        return i, true
    end

    -- Optional list: trial-parses the first element (so an absent list is not a
    -- hard error), then threads the comma tail. Serves both node lists
    -- (assignment / declaration variables) and type lists (interface lists).
    local function parse_trying_list<T is HasInlineTrivia>(
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

    -- Sets `before_separator` on the last element of a list from the same-line
    -- comments sitting before the closer at `i`.
    local function set_last_before_separator<T is HasInlineTrivia>(
        ps: ParseState, i: integer, list: {T}
    )
        if #list > 0 then
            set_inline_trivia(
                list[#list],
                "before_separator",
                take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
            )
        end
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

        local angle_line = ps.tokens[i].y
        i = verify_tk(ps, i, "<")
        local types: {T} = {}
        local leading = take_same_line_comments(ps.tokens[i], angle_line)
        local first: T
        i, first = parse_item(ps, i)
        if first then
            set_inline_trivia(first, "leading", leading)
            table.insert(types, first)
            i = thread_list(ps, i, types, parse_item, ",")
        end
        set_last_before_separator(ps, i, types)
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

    local function parse_return_types(ps: ParseState, i: integer): integer, TupleType
        local iprev = i - 1
        local t: TupleType
        i, t = parse_type_list(ps, i, "rets")
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
            i, typ.args, typ.maybe_method = parse_argument_type_list(ps, i)
            i, typ.rets = parse_return_types(ps, i)
        else
            typ.bare = true
            typ.args = new_tuple(ps, i, {new_type(ps, i, "any")}, true)
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

    local function parse_base_type(ps: ParseState, i: integer): integer, Type, integer
        local tk = ps.tokens[i].tk
        if ps.tokens[i].kind == "identifier" then
            return parse_simple_type_or_nominal(ps, i)
        elseif tk == "{" then
            local istart = i
            local brace_line = ps.tokens[i].y
            i = i + 1
            local leading = take_same_line_comments(ps.tokens[i], brace_line)
            local t: Type
            i, t = parse_type(ps, i)
            if not t then
                return i
            end
            set_inline_trivia(t, "leading", leading)
            if ps.tokens[i].tk == "}" then
                local decl = new_type(ps, istart, "array") as ArrayType
                set_inline_trivia(
                    t,
                    "before_separator",
                    take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
                )
                decl.elements = t
                end_at(decl as Node, ps, i)
                i = verify_tk(ps, i, "}")
                return i, decl
            elseif ps.tokens[i].tk == "," then
                local decl = new_type(ps, istart, "tupletable") as TupleTableType
                decl.types = {t}
                i = thread_list(ps, i, decl.types, parse_type, ",")
                set_last_before_separator(ps, i, decl.types)
                end_at(decl as Node, ps, i)
                i = verify_tk(ps, i, "}")
                return i, decl
            elseif ps.tokens[i].tk == ":" then
                local decl = new_type(ps, istart, "map") as MapType
                decl.keys = t
                set_inline_trivia(
                    t,
                    "before_separator",
                    take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
                )
                i = i + 1
                local value_leading = take_same_line_comments(
                    ps.tokens[i], ps.tokens[i - 1].y
                )
                i, decl.values = parse_type(ps, i)
                if not decl.values then
                    return i
                end
                set_inline_trivia(decl.values, "leading", value_leading)
                set_inline_trivia(
                    decl.values,
                    "before_separator",
                    take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
                )
                end_at(decl as Node, ps, i)
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

    parse_type = function(ps: ParseState, i: integer): integer, Type, integer
        if ps.tokens[i].tk == "(" then
            i = i + 1
            local t: Type
            i, t = parse_type(ps, i)
            i = verify_tk(ps, i, ")")
            if t then
                t.paren = true
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
        return i, bt
    end

    parse_type_list = function(
        ps: ParseState, i: integer, mode: ParseTypeListMode
    ): integer, TupleType
        local t, list = new_tuple(ps, i)

        local first_token = ps.tokens[i].tk
        -- Comments after the leading ':' and/or an optional '(' become the
        -- first element's `leading`, or the container's `after_opener` if empty.
        local first_leading: {Comment} = {}
        if mode == "rets" or mode == "decltuple" then
            if first_token == ":" then
                local colon_line = ps.tokens[i].y
                i = i + 1
                first_leading = take_same_line_comments(ps.tokens[i], colon_line)
            else
                return i, t
            end
        end

        local optional_paren = false
        if ps.tokens[i].tk == "(" then
            optional_paren = true
            local paren_line = ps.tokens[i].y
            i = i + 1
            for _, comment in ipairs(
                take_same_line_comments(ps.tokens[i], paren_line)
            ) do
                table.insert(first_leading, comment)
            end
        end

        -- Trial-parse the first type so an empty list (legal after ':' or '(')
        -- is not reported as a hard error.
        local first_type: Type
        i, first_type = attempt(ps, i, parse_type)
        if not first_type then
            if ps.tokens[i].tk ~= ")" then
                fail(ps, i - 1, "expected a type list")
            end
            -- No element to carry the post-'(' comments (e.g. `as(--[[c]])`).
            set_inline_trivia(t, "after_opener", first_leading)
        else
            set_inline_trivia(first_type, "leading", first_leading)
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
            set_last_before_separator(ps, i, list)
            i = verify_tk(ps, i, ")")
            t.paren = true
        end

        return i, t
    end

    local function parse_function_args_rets_body(
        ps: ParseState, i: integer, node: Node
    ): integer, Node
        local istart = i - 1
        i, node.typeargs = parse_typeargs_if_any(ps, i)
        i, node.args = parse_argument_list(ps, i)
        i, node.rets = parse_return_types(ps, i)
        set_inline_trivia(
            node, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
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
        elseif kind == "number" or kind == "integer" then
            return verify_kind(ps, i, kind)
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
            return verify_kind(ps, i, "...")
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

        -- Parsing drains comments off the token objects, which the slice shares with
        -- the file, so an attempt that turns out not to apply has to put them back.
        local function snapshot_comments(tokens: {Token}): {Token: {tl.LexerComment}}
            local saved: {Token: {tl.LexerComment}} = {}
            for _, token in ipairs(tokens) do
                if token.comments ~= nil then
                    local copy: {tl.LexerComment} = {}
                    for _, comment in ipairs(token.comments) do
                        table.insert(copy, comment)
                    end
                    saved[token] = copy
                end
            end
            return saved
        end

        local function restore_comments(saved: {Token: {tl.LexerComment}})
            for token, copy in pairs(saved) do
                token.comments = copy
            end
        end

        local function parse_statement_argument(
            ps: ParseState, i: integer, more_arguments_follow: boolean
        ): integer, Node
            local stop = statement_argument_end(ps, i, more_arguments_follow)
            local slice: {Token} = {}
            for k = i, stop - 1 do
                slice[k - i + 1] = ps.tokens[k]
            end
            local last = ps.tokens[math.max(i, stop - 1)]
            slice[#slice + 1] = {y = last.y, x = last.x, tk = "$EOF$", kind = "$EOF$"}

            local slice_ps = fork(ps)
            slice_ps.tokens = slice
            slice_ps.allow_bare_type = true

            local saved = snapshot_comments(slice)
            local node: Node
            local function run_slice(): any
                local _, parsed = parse_statements(slice_ps, 1, true)
                node = parsed
                return nil
            end
            local ok, raised = pcall(run_slice)
            if not ok and raised ~= parse_abort then
                error(raised)
            end
            if ok and node ~= nil then
                return stop, node
            end

            -- Teal rejects a `Statement` parameter handed anything else, but a
            -- formatter still has to produce something.
            restore_comments(saved)
            local next_i, exp = parse_expression(ps, i)
            return next_i, exp
        end

        -- A trailing `...` governs every argument from its own position on. Past a
        -- fixed list there is no parameter, which is also how the caller asks
        -- whether another argument is still expected.
        local function macro_param(params: Node, n: integer): Node
            local last = params[#params]
            if n > #params and last ~= nil and last.tk == "..." then
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
                local op_trailing_trivia = take_all_token_comments(ps.tokens[i])
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
                }
                set_inline_trivia(e1, "op_trailing", op_trailing_trivia)
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

                    local op_leading_trivia = take_all_token_comments(tkop)
                    local key: Node
                    i = i + 1
                    local op_trailing_trivia = take_all_token_comments(ps.tokens[i])
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
                    }
                    set_inline_trivia(e1, "op_leading", op_leading_trivia)
                    set_inline_trivia(e1, "op_trailing", op_trailing_trivia)
                    fmt_logger.debug(
                        "[expr] %s node: base y=%s op_tk=%s op_y=%s -> node y=%s",
                        e1.kind,
                        e1.e1.y,
                        tkop.tk,
                        tkop.y,
                        e1.y
                    )
                elseif tkop.tk == "(" then
                    local prev_tk = ps.tokens[i - 1]
                    if tkop.y > prev_tk.y then
                        table.insert(
                            ps.tokens,
                            i,
                            {
                                y = prev_tk.y,
                                x = prev_tk.x + #prev_tk.tk,
                                tk = ";",
                                kind = ";",
                            } as Token
                        )
                        break
                    end

                    local prev_i = i

                    local args = new_node(ps, i, "expression_list")
                    local open_paren_leading_trivia = take_same_line_comments(
                        ps.tokens[i + 1], ps.tokens[i].y
                    )
                    local parse_arg: ParseItem<Node> = parse_expression
                    if macro_params then
                        parse_arg = macro_arg_parser(macro_params)
                    end
                    i, args = parse_bracket_list(
                        ps, i, args, "(", ")", "sep", parse_arg
                    )
                    set_inline_trivia(args, "after_opener", open_paren_leading_trivia)
                    args.dangling_comments = get_attached_comments(
                        ps.tokens[i - 1], ps.tokens[i - 2]
                    )

                    local function leftmost_y(node: Node): integer
                        if node.kind == "op" and node.e1 then
                            return leftmost_y(node.e1)
                        end
                        return node.y
                    end

                    local previous_end: integer | nil = nil
                    for _, arg_node in ipairs(args) do
                        local leading = arg_node.leading_comments or {}
                        if #leading > 0 then
                            previous_end = leading[#leading].yend
                        end
                        if previous_end ~= nil then
                            local left_y = leftmost_y(arg_node)
                            arg_node.blank_line_before = left_y > previous_end + 1
                            fmt_logger.debug(
                                "[call args] blank_line_before=%s kind=%s y=%s leftmost_y=%s previous_end=%s",
                                arg_node.blank_line_before,
                                arg_node.kind,
                                arg_node.y,
                                left_y,
                                previous_end
                            )
                        end
                        previous_end = arg_node.yend or arg_node.y
                    end

                    -- Capture a comment that immediately follows the closing ')' on the
                    -- same line, but only for multi-line calls where ')' is on its own
                    -- line. For single-line calls like `f() -- note` the comment belongs
                    -- to the surrounding statement and is extracted there instead.
                    local close_paren_line = ps.tokens[i - 1].y
                    if close_paren_line > args.y then
                        args.trailing_comments = take_same_line_comments(
                            ps.tokens[i], close_paren_line
                        )
                    end

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
                    fmt_logger.debug(
                        "[expr] @funcall op node: base y=%s args_y=%s -> node y=%s",
                        e1.e1.y,
                        args.y,
                        e1.y
                    )
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
                        argument = new_node(ps, i)
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
                    local op_leading_trivia = take_all_token_comments(tkop)

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
                    }
                    set_inline_trivia(e1, "op_leading", op_leading_trivia)
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
                local op_leading_trivia = take_all_token_comments(ps.tokens[i])
                local op: Operator = new_operator(t1, 2, t1.tk)
                i = i + 1
                local op_trailing_trivia = take_all_token_comments(ps.tokens[i])
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
                }
                set_inline_trivia(lhs, "op_leading", op_leading_trivia)
                set_inline_trivia(lhs, "op_trailing", op_trailing_trivia)
            end
            return i, lhs
        end

        parse_expression = function(ps: ParseState, i: integer): integer, Node, integer
            local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
            local lhs: Node
            local istart = i
            i, lhs = P(ps, i)
            if lhs then
                i, lhs = E(ps, i, lhs, 0)
            end
            if lhs then
                if comments then
                    lhs.leading_comments = comments
                end
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
        return i, node
    end

    local function parse_argument(ps: ParseState, i: integer): integer, Node, integer
        local node: Node
        if ps.tokens[i].tk == "..." then
            i, node = verify_kind(ps, i, "...", "argument")
            node.opt = true
        else
            i, node = verify_kind(ps, i, "identifier", "argument")
        end
        if ps.tokens[i].tk == "..." then
            fail(ps, i, "'...' needs to be declared as a typed argument")
        end
        if ps.tokens[i].tk == "?" then
            i = i + 1
            if node then
                node.opt = true
            end
        end
        if ps.tokens[i].tk == ":" then
            i = i + 1
            local argtype: Type

            i, argtype = parse_type(ps, i)

            if node then
                node.argtype = argtype
            end
        end
        return i, node, 0
    end

    parse_argument_list = function(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "argument_list")
        local open_paren_leading_trivia = take_same_line_comments(
            ps.tokens[i + 1], ps.tokens[i].y
        )
        i, node = parse_bracket_list(ps, i, node, "(", ")", "sep", parse_argument)
        set_inline_trivia(node, "after_opener", open_paren_leading_trivia)
        node.dangling_comments = get_attached_comments(
            ps.tokens[i - 1], ps.tokens[i - 2]
        )
        return i, node
    end

    local function parse_argument_type(
        ps: ParseState, i: integer
    ): integer, ArgumentInfo, integer
        local opt = 0
        local is_va = false
        local is_self = false
        local argument_name: string = nil

        if ps.tokens[i].kind == "identifier" then
            if ps.tokens[i + 1].tk == "?" then
                opt = i + 1
                if ps.tokens[i + 2].tk == ":" then
                    argument_name = ps.tokens[i].tk
                    i = i + 3
                end
            elseif ps.tokens[i + 1].tk == ":" then
                argument_name = ps.tokens[i].tk
                i = i + 2
            end
        elseif ps.tokens[i].kind == "?" then
            opt = i
            i = i + 1
        elseif ps.tokens[i].tk == "..." then
            if ps.tokens[i + 1].tk == "?" then
                fail(
                    ps,
                    i + 1,
                    "cannot mix '?' and '...' in a declaration; '...' already implies optional"
                )
                i = i + 1
            end
            if ps.tokens[i + 1].tk == ":" then
                i = i + 2
                is_va = true
            else
                return fail(
                    ps,
                    i,
                    "cannot have untyped '...' when declaring the type of an argument"
                )
            end
        end

        -- A comment between the binding ':' and the type (`a: --[[c]] int`); the
        -- list walker captures the comments around the whole argument.
        local after_colon = take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        local typ: Type
        i, typ = parse_type(ps, i)
        if typ then
            set_inline_trivia(typ, "head", after_colon)
            if not is_va and ps.tokens[i].tk == "..." then
                i = i + 1
                is_va = true
                if opt > 0 then
                    fail(
                        ps,
                        opt,
                        "cannot mix '?' and '...' in a declaration; '...' already implies optional"
                    )
                end
            end

            if argument_name == "self" then
                is_self = true
            end
        end

        return i,
            {
                i = i,
                type = typ,
                name = argument_name,
                is_va = is_va,
                is_self = is_self,
                opt = (opt > 0) or is_va,
            },
            0
    end

    parse_argument_type_list = function(
        ps: ParseState, i: integer
    ): integer, TupleType, boolean
        local ars: {ArgumentInfo} = {}
        local paren_line = ps.tokens[i].y
        i = verify_tk(ps, i, "(")
        local leading = take_same_line_comments(ps.tokens[i], paren_line)
        if ps.tokens[i].tk ~= ")" then
            local first: ArgumentInfo
            i, first = parse_argument_type(ps, i)
            if first then
                set_inline_trivia(first, "leading", leading)
                table.insert(ars, first)
                i = thread_list(ps, i, ars, parse_argument_type, ",")
            end
        end
        set_last_before_separator(ps, i, ars)
        i = verify_tk(ps, i, ")")
        local t, list = new_tuple(ps, i)
        t.argnames = {}
        t.is_optional = {}
        local n = #ars
        for l, ar in ipairs(ars) do
            list[l] = ar.type
            t.argnames[l] = ar.name
            t.is_optional[l] = ar.opt
            if ar.type then
                set_inline_trivia(ar.type, "leading", ast.inline_trivia(ar, "leading"))
                set_inline_trivia(
                    ar.type,
                    "before_separator",
                    ast.inline_trivia(ar, "before_separator")
                )
            end
            if ar.is_va and l < n then
                fail(ps, ar.i, "'...' can only be last argument")
            end
        end
        if n > 0 and ars[n].is_va then
            t.is_va = true
        end
        return i, t, (n > 0 and ars[1].is_self)
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
            set_inline_trivia(
                block,
                "after_opener",
                take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
            )
            i, block.exp = parse_expression_and_tk(ps, i, "then")
            if not block.exp then
                return i
            end
        end
        set_inline_trivia(
            block, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
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
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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
        i = verify_end(ps, i, istart, node)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_while(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local istart = i
        local node = new_node(ps, i, "while")
        i = verify_tk(ps, i, "while")
        set_inline_trivia(
            node,
            "after_opener",
            take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.exp = parse_expression_and_tk(ps, i, "do")
        set_inline_trivia(
            node, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.body = parse_statements(ps, i)
        i = verify_end(ps, i, istart, node)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_fornum(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local istart = i
        local node = new_node(ps, i, "fornum")
        i = i + 1
        i, node.var = parse_identifier(ps, i)
        i = verify_tk(ps, i, "=")
        set_inline_trivia(
            node,
            "after_opener",
            take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.from = parse_expression_and_tk(ps, i, ",")
        i, node.to = parse_expression(ps, i)
        if ps.tokens[i].tk == "," then
            i = i + 1
            i, node.step = parse_expression_and_tk(ps, i, "do")
        else
            i = verify_tk(ps, i, "do")
        end
        set_inline_trivia(
            node, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.body = parse_statements(ps, i)
        i = verify_end(ps, i, istart, node)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_forin(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local istart = i
        local node = new_node(ps, i, "forin")
        i = i + 1
        node.vars = new_node(ps, i, "variable_list")
        i, node.vars = parse_list(
            ps, i, node.vars, {["in"] = true}, "sep", parse_identifier
        )
        i = verify_tk(ps, i, "in")
        set_inline_trivia(
            node,
            "after_opener",
            take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        node.exps = new_node(ps, i, "expression_list")
        i = parse_list(ps, i, node.exps, {["do"] = true}, "sep", parse_expression)
        if #node.exps < 1 then
            return fail(ps, i, "missing iterator expression in generic for")
        elseif #node.exps > 3 then
            return fail(ps, i, "too many expressions in generic for")
        end
        i = verify_tk(ps, i, "do")
        set_inline_trivia(
            node, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.body = parse_statements(ps, i)
        i = verify_end(ps, i, istart, node)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_for(ps: ParseState, i: integer): integer, Node
        if ps.tokens[i + 1].kind == "identifier" and ps.tokens[i + 2].tk == "=" then
            return parse_fornum(ps, i)
        else
            return parse_forin(ps, i)
        end
    end

    local function parse_repeat(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local node = new_node(ps, i, "repeat")
        i = verify_tk(ps, i, "repeat")
        set_inline_trivia(
            node, "head", take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.body = parse_statements(ps, i)
        i = verify_tk(ps, i, "until")
        set_inline_trivia(
            node,
            "after_opener",
            take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        i, node.exp = parse_expression(ps, i)
        end_at(node, ps, i - 1)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_do(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local istart = i
        local node = new_node(ps, i, "do")
        i = verify_tk(ps, i, "do")
        i, node.body = parse_statements(ps, i)
        i = verify_end(ps, i, istart, node)
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_break(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local node = new_node(ps, i, "break")
        i = verify_tk(ps, i, "break")
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_goto(ps: ParseState, i: integer): integer, Node
        local node = new_node(ps, i, "goto")
        i = verify_tk(ps, i, "goto")
        node.trailing_comments = take_same_line_comments(
            ps.tokens[i], ps.tokens[i - 1].y
        )
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
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local node = new_node(ps, i, "return")
        i = verify_tk(ps, i, "return")
        set_inline_trivia(
            node,
            "after_opener",
            take_same_line_comments(ps.tokens[i], ps.tokens[i - 1].y)
        )
        node.exps = new_node(ps, i, "expression_list")
        i = parse_list(ps, i, node.exps, stop_return_list, "sep", parse_expression)
        if ps.tokens[i].kind == ";" then
            i = i + 1
            if
                ps.tokens[i].kind ~= "$EOF$"
                and not stop_statement_list[ps.tokens[i].tk]
            then
                return fail(ps, i, "return must be the last statement of its block")
            end
        end
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function store_field_in_record(
        ps: ParseState,
        field_name: string,
        newt: Type,
        def: RecordLikeType,
        node: Node,
        end_i: integer,
        comments?: {Comment},
        meta?: string
    )
        local entry_line = node ~= nil and node.y or newt.y
        local entry = FieldEntry.new(
            field_name, newt, node, comments or {}, meta ~= nil, entry_line
        )
        entry.yend = ps.tokens[end_i - 1].y
        entry.tok_first = node ~= nil and node.tok_first or newt.tok_first
        entry.tok_last = end_i - 1
        entry.trailing_comments = take_same_line_comments(ps.tokens[end_i], entry.yend)
        table.insert(def.field_entries, entry)

        if meta and def.meta_fields[field_name] == nil then
            def.meta_fields[field_name] = newt
        end
    end

    local function set_declname(def: Type, declname: string)
        if def is GenericType then
            def = def.t
        end

        if def is ast.RecordType or def is ast.InterfaceType or def is EnumType then
            if not (def as ast.HasDeclName).declname then
                (def as ast.HasDeclName).declname = declname
            end
        end
    end

    local function comment_len(comment: tl.LexerComment): integer
        local _, comment_line_breaks = comment.text:gsub("\n", "\n")
        return comment_line_breaks + 1
    end

    local function make_comment(lc: tl.LexerComment): Comment
        return {
            x = lc.x,
            y = lc.y,
            text = lc.text,
            blank_line_before = false,
            yend = lc.y + comment_len(lc) - 1,
        }
    end

    -- Prepends `incoming` to the front of token.comments, preserving their
    -- relative order. Used when a token is dropped (e.g. a skipped `;`) and its
    -- leading comments must move onto the following token so they survive.
    local function prepend_token_comments(token: Token, incoming: {tl.LexerComment})
        if #incoming == 0 then
            return
        end
        local existing = token.comments
        if existing == nil or #existing == 0 then
            token.comments = incoming
        else
            for j = #incoming, 1, -1 do
                table.insert(existing, 1, incoming[j])
            end
        end
    end

    get_attached_comments = function(token: Token, previous_token?: Token): {Comment}
        local token_comments = token.comments
        if token_comments == nil or #token_comments == 0 then
            return nil
        end

        local last_lc = token_comments[#token_comments]

        local diff_y = token.y - last_lc.y
        if diff_y < 0 then
            return nil
        end

        local attached_comments: {Comment} = {}
        for j = 1, #token_comments do
            table.insert(attached_comments, make_comment(token_comments[j]))
        end

        for i = 2, #attached_comments do
            if attached_comments[i].y - attached_comments[i - 1].yend > 1 then
                attached_comments[i].blank_line_before = true
            end
        end

        if
            not (previous_token is nil)
            and attached_comments[1].y > previous_token.y + 1
        then
            attached_comments[1].blank_line_before = true
        end

        return attached_comments
    end

    -- Drains every comment on the given line from token.comments. Use after
    -- a block-opening keyword so trailing inline trivia does not leak into
    -- the first body statement's leading comments.
    take_same_line_comments = function(token: Token, line: integer): {Comment}
        -- Lookahead such as tokens[i + 1] can land one past $EOF$.
        if token == nil then
            return {}
        end
        local lc_list = token.comments
        if lc_list == nil or #lc_list == 0 then
            return {}
        end
        local result: {Comment} = {}
        local i = 1
        while i <= #lc_list do
            if lc_list[i].y == line then
                table.insert(result, make_comment(lc_list[i]))
                table.remove(lc_list, i)
            else
                i = i + 1
            end
        end
        return result
    end

    -- Drains the comments attached to a token that sits AFTER an item
    -- (typically a separator like `,`, `;`, or `=`) and routes each one
    -- to the trivia slot whose renderer can handle it:
    --
    --   * a line comment (`-- ...`) on the item's line goes into the
    --     item's trailing_comments — the comment ends the source line,
    --     so the separator must follow on the next line, which the
    --     trailing_comments renderer already arranges;
    --   * a line comment on a later line is relocated onto next_token's
    --     comment list, where parse_item's get_attached_comments will
    --     pick it up as a leading_comments entry for the following item
    --     (or as dangling_comments of the enclosing closer if there is
    --     no next item);
    --   * a block comment (`--[[ ... ]]`) stays in before_separator
    --     inline trivia — block comments do not terminate a source line
    --     and can sit between the item and the separator.
    --
    -- Invariant maintained: before_separator inline trivia never
    -- contains a line comment, so the renderer is free to emit the
    -- separator immediately after it.
    partition_separator_trivia = function(
        sep_token: Token, next_token: Token, item_line: integer
    ): {Comment}, {Comment}
        local lc_list = sep_token.comments
        if lc_list == nil or #lc_list == 0 then
            return {}, {}
        end
        local trailing: {Comment} = {}
        local before_sep: {Comment} = {}
        local relocated: {tl.LexerComment} = {}
        for _, lc in ipairs(lc_list) do
            if lc.text:match("^%-%-%[=*%[") then
                table.insert(before_sep, make_comment(lc))
            elseif lc.y == item_line then
                table.insert(trailing, make_comment(lc))
            else
                table.insert(relocated, lc)
            end
        end
        if next_token ~= nil then
            prepend_token_comments(next_token, relocated)
            sep_token.comments = {}
        else
            -- Leave relocated on sep_token so get_attached_comments collects
            -- them as dangling comments of the enclosing block.
            sep_token.comments = relocated
        end
        return trailing, before_sep
    end

    -- Mutates token.comments so a downstream get_attached_comments call
    -- cannot re-pick the same comment.
    take_all_token_comments = function(token: Token): {Comment}
        local lc_list = token.comments
        if lc_list == nil or #lc_list == 0 then
            return {}
        end
        local result: {Comment} = {}
        for j = 1, #lc_list do
            table.insert(result, make_comment(lc_list[j]))
        end
        for j = #lc_list, 1, -1 do
            table.remove(lc_list, j)
        end
        return result
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

        store_field_in_record(
            ps,
            v.tk,
            ndef,
            def,
            nt,
            i,
            get_attached_comments(ps.tokens[istart], ps.tokens[istart - 1])
        )
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
                item.leading_comments = get_attached_comments(
                    ps.tokens[i - 1], ps.tokens[i - 2]
                )
                item.yend = token_yend(ps.tokens[i - 1])
                item.tok_last = i - 1
                item.trailing_comments = take_same_line_comments(
                    ps.tokens[i], item.yend
                )
                table.insert(def.enum_items, item)
            end
        end

        local previous_end: integer | nil = nil
        for _, item in ipairs(def.enum_items) do
            local leading = item.leading_comments or {}
            if #leading > 0 then
                previous_end = leading[#leading].yend
            end
            if previous_end ~= nil then
                item.blank_line_before = item.y > previous_end + 1
            end
            previous_end = item.yend
        end

        def.dangling_comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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
        i, node.rets = parse_return_types(ps, i)
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
            typ.args = new_tuple(
                ps, wstart, {a_type(where_macroexp as Where, "self", {} as SelfType)}
            )
            typ.rets = new_tuple(ps, wstart, {new_type(ps, wstart, "boolean")})
            typ.macroexp = where_macroexp as Node

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
                local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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

                store_field_in_record(ps, v.tk, nt.def, def, nt, i, comments)
            elseif parse_type_body_fns[tn] and ps.tokens[i + 1].tk ~= ":" then
                if def.typename == "interface" and tn == "record" then
                    i = fail(ps, i, "interfaces cannot contain record definitions")
                else
                    i = parse_nested_type(ps, i, def, tn)
                end
            else
                local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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

                        if tt is FunctionType then
                            local macroexp_node: Node
                            i, macroexp_node = parse_macroexp(ps, i + 1, i + 2)
                            tt.macroexp = macroexp_node as Node
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
                        i,
                        comments,
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

        local previous_end: integer | nil = nil
        for _, entry in ipairs(def.field_entries) do
            local leading = entry.leading_comments or {}
            if #leading > 0 then
                previous_end = leading[#leading].yend
            end
            if previous_end ~= nil then
                entry.blank_line_before = entry.line > previous_end + 1
            end
            previous_end = entry.yend
        end

        def.dangling_comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        return i, true
    end

    parse_type_body_fns = {
        ["interface"] = parse_record_body as ParseBody,
        ["record"] = parse_record_body as ParseBody,
        ["enum"] = parse_enum_body as ParseBody,
    }

    local function parse_newtype(ps: ParseState, i: integer): integer, Node
        local node: Node = new_node(ps, i, "newtype")
        local def: Type
        local tn = ps.tokens[i].tk as BodyTypeName
        local istart = i

        if parse_type_body_fns[tn] then
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
        ps: ParseState, i: integer, asgn: Node
    ): integer, Node
        asgn.exps = new_node(ps, i, "expression_list")
        local eq_line = ps.tokens[i].y
        i = i + 1
        set_inline_trivia(
            asgn, "after_opener", take_same_line_comments(ps.tokens[i], eq_line)
        )
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
            local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
            local exp: Node
            local istart = i
            i, exp = parse_expression(ps, i)
            if not exp then
                return i
            end

            if exp.kind == "call" then
                if exp then
                    exp.leading_comments = comments
                end
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

            local last_var = asgn.vars[#asgn.vars]
            local last_var_trailing, last_var_before_sep = partition_separator_trivia(
                ps.tokens[i], ps.tokens[i + 1], last_var.yend or last_var.y
            )
            set_inline_trivia(last_var, "before_separator", last_var_before_sep)
            if #last_var_trailing > 0 then
                if last_var.trailing_comments == nil then
                    last_var.trailing_comments = last_var_trailing
                else
                    for _, c in ipairs(last_var_trailing) do
                        table.insert(last_var.trailing_comments, c)
                    end
                end
            end
            if ps.tokens[i].tk ~= "=" then
                verify_tk(ps, i, "=")
                return i
            end

            i, asgn = parse_assignment_expression_list(ps, i, asgn)
            if asgn then
                asgn.leading_comments = comments
            end
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

        local last_var = asgn.vars[#asgn.vars]
        local last_var_trailing, last_var_before_sep = partition_separator_trivia(
            ps.tokens[i], ps.tokens[i + 1], last_var.yend or last_var.y
        )
        set_inline_trivia(last_var, "before_separator", last_var_before_sep)
        if #last_var_trailing > 0 then
            if last_var.trailing_comments == nil then
                last_var.trailing_comments = last_var_trailing
            else
                for _, c in ipairs(last_var_trailing) do
                    table.insert(last_var.trailing_comments, c)
                end
            end
        end

        i, asgn.decltuple = parse_type_list(ps, i, "decltuple")

        if ps.tokens[i].tk == "=" then
            local next_word = ps.tokens[i + 1].tk
            local tn = next_word as BodyTypeName
            if parse_type_body_fns[tn] then
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

            i, asgn = parse_assignment_expression_list(ps, i, asgn)
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
            and parse_type_body_fns[ps.tokens[i].tk as BodyTypeName] ~= nil
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
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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
            parse_type_body_fns[tn as BodyTypeName]
            and ps.tokens[i + 2].kind == "identifier"
        then
            i, node = parse_type_constructor(ps, i, "local_type", tn as BodyTypeName)
            if node then
                node.dangling_comments = get_attached_comments(
                    ps.tokens[i - 1], ps.tokens[i - 2]
                )
            end
        else
            local between = take_same_line_comments(ps.tokens[i + 1], keyword.y)
            i, node = parse_variable_declarations(ps, i + 1, "local_declaration")
            if node then
                node.trailing_comments = between
            end
        end
        if node then
            -- Anchor the statement at the `local` keyword, not the declared
            -- name, so source positions are consistent across declaration
            -- kinds. The name stays available on node.var / node.vars.
            node.y, node.x = keyword.y, keyword.x
            node.tok_first = keyword_i
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_global(ps: ParseState, i: integer): integer, Node
        local keyword = ps.tokens[i]
        local keyword_i = i
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local ntk = ps.tokens[i + 1].tk
        local tn = ntk as TypeName

        local node: Node
        if ntk == "function" then
            i, node = parse_function(ps, i + 1, "global")
        elseif ntk == "type" and ps.tokens[i + 2].kind == "identifier" then
            local between = take_same_line_comments(ps.tokens[i + 1], keyword.y)
            i, node = parse_type_declaration(ps, i + 2, "global_type")
            if node then
                node.trailing_comments = between
            end
        elseif
            parse_type_body_fns[tn as BodyTypeName]
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
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_record_function(ps: ParseState, i: integer): integer, Node
        local comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
        local node: Node
        i, node = parse_function(ps, i, "record")
        if node then
            node.leading_comments = comments
        end
        return i, node
    end

    local function parse_pragma(ps: ParseState, i: integer): integer, Node
        i = i + 1
        local pragma = new_node(ps, i, "pragma")

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
        local previous_end: integer | nil = nil
        while true do
            while ps.tokens[i].kind == ";" do
                -- Add `;` leading comments to next token also
                -- as ';' is ignored when rendering.
                local semi_comments = ps.tokens[i].comments or {}
                prepend_token_comments(ps.tokens[i + 1], semi_comments)
                i = i + 1
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
                item.yend = token_yend(ps.tokens[i - 1])
                item.tok_last = i - 1
                -- Extract any same-line trailing comments (e.g. `local x = 1 -- note`).
                -- take_same_line_comments drains them from ps.tokens[i].comments so they
                -- won't be re-attached as leading comments of the next statement.
                -- If the statement parser (e.g. parse_goto) already captured inline
                -- trivia, merge rather than overwrite so neither set is lost.
                local stmt_trailing = take_same_line_comments(ps.tokens[i], item.yend)
                if item.trailing_comments and #item.trailing_comments > 0 then
                    for _, c in ipairs(stmt_trailing) do
                        table.insert(item.trailing_comments, c)
                    end
                else
                    item.trailing_comments = stmt_trailing
                end

                local leading = item.leading_comments or {}
                if #leading > 0 then
                    previous_end = leading[#leading].yend
                end
                if previous_end then
                    item.blank_line_before = item.y > previous_end + 1
                    fmt_logger.debug(
                        "[block] stmt %s at line %s: blank_line_before=%s (previous_end=%s)",
                        item.kind,
                        item.y,
                        item.blank_line_before,
                        previous_end
                    )
                end
                previous_end = item.yend
                table.insert(node, item)
            elseif i > 1 then
                local lasty = ps.tokens[i - 1].y
                while ps.tokens[i].kind ~= "$EOF$" and ps.tokens[i].y == lasty do
                    i = i + 1
                end
            end
        end

        node.dangling_comments = get_attached_comments(ps.tokens[i], ps.tokens[i - 1])
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

    parser.parse = function(input: string, filename: string): Node, {Error}, integer
        -- tl.lex loses a trailing comment when the file has no final newline
        local lex_input = input:sub(-1) == "\n" and input or input .. "\n"
        local tokens, errs = tl.lex(lex_input, filename)
        local comment_count = 0
        for _, token in ipairs(tokens) do
            comment_count = comment_count + #(token.comments or {})
        end
        local node: Node
        local function run_parse(): any
            node = parse_program(tokens, errs, filename)
            return nil
        end
        local ok, raised = pcall(run_parse)
        if not ok and raised ~= parse_abort then
            error(raised)
        end
        return node, errs, comment_count
    end
end

return parser
