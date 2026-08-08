module analyzer::sema @feat(SEMA);

import analyzer::core;
import analyzer::cursor;

import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;

struct SemaContext
{
	AnalyzerContext* context;
	Allocator allocator;
	Scope* scope;
	HashMap{String, ImportInfo} imports;
}

fn SemaContext* create(AnalyzerContext* context)
{
	SemaContext* ctx = alloc::new(context.allocator, SemaContext);

	ctx.context = context;
	ctx.allocator = context.allocator;
	ctx.scope = scope::create(ctx.allocator, {});
	ctx.imports.init(context.allocator);

	return ctx;
}

<*
 @require ctx.context != null
*>
fn void analyze_source_file(SemaContext* ctx, SourceFile* sf)
{
	ctx.context.current_source_file = sf;

	ctx.scope = scope::create(ctx.allocator, {});

	analyze_imports(ctx);

	run_variable_pass(ctx);
}

fn void analyze_imports(SemaContext* ctx)
{
	foreach (Node* node : ctx.context.current_source_file.ast.statements)
	{
		if (node.kind != IMPORT_DECL) continue;

		ImportDecl* imp = node.as(ImportDecl);

		foreach (Node* path : imp.paths)
		{
			PathExpr* expr = path.as(PathExpr);
			String full_path = expr.path.text;

			if (!ctx.context.modules.has_key(expr.path.text))
			{
				diagnostics::error(ctx.context, expr.range, "No module '%s' found", expr.path.text);
				continue;
			}

			if (ctx.imports.has_key(expr.path.text))
			{
				ImportInfo existing = ctx.imports.get(expr.path.text)!!;
				diagnostics::note(ctx.context, existing.node.range, "Previous import of '%s' was here", expr.path.text);
				diagnostics::error(ctx.context, expr.range, "Module '%s' is already imported", expr.path.text);
				continue;
			}

			diagnostics::log_debug("[AnalyzeImports]: Added import '%s'", expr.path.text);
			ctx.imports.set(expr.path.text, {expr.path.text, node});

			if (!cursor::has_attribute(imp, NORECURSE, null))
			{
				sz offset = 0;
				while (try idx = full_path[offset..].index_of("::"))
				{
					sz break_pos = offset + idx;
					String parent_prefix = full_path[:break_pos];

					if (!ctx.imports.has_key(parent_prefix) && ctx.context.modules.has_key(parent_prefix))
					{
						diagnostics::log_debug("[AnalyzeImports]: Added recursive import '%s'", parent_prefix);
						ctx.imports.set(parent_prefix, { full_path, node });
					}

					offset = break_pos + 2;
				}
			}

			if (try idx = full_path.rindex_of("::"))
			{
				String leaf = full_path[idx + 2..];
				if (!ctx.imports.has_key(leaf) && ctx.context.modules.has_key(leaf))
				{
					diagnostics::log_debug("[AnalyzeImports]: Added leaf import '%s'", leaf);
					ctx.imports.set(leaf, { full_path, node });
				}
			}
		}
	}
}
