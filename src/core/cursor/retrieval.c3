<*
 Cursor is basically a pointer to a specific node
 with the ability to walk and get out data from it.

 represents some Node in the abstract syntax tree for a module
*>
module analyzer::cursor;
import analyzer::core;
import analyzer::sema;

import std::collections::list;

import std::io;

fn NodeEntry node(Ast* ast, Location location)
{
	FindPathContext ctx = {
		.target = { location, location },
		.current_path = { },
	};

	foreach (node : ast.statements)
	{
		Node* root_cursor = node;

		if (!visit(root_cursor, { }, { .on_enter = &find_path_callback }, &ctx))
		{
			break;
		}
	}

	return { .node = ctx.best_match, .path = (NodePath)ctx.current_path.to_tarray() };
}

fn NodePoint? point(Ast* ast, Location location)
{
	FindPathContext ctx = {
		.target = { location, location },
		.current_path = { },
	};

	foreach (node : ast.statements)
	{
		Node* root_cursor = node;

		if (!visit(root_cursor, { }, { .on_enter = &find_path_callback }, &ctx))
		{
			break;
		}
	}

	if (ctx.current_path.is_empty())
	{
		return NOT_FOUND~;
	}

	return { (NodePath)ctx.current_path.to_tarray(), location.column };
}

fn NodePath? path(Ast* ast, Location location)
{
	return point(ast, location).path;
}

struct FindPathContext
{
	Range target;
	List{sz} current_path;
	sz current_idx;
	Node* best_match;
	int best_span;
}

fn ChildVisitResult find_path_callback(Node* cursor, Node* parent, void* user_data) @local
{
	FindPathContext* ctx = (FindPathContext*)user_data;

	if (!cursor.is_valid())
	{
		ctx.current_idx += 1;
		return CONTINUE;
	}

	Node* node = cursor;

	if (node.range.contains_range(ctx.target))
	{
		ctx.current_path.push(ctx.current_idx);
		ctx.current_idx = 0;

		int current_span = (node.range.end.line - node.range.start.line) * 1000
			+ (node.range.end.column - node.range.start.column);

		if (ctx.best_match == null || current_span <= ctx.best_span)
		{
			ctx.best_match = cursor;
			ctx.best_span = current_span;
		}

		return RECURSE;
	}

	ctx.current_idx += 1;
	return CONTINUE;
}
