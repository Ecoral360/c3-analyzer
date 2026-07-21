module analyzer::sema @if($feature(SEMA));

import analyzer::core;

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

			if (ctx.imports.has_key(expr.path.text))
			{
				ImportInfo existing = ctx.imports.get(expr.path.text)!!;
				diagnostics::note(ctx.context, existing.node.range, "Previous import of '%s' was here", expr.path.text);
				diagnostics::error(ctx.context, expr.range, "Module '%s' is already imported", expr.path.text);
				continue;
			}

			if (!ctx.context.modules.has_key(expr.path.text))
			{
				diagnostics::error(ctx.context, expr.range, "No module '%s' found", expr.path.text);
				continue;
			}

			diagnostics::log_debug("[AnalyzeImports]: Added import '%s'", expr.path.text);
			ctx.imports.set(expr.path.text, {expr.path.text, node});
		}
	}
}
