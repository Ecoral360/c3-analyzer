module analyzer::lexer;

enum TokenKind : char
{
	<* Error *>
	ERROR,

	// Operators
	<* & *>
	AMP,

	<* | *>
	BIT_OR,

	<* ^ *>
	BIT_XOR,

	<* ~ *>
	BIT_NOT,

	<* ! *>
	BANG,

	<* + *>
	PLUS,

	<* - *>
	MINUS,

	<* * *>
	ASTERISK,

	<* / *>
	DIV,

	<* % *>
	MOD,

	<* ? *>
	QUESTION,

	<* ?? *>
	QUESTQUEST,

	<* ?: *>
	ELVIS,

	<* !! *>
	BANGBANG,

	<* $$ *>
	BUILTIN,

	<* >> *>
	RSHIFT,

	<* << *>
	LSHIFT,

	<* ++ *>
	PLUSPLUS,

	<* -- *>
	MINUSMINUS,

	<* +++ *>
	CT_CONCAT_OP,

	<* ??? *>
	CT_TERNARY,

	// Assignment
	<* = *>
	EQ,

	<* >>= *>
	RSHIFT_ASSIGN,

	<* <<= *>
	LSHIFT_ASSIGN,

	<* += *>
	PLUS_ASSIGN,

	<* -= *>
	MINUS_ASSIGN,

	<* *= *>
	MULT_ASSIGN,

	<* /= *>
	DIV_ASSIGN,

	<* %= *>
	MOD_ASSIGN,

	<* &= *>
	BIT_AND_ASSIGN,

	<* ^= *>
	BIT_XOR_ASSIGN,

	<* |= *>
	BIT_OR_ASSIGN,

	<* +++= *>
	CT_CONCAT_ASSIGN,

	// Comparison
	<* < *>
	LESS,

	<* > *>
	GREATER,

	<* && *>
	AND,

	<* || *>
	OR,

	<* <= *>
	LESS_EQ,

	<* >= *>
	GREATER_EQ,

	<* == *>
	EQEQ,

	<* != *>
	NOT_EQUAL,

	<* &&& *>
	CT_AND_OP,

	<* ||| *>
	CT_OR_OP,

	// Punctuation
	<* ; *>
	EOS,

	<* : *>
	COLON,

	<* :: *>
	SCOPE,

	<* , *>
	COMMA,

	<* . *>
	DOT,

	<* .. *>
	DOTDOT,

	<* ... *>
	ELLIPSIS,

	// Structure
	<* { *>
	LBRACE,

	<* } *>
	RBRACE,

	<* [ *>
	LBRACKET,

	<* ] *>
	RBRACKET,

	<* ( *>
	LPAREN,

	<* ) *>
	RPAREN,

	<* -> *>
	ARROW,

	<* => *>
	IMPLIES,

	<* [< *>
	LVEC,

	<* >] *>
	RVEC,

	// '<*'
	DOCS_START,

	// '*>'
	DOCS_END,

	<* Any identifer before a @ *>
	DOCS_TEXT,

	<* // *>
	LINE_COMMENT,

