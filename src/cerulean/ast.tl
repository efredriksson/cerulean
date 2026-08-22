-- The data contract between the parser and the renderers: AST nodes, the
-- type hierarchy, comments, and inline-trivia slots. Renderers depend on
-- this module only; any parser that produces ast.Node trees can drive them.
local tl = require("tl")

local record ast
    enum TypeName
        "generic"
        "typedecl"
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
        "poly"
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

    interface HasInlineTrivia
        inline_trivia: {InlineSlot: {Comment}}
    end

    interface Type is Where, HasInlineTrivia where self.typename
        typename: TypeName    -- discriminator
        paren: boolean
    end

    record GenericType is Type where self.typename == "generic"

        typeargs: {TypeArgType}
        t: FirstOrderType
    end

    interface FirstOrderType is Type
    end

    type FirstClassType = GenericType | FirstOrderType

    interface StructuralType
        is FirstOrderType
    end

    record TypeDeclType
        is Type
        where self.typename == "typedecl"

        def: FirstClassType
    end

    interface HasDeclName
        declname: string
    end

    record NominalType
        is FirstOrderType
        where self.typename == "nominal"

        names: {string}
        typevals: {FirstClassType}
    end

    record SelfType
        is FirstOrderType
        where self.typename == "self"

        -- to be used only in error reports, not for type resolution
        display_type: RecordLikeType
    end

    interface ArrayLikeType
        is StructuralType
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
        "op_leading"
        "op_trailing"
        "before_separator"
        "head"
        "after_opener"
        "leading"
    end

    record FieldEntry
        where self.the_type ~= nil
        name: string
        the_type: Type
        node: Node
        leading_comments: {Comment}
        is_meta: boolean
        is_string_key: boolean
        string_key_token: string
        is_longstring_key: boolean
        line: integer
        yend: integer
        blank_line_before: boolean
        trailing_comments: {Comment}
        new: function(string, Type, Node, {Comment}, boolean, integer): FieldEntry
    end

    interface RecordLikeType
        is StructuralType, HasDeclName, ArrayLikeType
        where self.fields

        interface_list: {ArrayType | NominalType}
        fields: {string: Type}
        meta_fields: {string: Type}
        field_entries: {FieldEntry}
        dangling_comments: {Comment}
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
        is FirstOrderType
        where self.typename == "tuple"

        is_va: boolean
        argnames: {string}
        is_optional: {boolean}
        tuple: {Type}
    end

    interface TypeArgType
        is Type
        where self.typename == "typearg"

        typearg: string
        constraint: Type
    end

    record MapType
        is StructuralType
        where self.typename == "map"

        keys: Type
        values: Type
    end

    record NilType
        is StructuralType
        where self.typename == "nil"
    end

    record FunctionType
        is StructuralType
        where self.typename == "function"

        is_method: boolean
        maybe_method: boolean
        is_record_function: boolean
        bare: boolean
        args: TupleType
        rets: TupleType
        macroexp: Node
        yend: integer
    end

    interface AggregateType
        is StructuralType
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

    -- Intersection types, currently restricted to polymorphic functions
    -- defined inside records, representing polymorphic Lua APIs.
    record PolyType
        is AggregateType
        where self.typename == "poly"

        types: {FunctionType | GenericType}
    end

    record EnumType
        is StructuralType, HasDeclName
        where self.typename == "enum"

        enum_items: {Node}
        dangling_comments: {Comment}
    end

    enum Attribute
        "const"
        "close"
        "total"
    end

    enum KeyParsed
        "short"
        "long"
        "implicit"
    end

    enum NodeKind
        "op"
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
        "type_identifier"
        "variable"
        "variable_list"
        "statements"
        "assignment"
        "argument_list"
        "local_function"
        "global_function"
        "local_type"
        "global_type"
        "record_function"
        "local_declaration"
        "global_declaration"
        "identifier"
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
        "error_node"
    end

    simple_types: {TypeName: boolean}

    record Node
        is {Node}, Where, HasInlineTrivia
        where self.kind ~= nil

        -- fmt: off
        tk:                             string
        kind:                           NodeKind
        leading_comments:               {Comment}
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
        is_repeat:                      boolean
        attribute:                      Attribute
        fn_owner:                       Node
        is_method:                      boolean
        exp:                            Node
        if_parent:                      Node
        if_block_n:                     integer
        if_blocks:                      {Node}
        var:                            Node
        from:                           Node
        to:                             Node
        step:                           Node
        vars:                           Node
        exps:                           Node
        newtype:                        TypeDeclType
        op:                             Operator
        e1:                             Node
        e2:                             Node
        conststr:                       string
        failstore:                      boolean
        label:                          string
        casttype:                       Type
        macrodef:                       Node
        expanded:                       Node
        argtype:                        Type
        itemtype:                       Type
        decltuple:                      TupleType
        pkey:                           string
        pvalue:                         string
        opt:                            boolean
        trailing_comma:                 boolean
        dangling_comments:              {Comment}
        trailing_comments:              {Comment}
        blank_line_before:              boolean
        is_self:                        boolean
        is_type_declaration:            boolean
        f:                              string
        -- fmt: on
    end

    inline_trivia: function(node: HasInlineTrivia, slot: InlineSlot): {Comment}
end

function ast.FieldEntry.new(
    name: string,
    the_type: ast.Type,
    node: ast.Node,
    comments: {ast.Comment},
    is_meta: boolean,
    line: integer
): ast.FieldEntry
    local self = setmetatable({}, {__index = ast.FieldEntry}) as ast.FieldEntry
    self.name = name
    self.the_type = the_type
    self.node = node
    self.leading_comments = comments
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

local EMPTY_INLINE_TRIVIA: {ast.Comment} = {}

-- Returns the trivia list for `slot` on `node`, or an empty list when absent.
-- Callers must treat the result as read-only — the empty case shares one constant.
function ast.inline_trivia(
    node: ast.HasInlineTrivia, slot: ast.InlineSlot
): {ast.Comment}
    if node.inline_trivia == nil then
        return EMPTY_INLINE_TRIVIA
    end
    return node.inline_trivia[slot] or EMPTY_INLINE_TRIVIA
end

return ast
