module analyzer::sema @feat(SEMA);

import analyzer::core;
import analyzer::cursor;

import std::collections::list;

fn void run_variable_pass(SemaContext* ctx) => @pool()
{
	SourceFile* sf = ctx.context.current_source_file;

	foreach (root_node : sf.ast.statements)
	{
		if (!root_node) continue;

		if (root_node.kind == MODULE_DECL)
		{
			ModuleDecl* mod_decl = root_node.as(ModuleDecl);
			if (!mod_decl.path || mod_decl.path.kind != PATH_EXPR) continue;

			PathExpr* expr   = mod_decl.path.as(PathExpr);
			String full_path = expr.path.text;

			ctx.current_module.comptime_scope.range.end = root_node.range.start;
			ctx.current_module.runtime_scope.range.end = root_node.range.start;

			ctx.enter_module_section(full_path, root_node.range.start);

			Range range = {
				.start = root_node.range.start,
				.end = { },
			};

			ctx.current_module.comptime_scope.range = range;
			ctx.current_module.runtime_scope.range = range;
			continue;
		}

		switch (root_node.kind)
		{
			case VAR_DECL:
			case FN_DECL:
			case MACRO_DECL:
			case TYPEDEF_DECL:
			case ALIAS_DECL:
			case ATTRDEF_DECL:
				break;
			default:
				continue;
		}

		cursor::visit(root_node, null, { &sema_on_enter, &sema_on_exit }, ctx);
	}

	ctx.current_module.comptime_scope.range.end = ctx.current_module.range.end;
	ctx.current_module.runtime_scope.range.end = ctx.current_module.range.end;
}

fn void push_rt_scope(SemaContext* ctx, Node* node, ScopeKind kind = BLOCK)
{
	diagnostics::log_debug("[VariablePass]: Pushed new runtime scope for %s at %s", node.kind.description, node.range);

	Scope* new_scope = scope::new(ctx.allocator, node.range, ctx.current_module.runtime_scope, kind);

	ctx.current_module.runtime_scope.children.push(new_scope);
	ctx.current_module.runtime_scope = new_scope;
}

fn void pop_rt_scope(SemaContext* ctx)
{
	if (ctx.current_module.runtime_scope.parent)
	{
		ctx.current_module.runtime_scope = ctx.current_module.runtime_scope.parent;
	}
}

fn void push_ct_scope(SemaContext* ctx, Node* node, ScopeKind kind = BLOCK)
{
	diagnostics::log_debug("[VariablePass]: Pushed new comptime scope for %s at %s", node.kind.description, node.range);

	Scope* new_scope = scope::new(ctx.allocator, node.range, ctx.current_module.comptime_scope, kind);

	ctx.current_module.comptime_scope.children.push(new_scope);
	ctx.current_module.comptime_scope = new_scope;
}

fn void pop_ct_scope(SemaContext* ctx)
{
	if (ctx.current_module.comptime_scope.parent)
	{
		ctx.current_module.comptime_scope = ctx.current_module.comptime_scope.parent;
	}
}

