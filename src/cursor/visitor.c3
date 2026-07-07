module analyzer::cursor;

import analyzer::workspace;
import analyzer::core;

enum ChildVisitResult : int
{
	BREAK,    // Terminate the entire walk
	CONTINUE, // Continue to the next sibling
	RECURSE   // Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data);

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

	Cursor current_context = parent;

	if (!visit_decls(sec, node, parent, visitor, data)) return false;
	if (!visit_stmts(sec, node, parent, visitor, data)) return false;
	if (!visit_exprs(sec, node, parent, visitor, data)) return false;

	return true;
}

fn bool visit_decls(ModuleSection* sec, Node* node, Cursor parent, CursorVisitor visitor, void* data) @private
{
	switch (node.kind)
	{
		case MODULE_DECL:
		{
			ModuleDecl* md = node.as(ModuleDecl);
			if (md.path && !visit({sec, md.path}, parent, visitor, data)) return false;
			foreach (attr : md.attributes)
			{
				if (!visit({sec, attr}, parent, visitor, data)) return false;
			}
			if (md.generics && !visit({sec, md.generics}, parent, visitor, data)) return false;
			if (try contract = md.contract.get())
			{
				if (!visit({sec, contract}, parent, visitor, data)) return false;
			}
			break;
		}
		case IMPORT_DECL:
		{
			ImportDecl* id = node.as(ImportDecl);
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
			FnDecl* fndecl = node.as(FnDecl);
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
			StructDecl* structdecl = node.as(StructDecl);
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
			AttributeDecl* attr = node.as(AttributeDecl);
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
			EnumDecl* ed = node.as(EnumDecl);
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
		case VAR_DECL:
		{
			VarDecl* vardecl = node.as(VarDecl);
			if (vardecl.type && !visit({sec, vardecl.type}, parent, visitor, data)) return false;
			if (vardecl.init_expr && !visit({sec, vardecl.init_expr}, parent, visitor, data)) return false;
			if (vardecl.next && !visit({sec, vardecl.next}, parent, visitor, data)) return false;
			
			break;
		}
		case INTERFACE_DECL:
		{
			InterfaceDecl* inter = node.as(InterfaceDecl);
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
			GenericDecl* gd = node.as(GenericDecl);
			foreach (val : gd.params)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}
		default:
			break;
	}

	return true;
}

fn bool visit_stmts(ModuleSection* sec, Node* node, Cursor parent, CursorVisitor visitor, void* data) @private
{
	switch (node.kind)
	{
		case COMPOUND_STMT:
		{
			CompoundStmt* comp = node.as(CompoundStmt);
			foreach (stmt : comp.statements)
			{
				if (!visit({sec, stmt}, parent, visitor, data)) return false;
			}
			break;
		}

		case IF_STMT:
		{
			IfStmt* if_stmt = node.as(IfStmt);

			if (if_stmt.condition && !visit({sec, if_stmt.condition}, parent, visitor, data)) return false;
			if (if_stmt.then_body && !visit({sec, if_stmt.then_body}, parent, visitor, data)) return false;
			if (if_stmt.else_body && !visit({sec, if_stmt.else_body}, parent, visitor, data)) return false;

			break;
		}

		case CT_IF_STMT:
		{
			CtIfStmt* if_stmt = node.as(CtIfStmt);

			if (if_stmt.expr && !visit({sec, if_stmt.expr}, parent, visitor, data)) return false;
			foreach (val : if_stmt.then_stmts)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			foreach (val : if_stmt.else_stmts)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}

		case SWITCH_STMT:
		{
			SwitchStmt* swi = node.as(SwitchStmt);
			foreach (val : swi.cases)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (swi.cond && !visit({sec, swi.cond}, parent, visitor, data)) return false;
			break;
		}

		case DEFAULT_STMT:
		{
			DefaultStmt* def = node.as(DefaultStmt);
			if (def.body)
			{
				if (!visit({sec, def.body}, parent, visitor, data)) return false;
			}
			break;
		}

		case CASE_STMT:
		{
			CaseStmt* cs = node.as(CaseStmt);
			if (cs.expr && !visit({sec, cs.expr}, parent, visitor, data)) return false;
			if (cs.to_expr && !visit({sec, cs.to_expr}, parent, visitor, data)) return false;
			if (cs.body && !visit({sec, cs.body}, parent, visitor, data)) return false;
			break;
		}

		case NEXTCASE_STMT:
		{
			NextcaseStmt* next = node.as(NextcaseStmt);
			if (next.expr && !visit({sec, next.expr}, parent, visitor, data)) return false;
			break;
		}

		case RETURN_STMT:
		{
			ReturnStmt* ret = node.as(ReturnStmt);
			if (ret.expr && !visit({sec, ret.expr}, parent, visitor, data)) return false;
			break;
		}

		case CT_SWITCH_STMT:
		{
			CtSwitchStmt* cts = node.as(CtSwitchStmt);
			if (cts.cond && !visit({sec, cts.cond}, parent, visitor, data)) return false;
			foreach (val : cts.cases)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}
		case EXPR_STMT:
		{
			ExprStmt* exst = node.as(ExprStmt);
			if (exst.expr_stmt)
			{
				if (!visit({sec, exst.expr_stmt}, parent, visitor, data)) return false;
			}
			break;
		}
		case FOR_STMT:
		{
			ForStmt* fs = node.as(ForStmt);
			if (try val = fs.init.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (try val = fs.cond.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (try val = fs.incr.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (fs.body && !visit({sec, fs.body}, parent, visitor, data)) return false;
			break;
		}
		case CT_FOR_STMT:
		{
			CtForStmt* fs = node.as(CtForStmt);
			if (try val = fs.init.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}

			if (fs.cond && !visit({sec, fs.cond}, parent, visitor, data)) return false;
			
			if (try val = fs.incr.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (fs.body && !visit({sec, fs.body}, parent, visitor, data)) return false;
			break;
		}
		case WHILE_STMT:
		{
			WhileStmt* ws = node.as(WhileStmt);
			if (ws.cond && !visit({sec, ws.cond}, parent, visitor, data)) return false;
			if (ws.body && !visit({sec, ws.body}, parent, visitor, data)) return false;
			break;
		}
		case DO_WHILE_STMT:
		{
			DoWhileStmt* dws = node.as(DoWhileStmt);
			if (try val = dws.cond.get())
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (dws.body && !visit({sec, dws.body}, parent, visitor, data)) return false;
			break;
		}
		case FOREACH_STMT:
		{
			ForeachStmt* st = node.as(ForeachStmt);
			if (st.index && !visit({sec, st.index}, parent, visitor, data)) return false;
			if (st.variable && !visit({sec, st.variable}, parent, visitor, data)) return false;
			if (st.enumeration && !visit({sec, st.enumeration}, parent, visitor, data)) return false;
			if (st.body && !visit({sec, st.body}, parent, visitor, data)) return false;
			break;
		}
		case CT_FOREACH_STMT:
		{
			CtForeachStmt* st = node.as(CtForeachStmt);
			if (st.index && !visit({sec, st.index}, parent, visitor, data)) return false;
			if (st.value && !visit({sec, st.value}, parent, visitor, data)) return false;
			if (st.expr && !visit({sec, st.expr}, parent, visitor, data)) return false;
			if (st.body && !visit({sec, st.body}, parent, visitor, data)) return false;
			break;
		}
		case DEFER_STMT:
		{
			DeferStmt* st = node.as(DeferStmt);
			if (st.ident && !visit({sec, st.ident}, parent, visitor, data)) return false;
			if (st.body && !visit({sec, st.body}, parent, visitor, data)) return false;
			break;
		}
		case CT_EXPAND_STMT:
		{
			CtExpandStmt* st = node.as(CtExpandStmt);
			if (st.expr && !visit({sec, st.expr}, parent, visitor, data)) return false;
			break;
		}
		default:
			break;
	}

	return true;
}

fn bool visit_exprs(ModuleSection* sec, Node* node, Cursor parent, CursorVisitor visitor, void* data) @private
{
	switch(node.kind)
	{
		case ACCESS_EXPR:
		{
			AccessExpr* access = node.as(AccessExpr);
			if (access.left && !visit({sec, access.left}, parent, visitor, data)) return false;
			if (access.member && !visit({sec, access.member}, parent, visitor, data)) return false;
			break;
		}

		case BINARY_EXPR:
		{
			BinaryExpr* bin = node.as(BinaryExpr);
			if (bin.left && !visit({sec, bin.left}, parent, visitor, data)) return false;
			if (bin.right && !visit({sec, bin.right}, parent, visitor, data)) return false;
			break;
		}
		case TYPE_EXPR:
		{
			TypeExpr* te = node.as(TypeExpr);
			switch (te.type_kind)
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
		case EXPR_LIST:
		{
			ExprList* list = node.as(ExprList);
			foreach (val : list.exprs)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}
		case UNARY_EXPR:
		{
			UnaryExpr* expr = node.as(UnaryExpr);
			if (expr.expr && !visit({sec, expr.expr}, parent, visitor, data)) return false;
			break;
		}
		case POST_UNARY_EXPR:
		{
			PostUnaryExpr* expr = node.as(PostUnaryExpr);
			if (expr.expr && !visit({sec, expr.expr}, parent, visitor, data)) return false;
			break;
		}
		case COND_EXPR:
		{
			CondExpr* list = node.as(CondExpr);
			foreach (val : list.exprs)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			break;
		}
		case MACRO_BODY_EXPR:
		{
			MacroBodyExpr* expr = node.as(MacroBodyExpr);
			foreach (val : expr.args)
			{
				if (!visit({sec, val}, parent, visitor, data)) return false;
			}
			if (expr.body && !visit({sec, expr.body}, parent, visitor, data)) return false;
			break;
		}
		default:
			break;
	}

	return true;
}