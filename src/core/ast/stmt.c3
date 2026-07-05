module analyzer::core::ast;

import std::collections::list;
import analyzer::core::string_pool;

struct IfStmt
{
	Node* condition;
	Node* then_body;
	Node* else_body;
	Ident label;
}

struct CtIfStmt
{
	Node* expr;
	NodeArray then_stmts;
	NodeArray else_stmts;
}

struct CompoundStmt
{
	NodeArray statements;
}

struct SwitchStmt
{
	NodeArray cases;
	Node* cond;
	Ident label;
}

<*
 - expr: 
 - to_expr: 
 - body: compound_stmt
*>
struct CaseStmt
{
	Node* expr;
	Node* to_expr;
	Node* body;
}

<*
 -body: compound_stmt
*>
struct DefaultStmt
{
	Node* body;
}

struct NextcaseStmt
{
	Node* expr;
	Ident label;
	bool is_default;
}

struct ContinueBreakStmt
{
	Ident label;
	bool is_continue;
}

struct ReturnStmt
{
	Node* expr;
}

struct CtSwitchStmt
{
	Node* cond;
	NodeArray cases;
}

struct ExprStmt
{
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
	NullableNode init;
	NullableNode cond;
	NullableNode incr;
	Node* body;
	Ident label;
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
	NullableNode init;
	Node* cond;
	NullableNode incr;
	Node* body;
}

struct WhileStmt
{
	Node* cond;
	Node* body;
	Ident label;
}

struct DoWhileStmt
{
	Node* body;
	NullableNode cond;
	Ident label;
}

struct ForeachStmt
{
	Node* index;
	Node* variable;
	Node* enumeration;
	Node* body;
	Ident label;
	bool is_reverse;
	bool value_by_ref;
	bool index_by_ref;
}

struct CtForeachStmt
{
	Node* index;
	Node* value;
	Node* expr;
	Node* body;
}

struct CtAssertStmt
{
	Node* expr;
	NullableNode msg_expr;
	NodeArray args;
}

struct CtErrorStmt
{
	Node* expr;
}

struct CtEchoStmt
{
	Node* expr;
}

struct DeferStmt
{
	DeferKind kind;
	Node* ident;
	Node* body;
}

struct AssertStmt
{
	Node* expr;
	Node* message;
	NodeArray args;
}

struct CtExpandStmt
{
	Node* expr;
}

struct AsmBlockStmt
{
	bool is_volatile;
	bool is_inline;
	bool is_goto;
	bool is_string;
	bool is_aligned;
}