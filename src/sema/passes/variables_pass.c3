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

fn ChildVisitResult sema_on_enter(Cursor cursor, Cursor parent, void* user_data) @local
{
	SemaLocalContext* ctx = (SemaLocalContext*)user_data;
	Node* node = cursor.node;

	while (ctx.current_scope.parent && node.offset.start > ctx.current_scope.range.end)
	{
		ctx.current_scope = ctx.current_scope.parent;
	}
	
	if (node.kind == FN_DECL)
	{
		plog::debug("SCOPE: Pushed new scope for %s at [%d:%d]", "FUNCTION", node.offset.start, node.offset.end);
		SemaScope* func_scope = alloc::new(ctx.arena, SemaScope);
		func_scope.parent = ctx.current_scope;
		func_scope.range = node.offset;
		func_scope.children.init(ctx.arena, 4);
		func_scope.variables.init(ctx.arena, 4);
		
		ctx.current_scope.children.push(func_scope);
		ctx.current_scope = func_scope; 
	}

	if (node.kind == COMPOUND_STMT)
	{
		plog::debug("SCOPE: Pushed new scope for %s at [%d:%d]", "COMPOUND", node.offset.start, node.offset.end);
		SemaScope* sub_scope = alloc::new(ctx.arena, SemaScope);
		sub_scope.parent = ctx.current_scope;
		sub_scope.range = node.offset;
		sub_scope.children.init(ctx.arena, 4);
		sub_scope.variables.init(ctx.arena, 4);
		ctx.current_scope.children.push(sub_scope);
		ctx.current_scope = sub_scope; // Pushing the stack
	}
	
	if VD: (node.kind == VAR_DECL)
	{
		SemaVar var_entry = {
			.def = node,
			.lifetime = {
				.start = node.offset.start,
				.end = ctx.current_scope.range.end
			}
		};
		VarDecl* vardecl = node.as(VarDecl);
		if (!vardecl.name)
		{
			break VD;
		}
		plog::debug("REG: Found decl '%s' (kind: %s) at offset %d. Adding to scope at %d", 
				   vardecl.name.text, node.kind.description, node.offset.start, ctx.current_scope.range.start);
		String name = vardecl.name.text;
		ctx.current_scope.variables.set(name, var_entry);
	}

	return RECURSE;
}

fn ChildVisitResult sema_on_exit(Cursor cursor, Cursor parent, void* user_data) @local
{
	SemaLocalContext* ctx = (SemaLocalContext*)user_data;
	
	switch (cursor.node.kind)
	{
		case COMPOUND_STMT:
		case FN_DECL:
		case MACRO_DECL:
			if (ctx.current_scope.parent)
			{
				ctx.current_scope = ctx.current_scope.parent; // Popping the stack
			}
		default:
	}

	return CONTINUE;
}