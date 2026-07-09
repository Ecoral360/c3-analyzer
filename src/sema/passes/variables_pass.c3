module analyzer::sema @if($feature(SEMA));

import analyzer::core::plog;
import analyzer::core;
import analyzer::cursor;

import std::collections::list;

struct SemaLocalContext @local
{
	SemaScope* current_scope;
	ModuleSection* section;
	SemaContext* ctx;
	Allocator arena;
}

fn void run_variable_pass(SemaContext* ctx)
{
	SemaModSection* section = ctx.section;
	SemaMod* mod = section.section.parent_module;

	if (!section || !mod) return;

	String source = section.source_file.source;

	section.scope.range = {
		.start = 0,
		.end = (int)source.len - 1,
	};

	SemaLocalContext build_ctx = {
		.current_scope = &section.scope,
		.section = section,
		.ctx = ctx,
		.arena = &mod.arena
	};

	foreach (root_node : section.section.nodes)
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
		
		build_ctx.current_scope = &section.scope;
		
		Cursor root_cursor = { .node = root_node };
		cursor::visit(root_cursor, {}, { &sema_on_enter, &sema_on_exit }, &build_ctx);
	}
}

fn void push_scope(SemaLocalContext* ctx, Node* node)
{
	plog::debug("SCOPE: Pushed new scope for %s at [%d:%d]", node.kind.description, node.offset.start, node.offset.end);

	SemaScope* new_scope = alloc::new(ctx.arena, SemaScope);
	new_scope.parent = ctx.current_scope;
	new_scope.range = node.offset;
	new_scope.children.init(ctx.arena, 4);
	new_scope.variables.init(ctx.arena, 4);

	ctx.current_scope.children.push(new_scope);
	ctx.current_scope = new_scope;
}

fn void pop_scope(SemaLocalContext* ctx)
{
	if (ctx.current_scope.parent) 
	{
		ctx.current_scope = ctx.current_scope.parent;
	}
}

fn ChildVisitResult sema_on_enter(Cursor cursor, Cursor parent, void* user_data) @local
{
	SemaLocalContext* ctx = (SemaLocalContext*)user_data;
	Node* node = cursor.node;

	while (ctx.current_scope.parent && node.offset.start > ctx.current_scope.range.end)
	{
		ctx.current_scope = ctx.current_scope.parent;
	}
	
	switch (node.kind)
	{
		case IF_STMT:
		{
			IfStmt* if_stmt = node.as(IfStmt);
			if (if_stmt.then_body.kind != COMPOUND_STMT) 
			{
				push_scope(ctx, if_stmt.then_body);
				cursor::visit({ .node = if_stmt.then_body }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
				pop_scope(ctx);
			} 
			else 
			{
				cursor::visit({ .node = if_stmt.then_body }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
			}

			if (if_stmt.else_body)
			{
				if (if_stmt.else_body.kind != COMPOUND_STMT) 
				{
					push_scope(ctx, if_stmt.else_body);
					cursor::visit({ .node = if_stmt.else_body }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
					pop_scope(ctx);
				} 
				else 
				{
					cursor::visit({ .node = if_stmt.else_body }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
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
				cursor::visit({ .node = child }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
			}
			pop_scope(ctx);
			if (if_stmt.else_stmts.len > 0) 
			{
				push_scope(ctx, node);
				foreach (child : if_stmt.else_stmts) 
				{
					cursor::visit({ .node = child }, cursor, { &sema_on_enter, &sema_on_exit }, ctx);
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
	
	if VD: (node.kind == VAR_DECL)
	{
		SemaVar var_entry = {
			.def = node,
			.lifetime = {
				.start = node.offset.start,
				.end = ctx.current_scope.range.end
			},
			.section_id = (sz)ctx.section.id
		};
		VarDecl* vardecl = node.as(VarDecl);
		if (!vardecl.name)
		{
			break VD;
		}
		String name = vardecl.name.text;
		if (try SemaVar existing = ctx.current_scope.variables.get(name))
		{
			ctx.ctx.error(node, "Variable '%s' is being redefined in the same scope", name);
			ctx.ctx.info(existing.def, "Previous definition of '%s' was here", name);
			break VD;
		}
		if (try SemaVar shadowed = find_shadowed_variable(ctx.current_scope, name))
		{
			ctx.ctx.error(node, "Variable '%s' shadows a declaration in an outer scope", name);
			ctx.ctx.info(shadowed.def, "Original declaration of '%s' is here", name);
		}
		plog::debug("REG: Found decl '%s' (kind: %s) at offset %d. Adding to scope at %d", 
				   vardecl.name.text, node.kind.description, node.offset.start, ctx.current_scope.range.start);
		ctx.current_scope.variables.set(name, var_entry);
	}

	return RECURSE;
}

fn ChildVisitResult sema_on_exit(Cursor cursor, Cursor parent, void* user_data) @local
{
	SemaLocalContext* ctx = (SemaLocalContext*)user_data;
	switch (cursor.node.kind)
	{
		case MACRO_DECL:
		case FN_DECL:
		case FOR_STMT:
		case CT_FOR_STMT:
		case FOREACH_STMT:
		case CT_FOREACH_STMT:
		case WHILE_STMT:
		case COMPOUND_STMT:
			if (ctx.current_scope.parent)
			{
				ctx.current_scope = ctx.current_scope.parent; // Popping the stack
			}
		default:
	}

	return CONTINUE;
}

fn SemaVar? find_shadowed_variable(SemaScope* current_scope, String name)
{
	SemaScope* parent = current_scope.parent;

	while (parent)
	{
		if (try SemaVar var_ = parent.variables.get(name))
		{
			return var_;
		}
		parent = parent.parent;
	}
	return NOT_FOUND~;
}