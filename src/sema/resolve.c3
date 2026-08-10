module analyzer::sema::resolve;

import analyzer::core;

<*
 @require node.kind == IMPORT_DECL
*>
fn Module* resolve_import(SemaContext* ctx, Node* node)
{
	ImportDecl* imp = node.as(ImportDecl);

	foreach (Node* path_node : imp.paths)
	{
		String full_path = path_node.as(PathExpr).path.text; // e.g. "foo::bar::baz"

		if (ctx.context.modules.has_key(full_path))
		{
			Module* mod = ctx.context.modules.get(full_path)!!;

			if (try idx = full_path.rindex_of("::"))
			{
				String leaf_name = full_path[idx + 2..];

			}

			return mod;
		}
	}

	// Module not found
	return null;
}
