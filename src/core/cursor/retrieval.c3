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

fn Node* node(Ast* ast, Location location)
{
	return find_at(ast.statements.array_view(), { location, location });
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
		return RECURSE;
	}

	ctx.current_idx += 1;
	return CONTINUE;
}
