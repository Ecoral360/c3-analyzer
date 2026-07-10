module analyzer::sema @if($feature(SEMA));

import analyzer::core::plog;
import analyzer::core;
import analyzer::cursor;

import std::collections::list;

struct SemaVisitorData @local
{
	SemaContext* ctx;
	TypeRegistry* registry;
}

fn void run_resolution_pass(SemaContext* ctx)
{
	ModuleSection* section = ctx.section;
	Module* mod = section.parent_module;

	if (!section || !mod) return;

	SemaVisitorData build_ctx = {
		.registry = &mod.type_registry,
		.ctx = ctx,
	};

	foreach (root_node : section.section.nodes)
	{
		if (!root_node) continue;
		
		Cursor root_cursor = { root_node };
		cursor::visit(root_cursor, {}, { .on_enter = &on_resolve_enter }, &build_ctx);
	}
}

fn ChildVisitResult on_resolve_enter(Cursor cursor, Cursor parent, void* user_data) @local
{
	SemaVisitorData* data = (SemaVisitorData*)user_data;
	Node* node = cursor.node;

	if (node.kind == TYPE_EXPR)
	{
		ensure_resolved(data.registry, node.as(TypeExpr));
	}

	return RECURSE;
}

fn Type* ensure_resolved(SemaContext* ctx, TypeRegistry* reg, TypeExpr* expr)
{
	if (expr.type) 
	{
		return expr.type;
	}

	expr.type = resolve_type_expr(reg, expr);

	if (!expr.type)
	{
		ctx.error((Node*)expr, "Unknown type: %s", expr.unresolved.name);
	}

	return expr.type;
}

fn Type* resolve_type_expr(TypeRegistry* reg, TypeExpr* expr)
{
	switch (expr.type_kind)
	{
		case TYPE_IDENTIFIER:
		{
			if (Type* p = reg.get_primitive(expr.unresolved.name))
			{
				return p;
			}

			Node* decl = lookup_symbol(expr.unresolved.path, expr.unresolved.name);
			if (!decl) return null;

			return reg.get_type_from_decl(decl);
		}

		case TYPE_POINTER:
		{
			Type* base = resolve_type_expr(reg, expr.modify.base);
			if (!base) return null;
			return reg.get_pointer(base);
		}

		case TYPE_SLICE:
		{
			Type* base = resolve_type_expr(reg, expr.modify.base);
			if (!base) return null;
			return reg.get_slice(base);
		}

		case TYPE_ARRAY:
		{
			Type* base = resolve_type_expr(reg, expr.array.base);
			if (!base) return null;
			
			// If len_expr is null, this is an inferred array [*]
			sz len = (expr.array.len_expr) ? eval_const_int(expr.array.len_expr) : -1;
			return reg.get_array(base, len);
		}

		case TYPE_VECTOR:
		{
			Type* base = resolve_type_expr(reg, expr.array.base);
			sz len = eval_const_int(expr.array.len_expr);
			return reg.get_vector(base, len);
		}

		case TYPE_GENERIC:
		{
			Type* base = resolve_type_expr(reg, expr.generic.base);
			List{Type*} params = {};
			foreach (Node* p : expr.generic.params)
			{
				Type* t = resolve_type_expr(reg, p.as(TypeExpr));
				params.add(t);
			}
			return reg.get_generic(base, params);
		}

		default:
			return null;
	}
}