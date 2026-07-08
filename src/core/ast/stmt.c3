module analyzer::core::ast;

import std::collections::list;
import analyzer::core::string_pool;

struct IfStmt
{
	inline Node node;
	Node* condition;
	Node* then_body;
	Node* else_body;
	Ident* label;
}

struct CtIfStmt
{
	inline Node node;
	Node* expr;
	NodeArray then_stmts;
	NodeArray else_stmts;
}

struct CompoundStmt
{
	inline Node node;
	NodeArray statements;
}

struct SwitchStmt
{
	inline Node node;
	NodeArray cases;
	Node* cond;
	Ident* label;
}

<*
 - expr: 
 - to_expr: 
 - body: compound_stmt
*>
struct CaseStmt
{
	inline Node node;
	Node* expr;
	Node* to_expr;
	Node* body;
}

<*
 -body: compound_stmt
*>
struct DefaultStmt
{
	inline Node node;
	Node* body;
}

struct NextcaseStmt
{
	inline Node node;
	Node* expr;
	Ident* label;
	bool is_default;
}

struct ContinueBreakStmt
{
	inline Node node;
	Ident* label;
	bool is_continue;
}

struct ReturnStmt
{
	inline Node node;
	Node* expr;
}

struct CtSwitchStmt
{
	inline Node node;
	Node* cond;
	NodeArray cases;
}

struct ExprStmt
{
	inline Node node;
	Node* expr_stmt;
}

<*
 - init: expr_list?
 - cond: cond_expr?
 - incr: cond_ist?
 - body: stmt
 - label: optional label
*>
struct ForStmt
{
	inline Node node;
	NullableNode init;
	NullableNode cond;
	NullableNode incr;
	Node* body;
	Ident* label;
}

<*
 - init: expr_list?
 - cond: cond_expr?
 - incr: cond_ist?
 - body: stmt
 - label: optional label
*>
struct CtForStmt
{
	inline Node node;
	NullableNode init;
	Node* cond;
	NullableNode incr;
	Node* body;
}

struct WhileStmt
{
	inline Node node;
	Node* cond;
	Node* body;
	Ident* label;
}

struct DoWhileStmt
{
	inline Node node;
	Node* body;
	NullableNode cond;
	Ident* label;
}

struct ForeachStmt
{
	inline Node node;
	Node* index;
	Node* variable;
	Node* enumeration;
	Node* body;
	Ident* label;
	bool is_reverse;
	bool value_by_ref;
	bool index_by_ref;
}

struct CtForeachStmt
{
	inline Node node;
	Node* index;
	Node* value;
	Node* expr;
	Node* body;
}

struct CtAssertStmt
{
	inline Node node;
	Node* expr;
	NullableNode msg_expr;
	NodeArray args;
}

struct CtErrorStmt
{
	inline Node node;
	Node* expr;
}

struct CtEchoStmt
{
	inline Node node;
	Node* expr;
}

struct DeferStmt
{
	inline Node node;
	DeferKind defer_kind;
	Node* ident;
	Node* body;
}

struct AssertStmt
{
	inline Node node;
	Node* expr;
	Node* message;
	NodeArray args;
}

struct CtExpandStmt
{
	inline Node node;
	Node* expr;
}

struct AsmBlockStmt
{
	inline Node node;
	bool is_volatile;
	bool is_inline;
	bool is_goto;
	bool is_string;
	bool is_aligned;
}

struct NopStmt
{
	inline Node node;
}
