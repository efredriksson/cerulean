// Project: https://github.com/teal-language/tl
// Reference grammar: https://teal-language.org/book/latest/grammar.html

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

grammar Teal;

chunk
    : nonempty_block EOF
    ;

block
    : stat* retstat?
    ;

// The driver skips zero-byte files, so an empty top-level chunk burns a
// generation slot. Nested blocks keep `block` and may still be empty.
nonempty_block
    : stat+ retstat?
    | retstat
    ;

stat
    : ';'                                                                      # SemiStat
    | varlist '=' explist                                                      # AssignStat
    | functioncall                                                             # FuncCallStat
    | label                                                                    # LabelStat
    | 'break'                                                                  # BreakStat
    | 'goto' NAME                                                              # GotoStat
    | 'do' block 'end'                                                         # DoStat
    | 'while' exp 'do' block 'end'                                             # WhileStat
    | 'repeat' block 'until' exp                                               # RepeatStat
    | 'if' exp 'then' block ('elseif' exp 'then' block)* ('else' block)? 'end' # IfStat
    | 'for' NAME '=' exp ',' exp (',' exp)? 'do' block 'end'                   # ForStat
    | 'for' namelist 'in' explist 'do' block 'end'                             # ForInStat
    | 'function' funcname funcbody                                             # FuncStat
    | 'local' 'function' NAME funcbody                                         # LocalFuncStat
    | 'local' 'record' NAME recordbody                                         # LocalRecordStat
    | 'local' 'interface' NAME recordbody                                      # LocalInterfaceStat
    | 'local' 'enum' NAME enumbody                                             # LocalEnumStat
    | 'local' 'type' NAME '=' newtype                                          # LocalTypeStat
    | 'local' attnamelist (':' typelist)? ('=' explist)?                       # LocalAttrAssignStat
    | 'global' 'function' NAME funcbody                                        # GlobalFuncStat
    | 'global' 'record' NAME recordbody                                        # GlobalRecordStat
    | 'global' 'interface' NAME recordbody                                     # GlobalInterfaceStat
    | 'global' 'enum' NAME enumbody                                            # GlobalEnumStat
    | 'global' 'type' NAME ('=' newtype)?                                      # GlobalTypeStat
    | 'global' attnamelist ':' typelist ('=' explist)?                         # GlobalAttrStat
    | 'global' attnamelist '=' explist                                         # GlobalAttrAssignStat
    ;

attnamelist
    : NAME attrib? (',' NAME attrib?)*
    ;

attrib
    : '<' ('const' | 'close') '>'
    ;

// we rename `type` to `typ` because of keyword `type`
typ
    : '(' typ ')'
    | basetype ('|' basetype)*
    ;

nominal
    : NAME ('.' NAME)* typeargs?
    ;

basetype
    : 'string'
    | 'boolean'
    | 'nil'
    | 'number'
    | '{' typ (',' typ)* '}'
    | '{' typ ':' typ '}'
    | 'function' functiontype
    | nominal
    ;

typelist
    : typ (',' typ)*
    ;

retlist
    : '(' (typelist '...'?)? ')'
    | typelist '...'?
    ;

typeargs
    : '<' NAME (',' NAME)* '>'
    ;

interfacelist
    : nominal (',' nominal)*
    | '{' typ '}' (',' nominal)*
    ;

newtype
    : 'record' recordbody                # RecordNewType
    | 'enum' enumbody                    # EnumNewType
    | typ                                # TypeAliasNewType
    | 'require' '(' str ')' ('.' NAME)*  # RequireNewType
    ;

recordbody
    : typeargs? ('is' interfacelist)? ('where' exp)? recordentry* 'end'
    ;

recordentry
    : 'userdata'                       # UserdataEntry
    | 'type' NAME '=' newtype          # TypeAliasEntry
    | 'metamethod'? recordkey ':' typ  # FieldEntry
    | 'record' NAME recordbody         # NestedRecordEntry
    | 'interface' NAME recordbody      # NestedInterfaceEntry
    | 'enum' NAME enumbody             # NestedEnumEntry
    ;

recordkey
    : NAME
    | '[' str ']'
    ;

enumbody
    : str* 'end'
    ;

functiontype
    : typeargs? '(' partypelist? ')' (':' retlist)?
    ;

partypelist
    : partype (',' partype)*
    ;

partype
    : NAME '?'? ':' typ
    | '?'? typ
    ;

parnamelist
    : parname (',' parname)*
    ;

parname
    : NAME '?'? (':' typ)?
    ;

retstat
    : 'return' explist? ';'? # ReturnStat
    ;

label
    : '::' NAME '::'
    ;

funcname
    : NAME ('.' NAME)* (':' NAME)?
    ;

varlist
    : variable (',' variable)*
    ;

namelist
    : NAME (',' NAME)*
    ;

explist
    : exp (',' exp)*
    ;

