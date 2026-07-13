module analyzer::core::ast;

import std::collections::list;

struct BinaryExpr
{
	inline Node node;
	Node* left;
	Node* right;
	OperatorKind op;
}

struct IdentExpr
{
	inline Node node;
	Ident* ident;
	Node* path_expr;
}

struct PathExpr
{
	inline Node node;
	Ident* path;
	bool is_prefix;
}

<*
 TypeExpr represents C3 type syntax.

 Payloads:
- unresolved: TYPE_IDENTIFIER name and optional module path.
- modify: TYPE_POINTER and TYPE_SLICE base type.
- expr: $Typeof(expr) || $Typeof(expr)
- array: TYPE_ARRAY and TYPE_VECTOR base type plus length expression.
  `len_expr` is null for inferred arrays such as `Type[*]`.
- generic: TYPE_GENERIC base type and generic argument expressions.
- func: TYPE_FUNCTION return type and VAR_DECL parameter nodes.
*>
struct TypeExpr
{
	inline Node node;
	TypeExprKind type_kind;
	bool optional;

	union
	{
		struct unresolved
		{
			Ident* name;
			Node* path;
		}

		struct modify
		{
			Node* base;
		}

		Node* expr;

		struct array
		{
			Node* base;
			Node* len_expr;
		}

		struct generic
		{
			Node* base;
			Node*[] params;
		}

		struct func
		{
			Node* ret_type;
			NodeArray params;
			NodeArray attributes;
		}
	}
   
	Type* type;
}

struct CallExpr
{
	inline Node node;
	bool is_outer_call;
	Node* callee;
	MacroBodyExpr* macro_body_expr;
	NodeArray args;
	NodeArray attributes;
}

struct ContractExpr
{
	inline Node node;
	Node* exprs;
	Ident** comment;
	Node* expr_string;
}

struct ExprList
{
	inline Node node;
	NodeArray exprs;
}

enum LiteralKind : char
{
	INT_LITERAL,
	STRING_LITERAL,
	BYTES_LITERAL,
	REAL_LITERAL,
	BOOL_LITERAL,
	NULL_LITERAL,
}

struct LiteralExpr
{
	inline Node node;
	LiteralKind literal_kind;

	union
	{
		uint128 integer;
		double real;
		String string;
		char[] bytes;
		bool boolean;
	}
}

struct UnaryExpr
{
	inline Node node;
	UnaryOpKind operator;
	Node* expr;
}

struct PostUnaryExpr
{
	inline UnaryExpr unary;
}

struct CondExpr
{
	inline Node node;
	NodeArray exprs;
}

<*
 - variable: 
 - type: type_expr | missing
 - exprs:
*>
struct CatchExpr
{
	inline Node node;
	Node* variable;
	Node* type;
	NodeArray exprs;
}

<*
 - next: null | points to the next TryExpr
*>
struct TryExpr
{
	inline Node node;
	Node* variable;
	Node* type;
	Node* init;
	Node* next;
}

<*

*>
struct TernaryExpr
{
	inline Node node;
	Node* cond;
	Node* then_expr;
	Node* else_expr;
	bool is_grouped;
	bool is_const;
}

struct MacroBodyExpr
{
	inline Node node;
	Node* body;
	NodeArray args;
}

struct BuiltinExpr
{
	inline Node node;
	BuiltinFunction builtin;
	Ident* name;
}

struct CompilerConstExpr
{
	inline BuiltinExpr expr;
}

struct SplatExpr
{
	inline Node node;
	Node* inner;
}

struct VasplatExpr
{
	inline Node node;
	Node* range_expr;
}

struct NamedArgExpr
{
	inline Node node;
	Ident* name;
	Node* value;
}

struct EvalNamedArgExpr
{
	inline Node node;
	Node* name;
	Node* value;
}

struct CtEvalExpr
{
	inline Node node;
	Node* inner_expr;
}

struct LambdaExpr
{
	inline Node node;
	NodeArray attributes;
	NodeArray params;
	Node* return_type;
	Node* body;
}

struct GenericIdentExpr
{
	inline Node node;
	NodeArray exprs;
}

struct CastExpr
{
	inline Node node;
	Node* operand;
	Node* inner;
}

struct GroupExpr
{
	inline Node node;
	Node* inner;
}

struct InitializerListExpr
{
	inline Node node;
	NodeArray exprs;
}

<*
 - `path`:  Left-hand side part of the path (null if it's the start)
 - `field`: Valid if kind == PERIOD (.field)
 - `start`: Valid if kind == INDEX or RANGE ([start])
 - `end`:   Valid if kind is RANGE ([start .. end])
*>
struct DesignatorExpr
{
	inline Node node;
	DesignatorKind designator_kind;
	Node* path;

	union data
	{
		Node* field;
		Node* range;
	}
}

<*
 - `path`: DESIGNATOR_EXPR node chain (.foo.bar)
 - `value`: assigned expression node (= 42)
*>
struct DesignatedInitializerExpr
{
	inline Node node;
	Node* path;
	Node* value;
}

struct CompoundLiteralExpr
{
	inline Node node;
	Node* initializer_expr;
	Node* type_expr;
}

struct AccessExpr
{
	inline Node node;
	AccessKind access_kind;
	Node* left;
	Node* member;
}

struct MaybeDerefExpr
{
	inline Node node;
	Node* left;
}

<*
 - `start_from_end`: True if start had '^' (BIT_XOR)
 - `end_from_end`: True if end had '^' (BIT_XOR)
*>
struct RangeExpr
{
	inline Node node;
	RangeKind range_kind;
	bool start_from_end;
	bool end_from_end;
	Node* start;
	Node* end;
}

struct OptionalExpr
{
	inline Node node;
	Node* inner_expr;
}

struct CtDefinedExpr
{
	inline Node node;
	NodeArray expr_list;
}

struct CtFeatureExpr
{
	inline Node node;
	Node* inner_expr;
}

struct LengthofExpr
{
	inline Node node;
	Node* inner_expr;
}

struct CtStringifyExpr
{
	inline Node node;
	Node* inner_expr;
}

struct VaargExpr 
{
	inline Node node;
	Node* expr;
	VaargKind vaarg_kind;
	bool start_from_end;
}

struct OverloadExpr
{
	inline Node node;
	OverloadKind overload_kind;
}

struct CtReflectExpr
{
	inline Node node;
	Node* inner_expr;
}
