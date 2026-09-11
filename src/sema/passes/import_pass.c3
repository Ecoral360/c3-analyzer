module analyzer::sema @feat(SEMA);

import analyzer::core;
import analyzer::cursor;

import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;

fn void run_module_import_pass(SemaContext* ctx)
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

		if (node.kind != IMPORT_DECL) continue;

		ImportDecl* imp = node.as(ImportDecl);

		foreach (Node* path : imp.paths)
		{
			if (path.kind != PATH_EXPR) continue; // stops a crash if the path is invalid

			PathExpr* expr   = path.as(PathExpr);
			String full_path = expr.path.text;

			if (!ctx.context.modules.has_key(expr.path.text))
			{
				diagnostics::error(ctx.context, expr.range, "No module '%s' found", expr.path.text);
				continue;
			}

			if (ctx.current_module.imports.has_key(expr.path.text))
			{
				ImportInfo existing = ctx.current_module.imports.get(expr.path.text)!!;
				diagnostics::note(ctx.context, existing.node.range, "Previous import of '%s' was here", expr.path.text);
				diagnostics::error(ctx.context, expr.range, "Module '%s' is already imported", expr.path.text);
				continue;
			}

			diagnostics::log_debug("[AnalyzeImports]: Added import '%s'", expr.path.text);
			ctx.current_module.imports.set(expr.path.text, { expr.path.text, node });

			if (!cursor::has_attribute(imp, NORECURSE, null))
			{
				sz offset = 0;
				while (try idx = full_path[offset..].index_of("::"))
				{
					sz break_pos         = offset + idx;
					String parent_prefix = full_path[:break_pos];

					if (!ctx.current_module.imports.has_key(
						parent_prefix
					) && ctx.context.modules.has_key(parent_prefix))
					{
						diagnostics::log_debug("[AnalyzeImports]: Added recursive import '%s'", parent_prefix);
						ctx.current_module.imports.set(parent_prefix, { full_path, node });
					}

					offset = break_pos + 2;
				}
			}

			if (try idx = full_path.rindex_of("::"))
			{
				String leaf = full_path[idx + 2..];
				if (!ctx.current_module.imports.has_key(leaf) && ctx.context.modules.has_key(leaf))
				{
					diagnostics::log_debug("[AnalyzeImports]: Added leaf import '%s'", leaf);
					ctx.current_module.imports.set(leaf, { full_path, node });
				}
			}
		}
	}

	if (ctx.current_module)
	{
		SourceFile* sf = ctx.context.current_source_file;
		String[] lines = sf.content.tsplit("\n");
		Location end   = { .line = ((int) lines.len ?: 1) - 1, .column = ((int) lines[^1].len ?: 1) - 1 };
		ctx.current_module.range.end = end;
	}
}
