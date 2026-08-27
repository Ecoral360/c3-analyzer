module analyzer::cursor;

import analyzer::core;

enum ChildVisitResult : int
{
	BREAK,    // Terminate the entire walk
	CONTINUE, // Continue to the next sibling
	RECURSE   // Dive into the children of the current node
}

struct VisitorHooks
{
	CursorVisitor on_enter;
	CursorVisitor on_exit; // Called after children are processed
}

alias CursorVisitor = fn ChildVisitResult(Node* cursor, Node* parent, void* user_data);

<*
 @require hooks.on_enter != null
*>
fn bool visit(Node* child, Node* parent, VisitorHooks hooks, void* data, int max_depth = int::max)
{
	return visit_inner(child, parent, hooks, data, max_depth, 0);
}

<*
 @require hooks.on_enter != null
*>
fn bool visit_inner(Node* child, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @local
{
	if (max_depth <= depth) return false;

	ChildVisitResult res = hooks.on_enter(child, parent, data);
	if (res == ChildVisitResult.BREAK) return false; // Stop the whole walk

	if (res == ChildVisitResult.RECURSE)
	{
		// Recursively visit the children of this child
		if (!visit_children(child, hooks, data, max_depth, depth + 1)) return false;
	}

	if (hooks.on_exit)
	{
		hooks.on_exit(child, parent, data);
	}

	return true; // Continue to next sibling
}

<*
 Visit children
 returns false if a break was requested
 @param parent : "The Cursor to visit children on"
 @param hooks : "callback functions that will be invoked for all children of 'parent'"
 @param data : "user data to be passed around"
*>
fn bool visit_children(Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth)
{
	if (!parent.is_valid()) return true;
	Node* node = parent;

	switch
	{
		case node.kind.is_decl():
			if (!visit_decls(node, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		case node.kind.is_stmt():
			if (!visit_stmts(node, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		case node.kind.is_expr():
			if (!visit_exprs(node, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		default:
			unreachable("Unknown Node type");
	}

	return true;
}

fn bool visit_decls(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch (node.kind)
	{
		case MODULE_DECL:
		{
			ModuleDecl* md = node.as(ModuleDecl);
			if (md.path && !visit_inner(md.path, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (attr : md.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (md.generics && !visit_inner(md.generics, parent, hooks, data, max_depth, depth + 1)) return false;
			if (try contract = md.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case IMPORT_DECL:
		{
			ImportDecl* id = node.as(ImportDecl);
			foreach (attr : id.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (path : id.paths)
			{
				if (!visit_inner(path, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case FN_DECL:
		{
			FnDecl* fndecl = node.as(FnDecl);
			if (fndecl.associated_type && !visit_inner(fndecl.associated_type, parent, hooks, data, max_depth, depth + 1)) return false;
			if (fndecl.ret_type && !visit_inner(fndecl.ret_type, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (param : fndecl.params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (fndecl.body && !visit_inner(fndecl.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case STRUCT_DECL:
		{
			StructDecl* structdecl = node.as(StructDecl);
			foreach (inter : structdecl.interfaces)
			{
				if (!visit_inner(inter, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (field : structdecl.fields)
			{
				if (!visit_inner(field, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : structdecl.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (structdecl.next)
			{
				if (!visit_inner(structdecl.next, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (structdecl.type)
			{
				if (!visit_inner(structdecl.type, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case ATTRIBUTE_DECL:
		{
			AttributeDecl* attr = node.as(AttributeDecl);
			if (try val = attr.path.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

			foreach (expr : attr.exprs)
			{
				if (!visit_inner(expr, parent, hooks, data, max_depth, depth + 1)) return false;
			}

			break;
		}
		case ENUM_DECL:
		{
			EnumDecl* ed = node.as(EnumDecl);
			if (ed.backing_type)
			{
				if (!visit_inner(ed.backing_type, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (inter : ed.interfaces)
			{
				if (!visit_inner(inter, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (vari : ed.variants)
			{
				if (!visit_inner(vari, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : ed.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (param : ed.assoc_params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case VAR_DECL:
		{
			VarDecl* vardecl = node.as(VarDecl);
			if (vardecl.type && !visit_inner(vardecl.type, parent, hooks, data, max_depth, depth + 1)) return false;
			if (vardecl.init_expr && !visit_inner(vardecl.init_expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (vardecl.next && !visit_inner(vardecl.next, parent, hooks, data, max_depth, depth + 1)) return false;

			break;
		}
		case INTERFACE_DECL:
		{
			InterfaceDecl* inter = node.as(InterfaceDecl);
			foreach (val : inter.interfaces)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (val : inter.attributes)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (val : inter.methods)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case GENERIC_DECL:
		{
			GenericDecl* gd = node.as(GenericDecl);
			foreach (val : gd.params)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		default:
			break;
	}

	return true;
}

fn bool visit_stmts(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch (node.kind)
	{
		case COMPOUND_STMT:
		{
			CompoundStmt* comp = node.as(CompoundStmt);
			foreach (stmt : comp.statements)
			{
				if (!visit_inner(stmt, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}

		case IF_STMT:
		{
			IfStmt* if_stmt = node.as(IfStmt);

			if (if_stmt.condition && !visit_inner(if_stmt.condition, parent, hooks, data, max_depth, depth + 1)) return false;
			if (if_stmt.then_body && !visit_inner(if_stmt.then_body, parent, hooks, data, max_depth, depth + 1)) return false;
			if (if_stmt.else_body && !visit_inner(if_stmt.else_body, parent, hooks, data, max_depth, depth + 1)) return false;

			break;
		}

		case CT_IF_STMT:
		{
			CtIfStmt* if_stmt = node.as(CtIfStmt);

			if (if_stmt.expr && !visit_inner(if_stmt.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (val : if_stmt.then_stmts)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (val : if_stmt.else_stmts)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}

		case SWITCH_STMT:
		{
			SwitchStmt* swi = node.as(SwitchStmt);
			foreach (val : swi.cases)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (swi.cond && !visit_inner(swi.cond, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}

		case DEFAULT_STMT:
		{
			DefaultStmt* def = node.as(DefaultStmt);
			if (def.body)
			{
				if (!visit_inner(def.body, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}

		case CASE_STMT:
		{
			CaseStmt* cs = node.as(CaseStmt);
			if (cs.expr && !visit_inner(cs.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (cs.to_expr && !visit_inner(cs.to_expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (cs.body && !visit_inner(cs.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}

		case NEXTCASE_STMT:
		{
			NextcaseStmt* next = node.as(NextcaseStmt);
			if (next.expr && !visit_inner(next.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}

		case RETURN_STMT:
		{
			ReturnStmt* ret = node.as(ReturnStmt);
			if (ret.expr && !visit_inner(ret.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}

		case CT_SWITCH_STMT:
		{
			CtSwitchStmt* cts = node.as(CtSwitchStmt);
			if (cts.cond && !visit_inner(cts.cond, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (val : cts.cases)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case EXPR_STMT:
		{
			ExprStmt* exst = node.as(ExprStmt);
			if (exst.expr_stmt)
			{
				if (!visit_inner(exst.expr_stmt, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case FOR_STMT:
		{
			ForStmt* fs = node.as(ForStmt);
			if (try val = fs.init.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (try val = fs.cond.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (try val = fs.incr.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (fs.body && !visit_inner(fs.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case CT_FOR_STMT:
		{
			CtForStmt* fs = node.as(CtForStmt);
			if (try val = fs.init.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

			if (fs.cond && !visit_inner(fs.cond, parent, hooks, data, max_depth, depth + 1)) return false;

			if (try val = fs.incr.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (fs.body && !visit_inner(fs.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case WHILE_STMT:
		{
			WhileStmt* ws = node.as(WhileStmt);
			if (ws.cond && !visit_inner(ws.cond, parent, hooks, data, max_depth, depth + 1)) return false;
			if (ws.body && !visit_inner(ws.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case DO_WHILE_STMT:
		{
			DoWhileStmt* dws = node.as(DoWhileStmt);
			if (try val = dws.cond.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (dws.body && !visit_inner(dws.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case FOREACH_STMT:
		{
			ForeachStmt* st = node.as(ForeachStmt);
			if (st.index && !visit_inner(st.index, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.variable && !visit_inner(st.variable, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.enumeration && !visit_inner(st.enumeration, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case CT_FOREACH_STMT:
		{
			CtForeachStmt* st = node.as(CtForeachStmt);
			if (st.index && !visit_inner(st.index, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.value && !visit_inner(st.value, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case DEFER_STMT:
		{
			DeferStmt* st = node.as(DeferStmt);
			if (st.ident && !visit_inner(st.ident, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case CT_EXPAND_STMT:
		{
			CtExpandStmt* st = node.as(CtExpandStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		default:
			break;
	}

	return true;
}

fn bool visit_exprs(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch(node.kind)
	{
		case ACCESS_EXPR:
		{
			AccessExpr* access = node.as(AccessExpr);
			if (access.left && !visit_inner(access.left, parent, hooks, data, max_depth, depth + 1)) return false;
			if (access.member && !visit_inner(access.member, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}

		case BINARY_EXPR:
		{
			BinaryExpr* bin = node.as(BinaryExpr);
			if (bin.left && !visit_inner(bin.left, parent, hooks, data, max_depth, depth + 1)) return false;
			if (bin.right && !visit_inner(bin.right, parent, hooks, data, max_depth, depth + 1)) return false;
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
					if (te.unresolved.path && !visit_inner(te.unresolved.path, parent, hooks, data, max_depth, depth + 1)) return false;
					break;
				}

				case TYPE_POINTER:
				case TYPE_SLICE:
				{
					if (te.modify.base && !visit_inner(te.modify.base, parent, hooks, data, max_depth, depth + 1)) return false;
					break;
				}

				case TYPE_ARRAY:
				case TYPE_VECTOR:
				{
					if (te.array.base && !visit_inner(te.array.base, parent, hooks, data, max_depth, depth + 1)) return false;
					if (te.array.len_expr && !visit_inner(te.array.len_expr, parent, hooks, data, max_depth, depth + 1)) return false;
					break;
				}

				case TYPE_GENERIC:
				{
					if (te.generic.base && !visit_inner(te.generic.base, parent, hooks, data, max_depth, depth + 1)) return false;
					foreach (param : te.generic.params)
					{
						if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
					}
					break;
				}

				case TYPE_TYPEOF:
				case TYPE_TYPEFROM:
				{
					if (te.expr && !visit_inner(te.expr, parent, hooks, data, max_depth, depth + 1)) return false;
					break;
				}

				case TYPE_FUNCTION:
				{
					if (te.func.ret_type && !visit_inner(te.func.ret_type, parent, hooks, data, max_depth, depth + 1)) return false;
					foreach (param : te.func.params)
					{
						if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
					}
					foreach (attr : te.func.attributes)
					{
						if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
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
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case UNARY_EXPR:
		{
			UnaryExpr* expr = node.as(UnaryExpr);
			if (expr.expr && !visit_inner(expr.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case POST_UNARY_EXPR:
		{
			PostUnaryExpr* expr = node.as(PostUnaryExpr);
			if (expr.expr && !visit_inner(expr.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		case COND_EXPR:
		{
			CondExpr* list = node.as(CondExpr);
			foreach (val : list.exprs)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			break;
		}
		case MACRO_BODY_EXPR:
		{
			MacroBodyExpr* expr = node.as(MacroBodyExpr);
			foreach (val : expr.args)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (expr.body && !visit_inner(expr.body, parent, hooks, data, max_depth, depth + 1)) return false;
			break;
		}
		default:
			break;
	}

	return true;
}
