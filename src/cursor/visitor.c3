module analyzer::cursor;

import analyzer::workspace;
import analyzer::core;

enum ChildVisitResult : int
{
	BREAK,    // Terminate the entire walk
	CONTINUE, // Continue to the next sibling
	RECURSE   // Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data, args...);

// Helper to visit a node if it's valid
fn bool visit(Cursor child, Cursor parent, CursorVisitor visitor, void* data)
{
	ChildVisitResult res = visitor(child, parent, data);
	if (res == ChildVisitResult.BREAK) return false; // Stop the whole walk

	if (res == ChildVisitResult.RECURSE)
	{
		// Recursively visit the children of this child
		if (!visit_children(child, visitor, data)) return false;
	}

	return true; // Continue to next sibling
}

<*
 Visit children
 returns false if a break was requested
 @require parent.section != null
 @param parent : "The Cursor to visit children on"
 @param visitor : "visitor function that will be invoked for all children of 'parent'"
 @param data : "user data to be passed around"
*>
fn bool visit_children(Cursor parent, CursorVisitor visitor, void* data)
{
	if (!parent.is_valid()) return true;
	Node* node = parent.node;
	ModuleSection* sec = parent.section;

	// TODO:
 
	switch (node.kind)
	{
		case MODULE_DECL:
		{
			ModuleDecl* md = node.as(MODULE_DECL);
			if (md.path && visit({sec, md.path}, parent, visitor, data)) return false;
			foreach (attr : md.attributes)
			{
				if (!visit({sec, attr}, parent, visitor, data)) return false;
			}
			if (md.generics && visit({sec, md.generics}, parent, visitor, data)) return false;
			if (try contract = md.contract.get())
			{
				if (!visit({sec, contract}, parent, visitor, data)) return false;
			}
			break;
		}
		case IMPORT_DECL:
		{
			ImportDecl* id = node.as(IMPORT_DECL);
			foreach (attr : id.attributes)
			{
				if (!visit({sec, attr}, parent, visitor, data)) return false;
			}
			foreach (path : id.paths)
			{
				if (!visit({sec, path}, parent, visitor, data)) return false;
			}
			break;
		}
		case FN_DECL:
		{
			FnDecl* fndecl = node.as(FN_DECL);
			if (fndecl.associated_type && !visit({sec, fndecl.associated_type}, parent, visitor, data)) return false;
			if (fndecl.ret_type && !visit({sec, fndecl.ret_type}, parent, visitor, data)) return false;
			foreach (param : fndecl.params)
			{
				if (!visit({sec, param}, parent, visitor, data)) return false;
			}
			if (fndecl.body && !visit({sec, fndecl.body}, parent, visitor, data)) return false;
			break;
		}

		case STRUCT_DECL:
		{
			StructDecl* structdecl = node.as(STRUCT_DECL);
			foreach (inter : structdecl.interfaces)
			{
				if (!visit({sec, inter}, parent, visitor, data)) return false;
			}
			foreach (field : structdecl.fields)
			{
				if (!visit({sec, field}, parent, visitor, data)) return false;
			}
			foreach (attr : structdecl.attributes)
			{
				if (!visit({sec, attr}, parent, visitor, data)) return false;
			}
			if (structdecl.next)
			{
				if (!visit({sec, structdecl.next}, parent, visitor, data)) return false;
			}
			if (structdecl.type)
			{
				if (!visit({sec, structdecl.type}, parent, visitor, data)) return false;
			}
			break;
		}

		case ATTRIBUTE_DECL:
		{
			AttributeDecl* attr = node.as(ATTRIBUTE_DECL);
			if (try val = attr.path.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			
			foreach (expr : attr.exprs)
			{
				if (!visit({sec, expr}, parent, visitor, data)) return false;
			}

			break;
		}

		case ENUM_DECL:
		{
			EnumDecl* ed = node.as(ENUM_DECL);
			if (ed.backing_type)
			{
				if (!visit({sec, ed.backing_type}, parent, visitor, data)) return false;
			}
			foreach (inter : ed.interfaces)
			{
				if (!visit({sec, inter}, parent, visitor, data)) return false;
			}
			foreach (vari : ed.variants)
			{
				if (!visit({sec, vari}, parent, visitor, data)) return false;
			}
			foreach (attr : ed.attributes)
			{
				if (!visit({sec, attr}, parent, visitor, data)) return false;
			}
			foreach (param : ed.assoc_params)
			{
				if (!visit({sec, param}, parent, visitor, data)) return false;
			}
			break;
		}
		
		case COMPOUND_STMT:
		{
			CompoundStmt* comp = node.as(COMPOUND_STMT);
			foreach (stmt : comp.statements)
			{
				if (!visit({sec, stmt}, parent, visitor, data)) return false;
			}
			break;
		}

		case EXPR_STMT:
		{
			ExprStmt* expr = node.as(EXPR_STMT);
			if (expr.expr_stmt && !visit({sec, expr.expr_stmt}, parent, visitor, data)) return false;
			break;
		}

		case ACCESS_EXPR:
		{
			AccessExpr* access = node.as(ACCESS_EXPR);
			if (access.left && !visit({sec, access.left}, parent, visitor, data)) return false;
			if (access.member && !visit({sec, access.member}, parent, visitor, data)) return false;
			break;
		}

		case BINARY_EXPR:
		{
			BinaryExpr* bin = node.as(BINARY_EXPR);
			if (bin.left && !visit({sec, bin.left}, parent, visitor, data)) return false;
			if (bin.right && !visit({sec, bin.right}, parent, visitor, data)) return false;
			break;
		}

		case VAR_DECL:
		{
			VarDecl* vardecl = node.as(VAR_DECL);
			if (vardecl.type && !visit({sec, vardecl.type}, parent, visitor, data)) return false;
			if (vardecl.init_expr && !visit({sec, vardecl.init_expr}, parent, visitor, data)) return false;
			if (vardecl.next && !visit({sec, vardecl.next}, parent, visitor, data)) return false;

			break;
		}

		case RETURN_STMT:
		{
			ReturnStmt* stmt = node.as(RETURN_STMT);
			if (stmt.expr && !visit({sec, stmt.expr}, parent, visitor, data)) return false;
			break;
		}

		case TYPE_EXPR:
		{
			TypeExpr* te = node.as(TYPE_EXPR);
			switch (te.kind)
			{
				case TYPE_IDENTIFIER:
				{
					// Optional module path node (e.g., the 'foo::' in 'foo::MyStruct')
					if (te.unresolved.path && !visit({sec, te.unresolved.path}, parent, visitor, data)) return false;
					break;
				}

				case TYPE_POINTER:
				case TYPE_SLICE:
				{
					if (te.modify.base && !visit({sec, te.modify.base}, parent, visitor, data)) return false;
					break;
				}

				case TYPE_ARRAY:
				case TYPE_VECTOR:
				{
					if (te.array.base && !visit({sec, te.array.base}, parent, visitor, data)) return false;
					if (te.array.len_expr && !visit({sec, te.array.len_expr}, parent, visitor, data)) return false;
					break;
				}

				case TYPE_GENERIC:
				{
					if (te.generic.base && !visit({sec, te.generic.base}, parent, visitor, data)) return false;
					foreach (param : te.generic.params)
					{
						if (!visit({sec, param}, parent, visitor, data)) return false;
					}
					break;
				}

				case TYPE_TYPEOF:
				case TYPE_TYPEFROM:
				{
					if (te.expr && !visit({sec, te.expr}, parent, visitor, data)) return false;
					break;
				}

				case TYPE_FUNCTION:
				{
					if (te.func.ret_type && !visit({sec, te.func.ret_type}, parent, visitor, data)) return false;
					foreach (param : te.func.params)
					{
						if (!visit({sec, param}, parent, visitor, data)) return false;
					}
					foreach (attr : te.func.attributes)
					{
						if (!visit({sec, attr}, parent, visitor, data)) return false;
					}
					break;
				}
			}
			break;
		}

		case INTERFACE_DECL:
		{
			InterfaceDecl* inter = node.as(INTERFACE_DECL);
			foreach (val : inter.interfaces)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			foreach (val : inter.attributes)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			foreach (val : inter.methods)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}

		case GENERIC_DECL:
		{
			GenericDecl* gd = node.as(GENERIC_DECL);
			foreach (val : gd.params)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
		}
		default:
			break;
	}

	return true;
}