	<* /* *>
	BLOCK_COMMENT,

	// Literals (Identifiers and Strings)
 	<* STRING *>
	STRING_LITERAL,

	<* 'a' 'FO' 'BARS' '\u1232' *>
	CHAR_LITERAL, 
	<* Base64 or Hex *>
	BYTES_LITERAL, 

	<* 123 *>
	INT_DECIMAL_LITERAL, 
	<* 0x23 *>
	INT_HEX_LITERAL,  
	<* 0o327 *>   
	INT_OCTAL_LITERAL,  
	<* 0b10010 *> 
	INT_BIN_LITERAL,    
	<* 43.23e23 *>
	FLOAT_DECIMAL_LITERAL, 
	<* 0x23.2p-2a *>
	FLOAT_HEX_LITERAL,    

	<* foo *>
	IDENT,

	<* '@' *>
	AT,

	<* Foo, *>
	TYPE_IDENT,      
	<* FOO *> 
	CONST_IDENT,    
	<* @foo *>  
	AT_IDENT,         
	<* @Foo *>
	AT_TYPE_IDENT,   
	<* @FOO *>
	AT_CONST_IDENT,   
	<* #foo, *>
	HASH_IDENT,       
	<* #Type *>
	HASH_TYPE_IDENT,  
	<* #CONST_IDENT *>
	HASH_CONST_IDENT, 
	<* $foo *>
	CT_IDENT,      
	<* $Foo, *>   
	CT_TYPE_IDENT,    
	<* $FOO, *>
	CT_CONST_IDENT,   

	<* Base Types *>
	VOID_TYPE,
	BOOL_TYPE,
	CHAR_TYPE,
	DOUBLE_TYPE,
	FLOAT_TYPE,
	FLOAT16_TYPE,
	BFLOAT_TYPE,
	INT128_TYPE,
	ICHAR_TYPE,
	INT_TYPE,
	IPTR_TYPE,
	SZ_TYPE,
	LONG_TYPE,
	SHORT_TYPE,
	UINT128_TYPE,
	UINT_TYPE,
	ULONG_TYPE,
	UPTR_TYPE,
	USHORT_TYPE,
	USZ_TYPE,
	FLOAT128_TYPE,
	ANY_TYPE,
	FAULT_TYPE,
	TYPEID_TYPE,
	UNTYPEDLIST_TYPE,

	// Keywords
	ALIAS,
	ASSERT,
	ASM,
	ATTRDEF,
	BITSTRUCT,
	BREAK,
	CASE,
	CATCH,
	CONSTDEF,
	CONST,
	CONTINUE,
	DEFAULT,
	DEFER,
	DO,
	ELSE,
	ENUM,
	EXTERN,
	FALSE,
	FAULTDEF,
	FOR,
	FOREACH,
	FOREACH_R,
	FN,
	TLOCAL,
	IF,
	INLINE,
	IMPORT,
	LENGTHOF,
	MACRO,
	MODULE,
	NEXTCASE,
	NULL,
	INTERFACE,
	RETURN,
	STATIC,
	STRUCT,
	SWITCH,
	TRUE,
	TRY,
	TYPEDEF,
	UNION,
	VAR,
	WHILE,
	
	<* $assert *>
	CT_ASSERT,

	<* $case *>
	CT_CASE,

	<* $default *>
	CT_DEFAULT,

	<* $defined *>
	CT_DEFINED,

	<* $echo *>
	CT_ECHO,

	<* $else *>
	CT_ELSE,

	<* $embed *>
	CT_EMBED,

	<* $endfor *>
	CT_ENDFOR,

	<* $endforeach *>
	CT_ENDFOREACH,

	<* $endif *>
	CT_ENDIF,

	<* $endswitch *>
	CT_ENDSWITCH,

	<* $eval *>
	CT_EVAL,

	<* $error *>
	CT_ERROR,

	<* $exec *>
	CT_EXEC,

	<* $expand *>
	CT_EXPAND,

	<* $feature *>
	CT_FEATURE,

	<* $for *>
	CT_FOR,

	<* $foreach *>
	CT_FOREACH,

	<* $if *>
	CT_IF,

	<* $include *>
	CT_INCLUDE,

	<* $reflect *>
	CT_REFLECT,

	<* $stringify *>
	CT_STRINGIFY,

	<* $switch *>
	CT_SWITCH,

	<* $Typefrom *>
	CT_TYPEFROM,

	<* $Typeof *>
	CT_TYPEOF,

	<* $vaarg, *>
	CT_VAARG,

	AT_INLINE,
	AT_PURE,
	AT_NOINLINE,

	EOF
}

fn bool TokenKind.is_keyword(self) @inline
{
	return self.ordinal >= TokenKind.ALIAS.ordinal && self.ordinal <= TokenKind.WHILE.ordinal;
}

fn bool TokenKind.is_base_type(self) @inline
{
	return self.ordinal >= TokenKind.VOID_TYPE.ordinal && self.ordinal <= TokenKind.UNTYPEDLIST_TYPE.ordinal;
}

fn bool TokenKind.is_int_literal(
	&self
) @inline => TokenKind.INT_DECIMAL_LITERAL.ordinal <= self.ordinal && self.ordinal <= TokenKind.INT_BIN_LITERAL.ordinal;

fn bool TokenKind.is_float_literal(
	&self
) @inline => *self == TokenKind.FLOAT_DECIMAL_LITERAL || *self == TokenKind.FLOAT_HEX_LITERAL;