fn ChildVisitResult sema_on_enter(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;

	// LAMBDA_EXPR and ATTRDEF_DECL carry parameters of their own; without a
	// scope each, those parameters land in the enclosing scope and collide
	// with a sibling lambda's or with the surrounding declarations.
	switch (node.kind)
	{
		case IF_STMT:
			IfStmt* if_stmt = node.as(IfStmt);
			if (if_stmt.then_body.kind != COMPOUND_STMT)
			{
				push_rt_scope(ctx, if_stmt.then_body);
				cursor::visit(if_stmt.then_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
				pop_rt_scope(ctx);
			}
			else
			{
				cursor::visit(if_stmt.then_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
			}

			if (if_stmt.else_body)
			{
				if (if_stmt.else_body.kind != COMPOUND_STMT)
				{
					push_rt_scope(ctx, if_stmt.else_body);
					cursor::visit(if_stmt.else_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
					pop_rt_scope(ctx);
				}
				else
				{
					cursor::visit(if_stmt.else_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
				}
			}

			return CONTINUE;

		case CT_IF_STMT:
			CtIfStmt* if_stmt = node.as(CtIfStmt);
			push_ct_scope(ctx, node);
			foreach (child : if_stmt.then_stmts)
			{
				cursor::visit(child, node, { &sema_on_enter, &sema_on_exit }, ctx);
			}
			pop_ct_scope(ctx);
			if (if_stmt.else_stmts.len > 0)
			{
				push_ct_scope(ctx, node);
				foreach (child : if_stmt.else_stmts)
				{
					cursor::visit(child, node, { &sema_on_enter, &sema_on_exit }, ctx);
				}
				pop_ct_scope(ctx);
			}
			return CONTINUE;

		case MACRO_DECL:
		case FN_DECL:
		case ATTRDEF_DECL:
		case CT_DEFINED_EXPR:
			push_rt_scope(ctx, node, FUNCTION);
			push_ct_scope(ctx, node, FUNCTION);

		case TYPE_EXPR:
			TypeExpr* type_expr = node.as(TypeExpr);
			if (type_expr.type_kind == TYPE_FUNCTION)
			{
				push_rt_scope(ctx, node, FUNCTION);
			}

		case LAMBDA_EXPR:
			push_rt_scope(ctx, node, FUNCTION);

		case FOR_STMT:
		case CT_FOR_STMT:
		case FOREACH_STMT:
		case CT_FOREACH_STMT:
		case WHILE_STMT:
		case COMPOUND_STMT:
			push_rt_scope(ctx, node);

		default:
	}

	if VAR: (node.kind == VAR_DECL)
	{
		VarDecl* decl = node.as(VarDecl);

		if (!decl.name) break VAR;

		Scope* scope = decl.var_flags.is_comptime ? ctx.current_module.comptime_scope
			: ctx.current_module.runtime_scope;

		// A name already in view is a redefinition, with one exception: a
		// declaration inside a function may shadow a global. Two globals of the
		// same name still clash with each other if they are in the same module.
		VariableInfo* info = scope::resolve(scope, decl.name.text);
		if (info && (scope.kind == MODULE || info.binding != GLOBAL))
		{
			diagnostics::note(ctx.context, info.node.range, "Previous definition of '%s' was here", info.name);
			diagnostics::error(
				ctx.context,
				decl.range,
				"Variable '%s' is being redefined in the same scope",
				decl.name.text
			);
			break VAR;
		}

		diagnostics::log_debug("[VariablePass]: Added local variable: %s", decl.name.text);

		scope::add_variable(scope, ctx.allocator, decl.name.text, node, binding_of(scope, decl));
	}

	return RECURSE;
}

<*
 A '$name' is a compile-time binding, which stays in view inside a nested
 function. Otherwise the scope it is declared in decides: file scope makes a
 global, anything else - parameters, locals, local constants, static locals -
 makes a runtime binding.

 The scope is what decides rather than 'decl.var_kind', which the parser only
 fills in as VAR_LOCAL when the statement carried an explicit modifier.
*>
fn BindingKind binding_of(Scope* scope, VarDecl* decl) @local
{
	String name = decl.name.text;

	switch
	{
		case scope.kind == MODULE:
		case decl.var_flags.is_const:
		case decl.var_flags.is_static:
		case decl.var_flags.is_thread_local:
			return GLOBAL;

		default:
			return RUNTIME;
	}
}

fn ChildVisitResult sema_on_exit(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;
	switch (node.kind)
	{
		case MACRO_DECL:
		case FN_DECL:
		case CT_DEFINED_EXPR:
			pop_ct_scope(ctx);
			pop_rt_scope(ctx);

		case TYPE_EXPR:
			TypeExpr* type_expr = node.as(TypeExpr);
			if (type_expr.type_kind == TYPE_FUNCTION)
			{
				pop_rt_scope(ctx);
			}

		case LAMBDA_EXPR:
		case ATTRDEF_DECL:
		case FOR_STMT:
		case CT_FOR_STMT:
		case FOREACH_STMT:
		case CT_FOREACH_STMT:
		case WHILE_STMT:
		case COMPOUND_STMT:
			pop_rt_scope(ctx);
		default:
	}

	return CONTINUE;
}
