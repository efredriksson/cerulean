-- The data contract between the parser and the renderers: AST nodes, the type
-- hierarchy, comments, and the token-index slots (tok_first/tok_last/slot_tok)
-- the renderer uses to read comments off the lossless token stream. Renderers
-- depend on this module only; any parser that produces ast.Node trees can drive
-- them.
local tl = require("tl")

local record ast
    enum TypeName
        "generic"
        "typearg"
        "function"
        "array"
        "map"
        "tupletable"
        "record"
        "interface"
        "self"
        "enum"
        "boolean"
        "string"
        "nil"
        "thread"
        "number"
        "integer"
        "union"
        "nominal"
        "tuple"
        "any"
        "table"
    end

    record Operator
        y: integer
        x: integer
        arity: integer
        op: string
        prec: integer
    end

    interface Where
        f: string
        y: integer
        x: integer
    end

    -- The opener token index feeding each positional slot (the `(`/`=`/`until`
    -- that introduces a value, etc.), stamped by the parser. The renderer reads
    -- the lossless token stream at that index to recover the opener's same-line
    -- trivia (RenderContext:opener_comments); index-aligned with the parser's
    -- token array, which the token stream re-lexes one-to-one.
    interface HasOpenerSlots
        slot_tok: {InlineSlot: integer}
    end

    -- Token-index span into the parser's token array, stamped by the parser. The
    -- renderer reads the token stream built from that same array (see
    -- token_stream.from_tokens), so the indices address it directly and
    -- tok_last lands exactly on a delimited construct's closing token
    -- (`end`/`until`/`else`/`elseif`/`}`/`)`), the token before which dangling
    -- comments sit.
    interface HasTokenSpan
        tok_first: integer
        tok_last: integer
        -- Separator ownership, stamped by the parser at the site that consumes
        -- the token (the full_moon Punctuated model: a separator has no role of
        -- its own, it belongs to a node). The render layer decides trivia claims
        -- from these indices and never classifies tokens itself. (Statement `;`
        -- separators need no stamp: the parser deletes them from the token
        -- array as it consumes them.)
        --   tok_sep: the list separator (`,` / table `;` / `|`) right after this
        --     item; it donates its same-line trailing trivia to the item.
        --   tok_bound: the parent construct's `=`/`:` right after this node; it
        --     ends the node's same-line trivia claim and donates nothing.
        tok_sep: integer
        tok_bound: integer
    end

    -- A child of a container that lists its items one per line (statements,
    -- table items, call arguments, enum items, record fields). It may keep a
    -- single blank line above itself; blank_lines.mark recomputes the flag from
    -- the token stream and the renderer emits it.
    interface ContainerItem
        is HasTokenSpan

        blank_line_before: boolean
    end

    interface Type is Where, HasOpenerSlots, HasTokenSpan where self.typename
        typename: TypeName    -- discriminator
        paren: boolean
    end

    record GenericType is Type where self.typename == "generic"

        typeargs: {TypeArgType}
        t: Type
    end

    interface HasDeclName
        declname: string
    end

    record NominalType
        is Type
        where self.typename == "nominal"

        names: {string}
        typevals: {Type}
    end

    interface ArrayLikeType
        is Type
        where self.elements

        elements: Type
    end

    record ArrayType
        is ArrayLikeType
        where self.typename == "array"
    end

    record Comment
        is tl.LexerComment
        yend: integer
        blank_line_before: boolean
    end

    enum InlineSlot
        "head"
        "after_opener"
    end

    record FieldEntry
        is ContainerItem
        where self.the_type ~= nil
        name: string
        the_type: Type
        node: Node
        is_meta: boolean
        is_string_key: boolean
        string_key_token: string
        is_longstring_key: boolean
        line: integer
        yend: integer
        new: function(string, Type, Node, boolean, integer): FieldEntry
    end

    interface RecordLikeType
        is HasDeclName, ArrayLikeType
        where self.field_entries

        interface_list: {ArrayType | NominalType}
        meta_fields: {string: Type}
        field_entries: {FieldEntry}
    end

    record RecordType
        is RecordLikeType
        where self.typename == "record"
    end

    record InterfaceType
        is RecordLikeType
        where self.typename == "interface"
    end

    record TupleType
        is Type
        where self.typename == "tuple"

        is_va: boolean
        tuple: {Type}
    end

    interface TypeArgType
        is Type
        where self.typename == "typearg"

        typearg: string
        constraint: Type
    end

    record MapType
        is Type
        where self.typename == "map"

        keys: Type
        values: Type
    end

    record NilType
        is Type
        where self.typename == "nil"
    end

    record FunctionType
        is Type
        where self.typename == "function"

        is_method: boolean
        maybe_method: boolean
        bare: boolean
        args: Node
        rets: TupleType
        macroexp: Node
        yend: integer
    end

    interface AggregateType
        is Type
        where self.types

        types: {Type}
    end

    record UnionType
        is AggregateType
        where self.typename == "union"
    end

    record TupleTableType
        is AggregateType
        where self.typename == "tupletable"
    end

    record EnumType
        is Type, HasDeclName
        where self.typename == "enum"

        enum_items: {Node}
    end

    enum KeyParsed
        "short"
        "long"
        "implicit"
    end

    enum NodeKind
        "op"
        "field"
        "method"
        "index"
        "call"
        "nil"
        "string"
        "number"
        "integer"
        "boolean"
        "literal_table"
        "literal_table_item"
        "function"
        "expression_list"
        "if"
        "if_block"
        "while"
        "fornum"
        "forin"
        "goto"
        "label"
        "repeat"
        "do"
        "break"
        "return"
        "newtype"
        "argument"
        "name"
        "variable_list"
        "statements"
        "assignment"
        "argument_list"
        "function_declaration"
        "local_type"
        "global_type"
        "local_declaration"
        "global_declaration"
        "cast"
        "..."
        "paren"
        "macro_quote"
        "local_macro"
        "bare_type"
        "macroexp"
        "local_macroexp"
        "interface"
        "pragma"
    end

    simple_types: {TypeName: boolean}

    record Node
        is {Node}, Where, HasOpenerSlots, ContainerItem
        where self.kind ~= nil

        -- fmt: off
        tk:                             string
        kind:                           NodeKind
        hashbang:                       string
        is_longstring:                  boolean
        yend:                           integer
        close_x:                        integer
        key:                            Node
        value:                          Node
        key_parsed:                     KeyParsed
        typeargs:                       {TypeArgType}
        args:                           Node
        rets:                           TupleType
        body:                           Node
        implicit_global_function:       boolean
        is_macro_invocation:            boolean
        name:                           Node
        attribute:                      string
        fn_owner:                       Node
        is_method:                      boolean
        is_local:                       boolean
        exp:                            Node
        if_blocks:                      {Node}
        var:                            Node
        from:                           Node
        to:                             Node
        step:                           Node
        vars:                           Node
        exps:                           Node
        def:                            Type
        op:                             Operator
        op_y:                           integer
        -- The interior token a node threads its inline op-trivia around, stamped
        -- by the parser: a binary/unary operator, a `.`/`:` member access, an
        -- `as`/`is` cast keyword, or a function definition's name separator. The
        -- op_leading/op_trailing accessors read the gap on either side of it.
        tok_op:                         integer
        e1:                             Node
        e2:                             Node
        conststr:                       string
        label:                          string
        casttype:                       Type
        is_assertion:                   boolean
        macrodef:                       Node
        argtype:                        Type
        itemtype:                       Type
        decltuple:                      TupleType
        pkey:                           string
        pvalue:                         string
        opt:                            boolean
        is_va:                          boolean
        trailing_comma:                 boolean
        is_type_declaration:            boolean
        f:                              string
        -- fmt: on
    end
end

function ast.FieldEntry.new(
    name: string, the_type: ast.Type, node: ast.Node, is_meta: boolean, line: integer
): ast.FieldEntry
    local self = setmetatable({}, {__index = ast.FieldEntry}) as ast.FieldEntry
    self.name = name
    self.the_type = the_type
    self.node = node
    self.is_meta = is_meta
    self.line = line
    return self
end

ast.simple_types = {
    ["nil"] = true,
    ["any"] = true,
    ["number"] = true,
    ["string"] = true,
    ["thread"] = true,
    ["boolean"] = true,
    ["integer"] = true,
    ["self"] = true,
    ["table"] = true,
}

return ast
