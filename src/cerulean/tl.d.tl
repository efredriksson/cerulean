local record tl
    enum WarningKind
        "unknown"
        "unused"
        "redeclaration"
        "branch"
        "hint"
        "debug"
        "unread"
    end
    record Error
        y: integer
        x: integer
        msg: string
        filename: string
        tag: WarningKind
        -- used temporarily for stable-sorting
        i: integer
    end
    enum TokenKind
        "hashbang"
        "keyword"
        "op"
        "string"
        "["
        "]"
        "("
        ")"
        "{"
        "}"
        ","
        ":"
        "."
        ";"
        "?"
        "::"
        "..."
        "identifier"
        "number"
        "integer"
        "pragma"
        "pragma_identifier"
        "$ERR$"
        "$EOF$"
    end
    interface LexerComment
        x: integer
        y: integer
        text: string
    end
    record Token
        x: integer
        y: integer
        tk: string
        kind: TokenKind
        comments: {LexerComment}
    end
    lex: function(input: string, filename: string): {Token}, {Error}
end

return tl
