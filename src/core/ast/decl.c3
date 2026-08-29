module analyzer::core::ast;

import analyzer::lexer;

import std::collections::list;

struct ContractParam
{
	inline Node node;
	Ident* ident;
	Ident* description;
	InOutModifier modifier;
	bool by_ref;
}

struct ContractDecl
{
	inline Node node;
	NodeArray requires;
	NodeArray ensures;
	NodeArray returns;
	NodeArray params; // ContractParam
	Ident* comment;
	Node* return_desc; // ident_expr
	Node* deprecated;
	bool is_pure;
}

<*
 - `generics`: generic_decl | null
*>
struct ModuleDecl
{
	inline Node node;
	Node* path;
	NullableNode contract;
	NodeArray attributes;
	Node* generics;
}

struct ImportDecl
{
	inline Node node;
	NodeArray paths;
	NodeArray attributes;
}

<*
 AliasDecl represents the three C3 alias forms:
- TYPE_ALIAS: a TYPE_IDENT name with a type expression target.
- MODULE_ALIAS: an IDENT name whose target is a module path after '=' 'module'.
- IDENT_ALIAS: an IDENT, CONST_IDENT, or AT_IDENT name whose target path ends
  in the same token kind.

Fields:
- name: The interned alias name text.
- name_kind: The token kind used by the alias name.
- alias_kind: Which alias form was parsed.
- generics: Optional generic declaration parameters, e.g. Ty in `alias Stack<Ty> = List{Ty};`.
- target: TYPE_EXPR for TYPE_ALIAS, PATH_EXPR for MODULE_ALIAS and IDENT_ALIAS.
- attributes: Attributes written on the alias declaration before '='.
*>
struct AliasDecl
{
	inline Node node;
	NullableNode contract;
	Ident* name;
	TokenKind name_kind;
	AliasDeclKind alias_kind;
	Node* generics;
	Node* target;
	NodeArray attributes;
}

<*
 TypedefDecl represents a C3 distinct type declaration.

 Fields:
- name: The interned typedef type name.
- base_type: The underlying TYPE_EXPR this distinct type is based on.
- generics: Optional generic declaration parameters, e.g. Type in `typedef Option<Type> = Type*`.
- interfaces: Optional interface type list after the typedef name.
- attributes: Attributes written on the typedef declaration or base type.
- is_inline: True when the declaration uses '= inline type'.
*>
struct TypedefDecl
{
	inline Node node;
	NullableNode contract;
	Ident* name;
	Node* base_type;
	Node* generics;
	NodeArray interfaces;
	NodeArray attributes;
	bool is_inline;
}

struct FnDecl
{
	inline Node node;
	Ident* name;
	Node* associated_type;
	Node* ret_type;
	Node* body;
	Node* generics;
	NullableNode contract;
	NodeArray params;
	NodeArray attributes;
}

struct MacroDecl
{
	inline Node node;
	Ident* name;
	NullableNode associated_type;
	NullableNode ret_type;
	Node* body;
	NullableNode contract;
	Node* body_params;
	NodeArray params;
	NodeArray attributes;
	Node* generics;
}

<*
 VarDecl: represents (Global, Local, Field) variables
- type: type_expr if has type
- init_expr: if has initializer or if `VAR_BITFIELD` might be range start
- bit_end: for `VAR_BITFIELD` end bit range
- next: Var_decl if chained (e.g. int a, b, c; )
*>
struct VarDecl
{
	inline Node node;
	VarDeclKind var_kind;
	VarDeclFlags var_flags;
	Ident* name;
	NullableNode contract;
	Node* type;
	Node* init_expr;
	Node* bit_end;
	NodeArray attributes;
	Node* assoc_values; // enum variant associated values: VARIANT{expr, ...}
	Node* next;
}

struct EnumDecl
{
	inline Node node;
	NullableNode contract;
	Ident* name;
	NodeArray interfaces; // optional implemented interfaces: "(" type ("," type)* ")"
	bool is_inline_backing;
	Node* backing_type; // optional: ":" type
	NodeArray assoc_params; // optional enum_param_list inside ":"
	NodeArray attributes;
	NodeArray variants;
}

struct AttributeDecl
{
	inline Node node;
	NullableNode path;
	Ident* name;
	NodeArray exprs;
	AttributeKind attribute_kind;
	bool is_custom;
}

struct CtExpandDecl
{
	inline Node node;
	Node* expr;
	NodeArray attributes;
}

<*
 StructDecl is both for structs & unions `is_union`
 - `generics`: generic_decl | null
*>
struct StructDecl
{
	inline Node node;
	NullableNode contract;
	NodeArray interfaces;
	NodeArray attributes;
	NodeArray fields;
	Node* generics;
	Node* type;
	Node* next;
	Ident* name;
	bool is_union;
	bool is_bitstruct;
}

struct FaultDecl
{
	inline Node node;
	NullableNode contract;
	NodeArray attributes;
	Ident* name;
}

struct FaultdefDecl
{
	inline Node node;
	NullableNode contract;
	NodeArray faults;
}

<*
 - interfaces: parent interfaces
*>
struct InterfaceDecl
{
	inline Node node;
	NullableNode contract;
	NodeArray interfaces;
	NodeArray attributes;
	NodeArray methods;
	Ident* name;
}

<*
 - `defined_attributes` the attributes after the '='
*>
struct AttrdefDecl
{
	inline Node node;
	NullableNode contract;
	Ident* name;
	NodeArray params;
	NodeArray attributes;
	NodeArray defined_attributes;
}

struct CtAssertDecl
{
	inline Node node;
	Node* stmt;
}

struct GenericDecl
{
	inline Node node;
	NodeArray params;
}

struct BodyParamDecl
{
	inline Node node;
	NodeArray params;
}