exp
    : 'nil'
    | 'false'
    | 'true'
    | number
    | str
    | '...'
    | functiondef
    | prefixexp
    | tableconstructor
    | exp 'as' typ
    | exp 'as' '(' typelist ')'
    | <assoc = right> exp operatorPower exp
    | operatorUnary exp
    | exp operatorMulDivMod exp
    | exp operatorAddSub exp
    | <assoc = right> exp operatorStrcat exp
    | exp operatorComparison exp
    | NAME 'is' typ
    | exp operatorAnd exp
    | exp operatorOr exp
    | exp operatorBitwise exp
    ;

prefixexp
    : varOrExp nameAndArgs*
    ;

functioncall
    : varOrExp nameAndArgs+
    ;

varOrExp
    : variable
    | '(' exp ')'
    ;

// we rename `var` to `variable` because of keyword `var`
variable
    : (NAME | '(' exp ')' varSuffix) varSuffix*
    ;

varSuffix
    : nameAndArgs* ('[' exp ']' | '.' NAME)
    ;

nameAndArgs
    : (':' NAME)? args
    ;

args
    : '(' explist? ')'
    | tableconstructor
    | str
    ;

functiondef
    : 'function' funcbody
    ;

funcbody
    : typeargs? '(' parlist? ')' (':' retlist)? block 'end'
    ;

parlist
    : parnamelist (',' '...' (':' typ)?)?
    | '...' (':' typ)?
    ;

tableconstructor
    : '{' fieldlist? '}'
    ;

fieldlist
    : field (fieldsep field)* fieldsep?
    ;

field
    : '[' exp ']' '=' exp     # BracketAssignField
    | NAME (':' typ)? '=' exp # AssignField
    | exp                     # ExprField
    ;

fieldsep
    : ','
    | ';'
    ;

operatorOr
    : 'or'
    ;

operatorAnd
    : 'and'
    ;

operatorComparison
    : '<'
    | '>'
    | '<='
    | '>='
    | '~='
    | '=='
    ;

operatorStrcat
    : '..'
    ;

operatorAddSub
    : '+'
    | '-'
    ;

operatorMulDivMod
    : '*'
    | '/'
    | '%'
    | '//'
    ;

operatorBitwise
    : '&'
    | '|'
    | '~'
    | '<<'
    | '>>'
    ;

operatorUnary
    : 'not'
    | '#'
    | '-'
    | '~'
    ;

operatorPower
    : '^'
    ;

number
    : INT
    | HEX
    | FLOAT
    | HEX_FLOAT
    ;

str
    : NORMALSTRING
    | CHARSTRING
    | LONGSTRING
    ;

// LEXER

NAME
    : [a-zA-Z_][a-zA-Z_0-9]*
    ;

NORMALSTRING
    : '"' (EscapeSequence | ~('\\' | '"'))* '"'
    ;

CHARSTRING
    : '\'' (EscapeSequence | ~('\'' | '\\'))* '\''
    ;

LONGSTRING
    : '[' NESTED_STR ']'
    ;

fragment NESTED_STR
    : '=' NESTED_STR '='
    | '[' .*? ']'
    ;

INT
    : Digit+
    ;

HEX
    : '0' [xX] HexDigit+
    ;

FLOAT
    : Digit+ '.' Digit* ExponentPart?
    | '.' Digit+ ExponentPart?
    | Digit+ ExponentPart
    ;

HEX_FLOAT
    : '0' [xX] HexDigit+ '.' HexDigit* HexExponentPart?
    | '0' [xX] '.' HexDigit+ HexExponentPart?
    | '0' [xX] HexDigit+ HexExponentPart
    ;

fragment ExponentPart
    : [eE] [+-]? Digit+
    ;

fragment HexExponentPart
    : [pP] [+-]? Digit+
    ;

fragment EscapeSequence
    : '\\' [abfnrtvz"'\\]
    | '\\' '\r'? '\n'
    | DecimalEscape
    | HexEscape
    | UtfEscape
    ;

// Lua decimal escapes are bounded to 0..255.
fragment DecimalEscape
    : '\\' [01] Digit Digit
    | '\\' '2' [0-4] Digit
    | '\\' '25' [0-5]
    | '\\' Digit Digit
    | '\\' Digit
    ;

fragment HexEscape
    : '\\' 'x' HexDigit HexDigit
    ;

fragment UtfEscape
    : '\\' 'u{' HexDigit+ '}'
    ;

fragment Digit
    : [0-9]
    ;

fragment HexDigit
    : [0-9a-fA-F]
    ;

// define doc lexer before comment lexer
COMMENT
    : '--[' NESTED_STR ']' -> channel(HIDDEN)
    ;

LINE_COMMENT
    : '--' (
        // --
        | '[' '='*                                            // --[==
        | '[' '='* ~('=' | '[' | '\r' | '\n') ~('\r' | '\n')* // --[==AA
        | ~('[' | '\r' | '\n') ~('\r' | '\n')*                // --AAA
    ) ('\r\n' | '\r' | '\n' | EOF) -> channel(HIDDEN)
    ;

WS
    : [ \t\r\n]+ -> skip
    ;

SHEBANG
    : '#' '!' ~('\n' | '\r')* -> channel(HIDDEN)
    ;
