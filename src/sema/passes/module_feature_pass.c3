module analyzer::sema @feat(SEMA);

import analyzer::core;
import analyzer::cursor;

import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;

fn void run_module_feature_pass(SemaContext* ctx)
{
	foreach (Node* node : ctx.context.current_source_file.ast.statements)
	{
		if (!node) continue;
		if (node.kind == MODULE_DECL)
		{
			ModuleDecl* mod_decl = node.as(ModuleDecl);
			if (!mod_decl.path || mod_decl.path.kind != PATH_EXPR) continue;

			PathExpr* expr   = mod_decl.path.as(PathExpr);
			String full_path = expr.path.text;

			if (ctx.current_module)
			{
				ctx.current_module.range.end = node.range.start;
			}

			ctx.set_current_module(full_path);

			ctx.current_module.range.start = node.range.start;
			continue;
		}

		switch (node.kind)
		{
			case ATTRDEF_DECL:
			case ATTRIBUTE_DECL:
			case STRUCT_DECL:
			case ENUM_DECL:
			case VAR_DECL:
			case MODULE_DECL:
			case IMPORT_DECL:
			case ALIAS_DECL:
			case TYPEDEF_DECL:
			case FN_DECL:
			case MACRO_DECL:
			case FAULT_DECL:
			case FAULTDEF_DECL:
			case GENERIC_DECL:
			case INTERFACE_DECL:
			case CT_EXPAND_DECL:
				break;

			default:
				continue;
		}

		cursor::visit(node, null, { &sema_on_enter, &sema_on_exit }, ctx);
	}

	if (ctx.current_module)
	{
		SourceFile* sf = ctx.context.current_source_file;
		String[] lines = sf.content.tsplit("\n");
		Location end   = { .line = ((int)lines.len ?: 1) - 1, .column = ((int)lines[^1].len ?: 1) - 1 };
		ctx.current_module.range.end = end;
	}
}

fn ChildVisitResult sema_on_enter(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;
	return CONTINUE;
}

fn ChildVisitResult sema_on_exit(Node* node, Node* parent, void* user_data) @local
{
	SemaContext* ctx = (SemaContext*)user_data;
	return CONTINUE;
}
