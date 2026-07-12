module analyzer::core;

import std::collections::list;
import analyzer::lexer;

typedef FileID = ushort;

faultdef UNKNOWN_OP_OVERLOAD;

struct Location
{
	int line;
	int column;
}

fn bool Location.eq(self, Location other) @operator(==)
{
	return self.line == other.line && self.column == other.column;
}

struct Range
{
	Location start;
	Location end;
}

fn bool Range.eq(self, Location other) @operator(==)
{
	return self.start == other.start && self.end == other.end;
}

enum AttributeKind : char
{
	ALIGN,
	ALLOW_DEPRECATED,
	BENCHMARK,
	BIGENDIAN,
	BUILTIN,
	CALLCONV,
	CNAME,
	COMPACT,
	CONST,
	CONSTINIT,
	DEPRECATED,
	DYNAMIC,
	EXPORT,
	EXTERN,
	FINALIZER,
	FORMAT,
	IF,
	INLINE,
	INIT,
	JUMP,
	LINK,
	LITTLEENDIAN,
	LOCAL,
	MAYDISCARD,
	NAKED,
	NOALIAS,
	NODISCARD,
	NOINIT,
	NOINLINE,
	NOPADDING,
	NORECURSE,
	NORETURN,
	NOSANITIZE,
	NOSTRIP,
	OBFUSCATE,
	OPERATOR,
	OPERATOR_R,
	OPERATOR_S,
	OPTIONAL,
	OVERLAP,
	PACKED,
	PRIVATE,
	PUBLIC,
	PURE,
	REFLECT,
	SAFEINFER,
	SAFEMACRO,
	SIMD,
	SECTION,
	STRUCTLIKE,
	TAG,
	TEST,
	UNUSED,
	USED,
	WASM,
	WEAK,
	WINMAIN,
	NONE,
}

fn AttributeKind get_attribute_from_string(String str)
{
	switch (str)
	{
		case "@align": return AttributeKind.ALIGN;
		case "@allow_deprecated": return AttributeKind.ALLOW_DEPRECATED;
		case "@benchmark": return AttributeKind.BENCHMARK;
		case "@bigendian": return AttributeKind.BIGENDIAN;
		case "@builtin": return AttributeKind.BUILTIN;
		case "@callconv": return AttributeKind.CALLCONV;
		case "@cname": return AttributeKind.CNAME;
		case "@compact": return AttributeKind.COMPACT;
		case "@const": return AttributeKind.CONST;
		case "@constinit": return AttributeKind.CONSTINIT;

		case "@deprecated": return AttributeKind.DEPRECATED;
		case "@dynamic": return AttributeKind.DYNAMIC;
		case "@export": return AttributeKind.EXPORT;
		case "@extern": return AttributeKind.EXTERN;
		case "@finalizer": return AttributeKind.FINALIZER;
		case "@format": return AttributeKind.FORMAT;

		case "@if": return AttributeKind.IF;
		case "@inline": return AttributeKind.INLINE;
		case "@init": return AttributeKind.INIT;
		case "@jump": return AttributeKind.JUMP;
		case "@link": return AttributeKind.LINK;
		case "@littleendian": return AttributeKind.LITTLEENDIAN;
		case "@local": return AttributeKind.LOCAL;

		case "@maydiscard": return AttributeKind.MAYDISCARD;
		case "@naked": return AttributeKind.NAKED;
		case "@noalias": return AttributeKind.NOALIAS;
		case "@nodiscard": return AttributeKind.NODISCARD;
		case "@noinit": return AttributeKind.NOINIT;
		case "@noinline": return AttributeKind.NOINLINE;
		case "@nopadding": return AttributeKind.NOPADDING;
		case "@norecurse": return AttributeKind.NORECURSE;
		case "@noreturn": return AttributeKind.NORETURN;
		case "@nosanitize": return AttributeKind.NOSANITIZE;
		case "@nostrip": return AttributeKind.NOSTRIP;

		case "@obfuscate": return AttributeKind.OBFUSCATE;
		case "@operator": return AttributeKind.OPERATOR;
		case "@operator_r": return AttributeKind.OPERATOR_R;
		case "@operator_s": return AttributeKind.OPERATOR_S;
		case "@optional": return AttributeKind.OPTIONAL;
		case "@overlap": return AttributeKind.OVERLAP;
		case "@packed": return AttributeKind.PACKED;
		case "@private": return AttributeKind.PRIVATE;
		case "@public": return AttributeKind.PUBLIC;
		case "@pure": return AttributeKind.PURE;

		case "@reflect": return AttributeKind.REFLECT;
		case "@safeinfer": return AttributeKind.SAFEINFER;
		case "@safemacro": return AttributeKind.SAFEMACRO;
		case "@section": return AttributeKind.SECTION;
		case "@simd": return AttributeKind.SIMD;
		case "@structlike": return AttributeKind.STRUCTLIKE;

		case "@tag": return AttributeKind.TAG;
		case "@test": return AttributeKind.TEST;
		case "@unused": return AttributeKind.UNUSED;
		case "@used": return AttributeKind.USED;
		case "@wasm": return AttributeKind.WASM;
		case "@weak": return AttributeKind.WEAK;
		case "@winmain": return AttributeKind.WINMAIN;

		default: return AttributeKind.NONE;
	}
}

bitstruct TypeFlags : uint
{
	bool is_none;
	bool is_vector;
	bool is_comptime;
	bool is_optional;
}

