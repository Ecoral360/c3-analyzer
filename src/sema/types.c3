module analyzer::sema @if($feature(SEMA));

import analyzer::core;

<*
 @param [&in] ctx
 @param [&in] decl
 @require decl.kind.is_decl()
 @return "Resolved type or null"
*>
fn Type* ensure_type_resolved(SemaContext* ctx, Node* decl)
{
	switch (decl.kind)
	{
		case STRUCT_DECL:
		{
			StructDecl* strukt = decl.as(StructDecl);
		}
		default:
	}

	//if (decl.kind == STRUCT_DECL)
	//{
	//	decl.type = ctx.workspace.registry.create_struct(decl.name, decl);
	//	
	//	decl.type.size = calculate_struct_size(decl);
	//}

	return null;
}