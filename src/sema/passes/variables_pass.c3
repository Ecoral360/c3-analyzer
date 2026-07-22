module analyzer::sema @if($feature(SEMA));

import analyzer::core;
import analyzer::cursor;

import std::collections::list;

fn void run_variable_pass(SemaContext* ctx) => @pool()
{
    SourceFile* sf = ctx.context.current_source_file;
    String[] lines = sf.content.tsplit("\n");

	Range range = {
		.start = {},
		.end = {
		    .line = lines.len - 1,
			.column = lines[^1].len - 1
		},
	};

	foreach (root_node : sf.ast.statements)
	{
		if (!root_node) continue;

		switch (root_node.kind)
		{
			case FN_DECL:
			case MACRO_DECL:
				break;
			default:
				continue;
		}

		cursor::visit(root_node, null, { &sema_on_enter, &sema_on_exit }, ctx);
	}
}

fn void push_scope(SemaContext* ctx, Node* node)
{
	diagnostics::log_debug("[VariablePass]: Pushed new scope for %s at %s", node.kind.description, node.range);

	Scope* new_scope = scope::create(ctx.allocator, node.range, ctx.scope);

	ctx.scope.children.push(new_scope);
	ctx.scope = new_scope;
}

fn void pop_scope(SemaContext* ctx)
{
	if (ctx.scope.parent)
	{
		ctx.scope = ctx.scope.parent;
	}
}

fn ChildVisitResult sema_on_enter(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;

	while (ctx.scope.parent && !ctx.scope.range.contains(node.range.end))
	{
		ctx.scope = ctx.scope.parent;
	}

	switch (node.kind)
	{
		case IF_STMT:
		{
			IfStmt* if_stmt = node.as(IfStmt);
			if (if_stmt.then_body.kind != COMPOUND_STMT)
			{
				push_scope(ctx, if_stmt.then_body);
				cursor::visit(if_stmt.then_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
				pop_scope(ctx);
			}
			else
			{
				cursor::visit(if_stmt.then_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
			}

			if (if_stmt.else_body)
			{
				if (if_stmt.else_body.kind != COMPOUND_STMT)
				{
					push_scope(ctx, if_stmt.else_body);
					cursor::visit(if_stmt.else_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
					pop_scope(ctx);
				}
				else
				{
					cursor::visit(if_stmt.else_body, node, { &sema_on_enter, &sema_on_exit }, ctx);
				}
			}

			return CONTINUE;
		}
		case CT_IF_STMT:
		{
			CtIfStmt* if_stmt = node.as(CtIfStmt);
			push_scope(ctx, node);
			foreach (child : if_stmt.then_stmts)
			{
				cursor::visit(child, node, { &sema_on_enter, &sema_on_exit }, ctx);
			}
			pop_scope(ctx);
			if (if_stmt.else_stmts.len > 0)
			{
				push_scope(ctx, node);
				foreach (child : if_stmt.else_stmts)
				{
					cursor::visit(child, node, { &sema_on_enter, &sema_on_exit }, ctx);
				}
				pop_scope(ctx);
			}
			return CONTINUE;
		}
		case MACRO_DECL:
		case FN_DECL:
		case FOR_STMT:
		case CT_FOR_STMT:
		case FOREACH_STMT:
		case CT_FOREACH_STMT:
		case WHILE_STMT:
		case COMPOUND_STMT:
			push_scope(ctx, node);
			break;
		default: break;
	}

	if VAR: (node.kind == VAR_DECL)
	{
        VarDecl* decl = node.as(VarDecl);

        if (!decl.name) break VAR;

        VariableInfo* info = scope::get_variable(ctx.scope, decl.name.text);
        if (info)
        {
			diagnostics::note(ctx.context, info.node.range, "Previous definition of '%s' was here", info.name);
			diagnostics::error(ctx.context, decl.range, "Variable '%s' is being redefined in the same scope", decl.name.text);
			break VAR;
        }

        diagnostics::log_debug("[VariablePass]: Added local variable: %s", decl.name.text);

        scope::add_variable(ctx.scope, ctx.allocator, decl.name.text, node);
	}

	return RECURSE;
}

fn ChildVisitResult sema_on_exit(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;
	switch (node.kind)
	{
		case MACRO_DECL:
		case FN_DECL:
		case FOR_STMT:
		case CT_FOR_STMT:
		case FOREACH_STMT:
		case CT_FOREACH_STMT:
		case WHILE_STMT:
		case COMPOUND_STMT:
			pop_scope(ctx);
		default:
	}

	return CONTINUE;
}