bitstruct VarDeclFlags : uint
{
	bool is_const;
	bool is_local;
	bool is_extern;
	bool is_thread_local;
	bool is_inline;
	bool is_static;

	bool is_ref;

	// for params
	bool is_self;
	bool is_self_by_ref;
	bool is_variadic;
	bool is_macro_optional_ellipsis; // For `param = ...`
}

bitstruct ContractFlags : char
{
	bool is_pure;
}

bitstruct ContractParamFlags : char
{
	bool is_ref;
}

bitstruct AsmFlags : char
{
	bool is_volatile;
	bool is_string_style;
}

enum AsmArgKind : char
{
	ARG_REG,     // A register
	ARG_ADDR,    // [...]
	ARG_REGVAR,  // foo - variable in a register, r/=r/+r
	ARG_MEMADDR, // &foo - address to a variable
	ARG_MEMVAR,  // [&foo]
	ARG_VALUE,   // -1, (expr), 1, 3.0
	ARG_INT,     // Converted from VALUE
}

enum AsmOffsetKind : char
{
	SCALE_1,    // *
	SCALE_2,
	SCALE_4,
	SCALE_8,
	SCALE_SHR,  // >>
	SCALE_SHL,  // <<
	SCALE_ASHL, // >>>
	SCALE_ROR,  // ror
	SCALE_RRX,  // rrx
}

bitstruct AsmArgBits : uint
{
	bool arg_bits_8;
	bool arg_bits_16;
	bool arg_bits_32;
	bool arg_bits_64;
	bool arg_bits_128;
	bool arg_bits_256;
	bool arg_bits_512;
	bool arg_bits_80;
	bool arg_bits_5;
	bool arg_bits_12;
	bool arg_bits_20;
}

enum AsmRegisterKind : char
{
	REG_INT,
	REG_FLOAT,
	REG_IVEC,
	REF_FVEC,
}

enum OverloadKind : char
{
	UNKNOWN,
	OV_ELEMENT_AT,
	OV_ELEMENT_REF,
	OV_ELEMENT_SET,
	OV_LEN,
	OV_NEGATE,
	OV_UNARY_MINUS,
	OV_PLUS,
	OV_MINUS,
	OV_MULTIPLY,
	OV_DIVIDE,
	OV_REMINDER,
	OV_AND,
	OV_OR,
	OV_XOR,
	OV_SHL,
	OV_SHR,
	OV_EQUAL,
	OV_LESS_THAN,
	OV_PLUS_ASSIGN,
	OV_MINUS_ASSIGN,
	OV_MULTIPLY_ASSIGN,
	OV_DIVIDE_ASSIGN,
	OV_REMINDER_ASSIGN,
	OV_AND_ASSIGN,
	OV_OR_ASSIGN,
	OV_XOR_ASSIGN,
	OV_SHL_ASSIGN,
	OV_SHR_ASSIGN,
}

fn OverloadKind get_overload_kind(TokenKind kind)
{
	switch (kind)
	{
		case PLUS:           return OV_PLUS;
		case PLUS_ASSIGN:    return OV_PLUS_ASSIGN;
		case MINUS:          return OV_MINUS;
		case MINUS_ASSIGN:   return OV_MINUS_ASSIGN;
		case ASTERISK:       return OV_MULTIPLY;
		case MULT_ASSIGN:    return OV_MULTIPLY_ASSIGN;
		case DIV:            return OV_DIVIDE;
		case MOD:            return OV_REMINDER;
		case MOD_ASSIGN:     return OV_REMINDER_ASSIGN;
		case AMP:            return OV_AND;
		case BIT_AND_ASSIGN: return OV_AND_ASSIGN;
		case BIT_OR:         return OV_OR;
		case BIT_OR_ASSIGN:  return OV_OR_ASSIGN;
		case BIT_XOR:        return OV_XOR;
		case BIT_XOR_ASSIGN: return OV_XOR_ASSIGN;
		case LSHIFT:         return OV_SHL;
		case LSHIFT_ASSIGN:  return OV_SHL_ASSIGN;
		case RSHIFT:         return OV_SHR;
		case RSHIFT_ASSIGN:  return OV_SHR_ASSIGN;
		case BIT_NOT:        return OV_NEGATE;
		case EQEQ:           return OV_EQUAL;
		case LESS:           return OV_LESS_THAN;
		default:
			return UNKNOWN;
	}
}

enum InOutModifier : char
{
	ANY,
	IN,
	OUT,
	INOUT,
}

enum Visibility : char
{
	PUBLIC,
	PRIVATE,
	LOCAL
}

<*
 Type expression variants.

 Payload mapping:
- TYPE_IDENTIFIER: TypeExpr.unresolved
- TYPE_POINTER and TYPE_SLICE: TypeExpr.modify
- TYPE_ARRAY and TYPE_VECTOR: TypeExpr.array
- TYPE_GENERIC: TypeExpr.generic
- TYPE_FUNCTION: TypeExpr.func
*>
enum TypeExprKind : char
{
	TYPE_IDENTIFIER,
	TYPE_POINTER,
	TYPE_ARRAY,
	TYPE_SLICE,
	TYPE_VECTOR,
	TYPE_GENERIC,
	TYPE_TYPEOF,
	TYPE_TYPEFROM,
	TYPE_FUNCTION
}

enum DesignatorKind : char
{
	PERIOD,
	INDEX,
	RANGE,
}

enum AccessKind : char
{
	INSTANCE, // field.
	STATIC    // Type::
}
