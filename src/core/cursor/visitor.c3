module analyzer::cursor;

import analyzer::core;

enum ChildVisitResult : int
{
	BREAK, // Terminate the entire walk
	CONTINUE, // Continue to the next sibling
	RECURSE // Dive into the children of the current node
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
		case node.kind == CONTRACT_PARAM:
		case node.kind == ERROR:
			// Leaves outside the decl/stmt/expr classes: a contract parameter
			// only holds identifiers, and an error node holds nothing at all.
			break;
		default:
			unreachable("Unknown Node type");
	}

	return true;
}

<*
 Visit the children of a declaration node.

 Every NodeKind for which 'is_decl' holds is listed, so a new kind added to
 the enum shows up here as a missing case rather than as a silently
 unvisited subtree.
*>
fn bool visit_decls(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch (node.kind)
	{
		case MODULE_DECL:
			ModuleDecl* md = node.as(ModuleDecl);
			if (try contract = md.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (md.path && !visit_inner(md.path, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (attr : md.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (md.generics && !visit_inner(md.generics, parent, hooks, data, max_depth, depth + 1)) return false;

		case IMPORT_DECL:
			ImportDecl* id = node.as(ImportDecl);
			foreach (attr : id.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (path : id.paths)
			{
				if (!visit_inner(path, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case FN_DECL:
			FnDecl* fndecl = node.as(FnDecl);
			if (try contract = fndecl.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (fndecl.associated_type && !visit_inner(
				fndecl.associated_type,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (fndecl.ret_type && !visit_inner(
				fndecl.ret_type,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (fndecl.generics && !visit_inner(
				fndecl.generics,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			foreach (param : fndecl.params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : fndecl.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (fndecl.body && !visit_inner(fndecl.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case MACRO_DECL:
			MacroDecl* macrodecl = node.as(MacroDecl);
			if (try contract = macrodecl.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (try val = macrodecl.associated_type.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (try val = macrodecl.ret_type.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (macrodecl.generics && !visit_inner(
				macrodecl.generics,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			foreach (param : macrodecl.params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (macrodecl.body_params && !visit_inner(
				macrodecl.body_params,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			foreach (attr : macrodecl.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (macrodecl.body && !visit_inner(macrodecl.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case STRUCT_DECL:
			StructDecl* structdecl = node.as(StructDecl);
			if (try contract = structdecl.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (inter : structdecl.interfaces)
			{
				if (!visit_inner(inter, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (structdecl.generics && !visit_inner(
				structdecl.generics,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			foreach (attr : structdecl.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (field : structdecl.fields)
			{
				if (!visit_inner(field, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (structdecl.type)
			{
				if (!visit_inner(structdecl.type, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (structdecl.next)
			{
				if (!visit_inner(structdecl.next, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case ATTRIBUTE_DECL:
			AttributeDecl* attr = node.as(AttributeDecl);
			if (try val = attr.path.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

			foreach (expr : attr.exprs)
			{
				if (!visit_inner(expr, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case ATTRDEF_DECL:
			AttrdefDecl* attr_def = node.as(AttrdefDecl);
			if (try contract = attr_def.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (param : attr_def.params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : attr_def.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : attr_def.defined_attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case CONTRACT_DECL:
			ContractDecl* cd = node.as(ContractDecl);
			foreach (param : cd.params)
			{
				if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (req : cd.requires)
			{
				if (!visit_inner(req, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (ens : cd.ensures)
			{
				if (!visit_inner(ens, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (ret : cd.returns)
			{
				if (!visit_inner(ret, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (cd.return_desc && !visit_inner(cd.return_desc, parent, hooks, data, max_depth, depth + 1)) return false;
			if (cd.deprecated && !visit_inner(cd.deprecated, parent, hooks, data, max_depth, depth + 1)) return false;

		case ENUM_DECL:
			EnumDecl* ed = node.as(EnumDecl);
			if (try contract = ed.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
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

		case VAR_DECL:
			VarDecl* vardecl = node.as(VarDecl);
			if (try contract = vardecl.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (vardecl.type && !visit_inner(vardecl.type, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (attr : vardecl.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (vardecl.init_expr && !visit_inner(
				vardecl.init_expr,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (vardecl.bit_end && !visit_inner(
				vardecl.bit_end,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (vardecl.assoc_values && !visit_inner(
				vardecl.assoc_values,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (vardecl.next && !visit_inner(vardecl.next, parent, hooks, data, max_depth, depth + 1)) return false;

		case ALIAS_DECL:
			AliasDecl* ad = node.as(AliasDecl);
			if (try contract = ad.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (ad.generics && !visit_inner(ad.generics, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (attr : ad.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (ad.target && !visit_inner(ad.target, parent, hooks, data, max_depth, depth + 1)) return false;

		case TYPEDEF_DECL:
			TypedefDecl* td = node.as(TypedefDecl);
			if (try contract = td.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (td.generics && !visit_inner(td.generics, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (inter : td.interfaces)
			{
				if (!visit_inner(inter, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : td.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (td.base_type && !visit_inner(td.base_type, parent, hooks, data, max_depth, depth + 1)) return false;

		case FAULT_DECL:
			FaultDecl* fd = node.as(FaultDecl);
			if (try contract = fd.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (attr : fd.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case FAULTDEF_DECL:
			FaultdefDecl* fd = node.as(FaultdefDecl);
			if (try contract = fd.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (val : fd.faults)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case INTERFACE_DECL:
			InterfaceDecl* inter = node.as(InterfaceDecl);
			if (try contract = inter.contract.get())
			{
				if (!visit_inner(contract, parent, hooks, data, max_depth, depth + 1)) return false;
			}
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

		case GENERIC_DECL:
			GenericDecl* gd = node.as(GenericDecl);
			foreach (val : gd.params)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case BODY_PARAM_DECL:
			BodyParamDecl* bpd = node.as(BodyParamDecl);
			foreach (val : bpd.params)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case CT_EXPAND_DECL:
			CtExpandDecl* ced = node.as(CtExpandDecl);
			if (ced.expr && !visit_inner(ced.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (attr : ced.attributes)
			{
				if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case CT_ASSERT_DECL:
			CtAssertDecl* cad = node.as(CtAssertDecl);
			if (cad.stmt && !visit_inner(cad.stmt, parent, hooks, data, max_depth, depth + 1)) return false;

		default:
			// Not a declaration kind; every declaration kind is listed above.
			break;
	}

	return true;
}

fn bool visit_stmts(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch (node.kind)
	{
		case COMPOUND_STMT:
			CompoundStmt* comp = node.as(CompoundStmt);
			foreach (stmt : comp.statements)
			{
				if (!visit_inner(stmt, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case IF_STMT:
			IfStmt* if_stmt = node.as(IfStmt);

			if (if_stmt.condition && !visit_inner(
				if_stmt.condition,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (if_stmt.then_body && !visit_inner(
				if_stmt.then_body,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;
			if (if_stmt.else_body && !visit_inner(
				if_stmt.else_body,
				parent,
				hooks,
				data,
				max_depth,
				depth + 1
			)) return false;


		case CT_IF_STMT:
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

		case SWITCH_STMT:
			SwitchStmt* swi = node.as(SwitchStmt);
			foreach (val : swi.cases)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (swi.cond && !visit_inner(swi.cond, parent, hooks, data, max_depth, depth + 1)) return false;

		case DEFAULT_STMT:
			DefaultStmt* def = node.as(DefaultStmt);
			if (def.body)
			{
				if (!visit_inner(def.body, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case CASE_STMT:
			CaseStmt* cs = node.as(CaseStmt);
			if (cs.expr && !visit_inner(cs.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (cs.to_expr && !visit_inner(cs.to_expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (cs.body && !visit_inner(cs.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case NEXTCASE_STMT:
			NextcaseStmt* next = node.as(NextcaseStmt);
			if (next.expr && !visit_inner(next.expr, parent, hooks, data, max_depth, depth + 1)) return false;

		case RETURN_STMT:
			ReturnStmt* ret = node.as(ReturnStmt);
			if (ret.expr && !visit_inner(ret.expr, parent, hooks, data, max_depth, depth + 1)) return false;

		case CT_SWITCH_STMT:
			CtSwitchStmt* cts = node.as(CtSwitchStmt);
			if (cts.cond && !visit_inner(cts.cond, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (val : cts.cases)
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case EXPR_STMT:
			ExprStmt* exst = node.as(ExprStmt);
			if (exst.expr_stmt)
			{
				if (!visit_inner(exst.expr_stmt, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case FOR_STMT:
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

		case CT_FOR_STMT:
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

		case WHILE_STMT:
			WhileStmt* ws = node.as(WhileStmt);
			if (ws.cond && !visit_inner(ws.cond, parent, hooks, data, max_depth, depth + 1)) return false;
			if (ws.body && !visit_inner(ws.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case DO_WHILE_STMT:
			DoWhileStmt* dws = node.as(DoWhileStmt);
			if (try val = dws.cond.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			if (dws.body && !visit_inner(dws.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case FOREACH_STMT:
			ForeachStmt* st = node.as(ForeachStmt);
			if (st.index && !visit_inner(st.index, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.variable && !visit_inner(st.variable, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.enumeration && !visit_inner(st.enumeration, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case CT_FOREACH_STMT:
			CtForeachStmt* st = node.as(CtForeachStmt);
			if (st.index && !visit_inner(st.index, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.value && !visit_inner(st.value, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case DEFER_STMT:
			DeferStmt* st = node.as(DeferStmt);
			if (st.ident && !visit_inner(st.ident, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.body && !visit_inner(st.body, parent, hooks, data, max_depth, depth + 1)) return false;

		case CT_EXPAND_STMT:
			CtExpandStmt* st = node.as(CtExpandStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;

		case CT_ASSERT_STMT:
			CtAssertStmt* st = node.as(CtAssertStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (try val = st.msg_expr.get())
			{
				if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
			}
			foreach (arg : st.args)
			{
				if (!visit_inner(arg, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case ASSERT_STMT:
			AssertStmt* st = node.as(AssertStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;
			if (st.message && !visit_inner(st.message, parent, hooks, data, max_depth, depth + 1)) return false;
			foreach (arg : st.args)
			{
				if (!visit_inner(arg, parent, hooks, data, max_depth, depth + 1)) return false;
			}

		case CT_ERROR_STMT:
			CtErrorStmt* st = node.as(CtErrorStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;

		case CT_ECHO_STMT:
			CtEchoStmt* st = node.as(CtEchoStmt);
			if (st.expr && !visit_inner(st.expr, parent, hooks, data, max_depth, depth + 1)) return false;

		// Leaf statements: everything they carry is a label or a flag, never a child node.
		case CONTINUE_BREAK_STMT:
		case NOP_STMT:
		case ASM_BLOCK_STMT:
			break;
		default:
			// Not a statement kind; every statement kind is listed above.
			break;
	}

	return true;
}

fn bool visit_exprs(Node* node, Node* parent, VisitorHooks hooks, void* data, int max_depth, int depth) @private
{
	switch (node.kind)
	{
		case ACCESS_EXPR:

			{
				AccessExpr* access = node.as(AccessExpr);
				if (access.left && !visit_inner(access.left, parent, hooks, data, max_depth, depth + 1)) return false;
				if (access.member && !visit_inner(
					access.member,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
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
							if (te.unresolved.path && !visit_inner(
								te.unresolved.path,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							break;
						}

					case TYPE_POINTER:
					case TYPE_SLICE:

						{
							if (te.modify.base && !visit_inner(
								te.modify.base,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							break;
						}

					case TYPE_ARRAY:
					case TYPE_VECTOR:

						{
							if (te.array.base && !visit_inner(
								te.array.base,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							if (te.array.len_expr && !visit_inner(
								te.array.len_expr,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							break;
						}

					case TYPE_GENERIC:

						{
							if (te.generic.base && !visit_inner(
								te.generic.base,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							foreach (param : te.generic.params)
							{
								if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
							}
							break;
						}

					case TYPE_TYPEOF:
					case TYPE_TYPEFROM:

						{
							if (te.expr && !visit_inner(
								te.expr,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
							break;
						}

					case TYPE_FUNCTION:

						{
							if (te.func.ret_type && !visit_inner(
								te.func.ret_type,
								parent,
								hooks,
								data,
								max_depth,
								depth + 1
							)) return false;
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
		case CALL_EXPR:

			{
				CallExpr* call = node.as(CallExpr);
				if (call.callee && !visit_inner(call.callee, parent, hooks, data, max_depth, depth + 1)) return false;
				foreach (arg : call.args)
				{
					if (!visit_inner(arg, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				if (call.macro_body_expr && !visit_inner(
					(Node*)call.macro_body_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				foreach (attr : call.attributes)
				{
					if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				break;
			}
		case IDENT_EXPR:

			{
				IdentExpr* ident = node.as(IdentExpr);
				if (ident.path_expr && !visit_inner(
					ident.path_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case GENERIC_IDENT_EXPR:

			{
				GenericIdentExpr* gie = node.as(GenericIdentExpr);
				foreach (val : gie.exprs)
				{
					if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				break;
			}
		case CONTRACT_EXPR:

			{
				ContractExpr* ce = node.as(ContractExpr);
				if (ce.exprs && !visit_inner(ce.exprs, parent, hooks, data, max_depth, depth + 1)) return false;
				if (ce.expr_string && !visit_inner(
					ce.expr_string,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case TRY_EXPR:

			{
				TryExpr* te = node.as(TryExpr);
				if (te.type && !visit_inner(te.type, parent, hooks, data, max_depth, depth + 1)) return false;
				if (te.variable && !visit_inner(te.variable, parent, hooks, data, max_depth, depth + 1)) return false;
				if (te.init && !visit_inner(te.init, parent, hooks, data, max_depth, depth + 1)) return false;
				if (te.next && !visit_inner(te.next, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case CATCH_EXPR:

			{
				CatchExpr* ce = node.as(CatchExpr);
				if (ce.type && !visit_inner(ce.type, parent, hooks, data, max_depth, depth + 1)) return false;
				if (ce.variable && !visit_inner(ce.variable, parent, hooks, data, max_depth, depth + 1)) return false;
				foreach (val : ce.exprs)
				{
					if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				break;
			}
		case TERNARY_EXPR:

			{
				TernaryExpr* te = node.as(TernaryExpr);
				if (te.cond && !visit_inner(te.cond, parent, hooks, data, max_depth, depth + 1)) return false;
				if (te.then_expr && !visit_inner(te.then_expr, parent, hooks, data, max_depth, depth + 1)) return false;
				if (te.else_expr && !visit_inner(te.else_expr, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case LAMBDA_EXPR:

			{
				LambdaExpr* le = node.as(LambdaExpr);
				if (le.return_type && !visit_inner(
					le.return_type,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				foreach (param : le.params)
				{
					if (!visit_inner(param, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				foreach (attr : le.attributes)
				{
					if (!visit_inner(attr, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				if (le.body && !visit_inner(le.body, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case CAST_EXPR:

			{
				CastExpr* ce = node.as(CastExpr);
				if (ce.operand && !visit_inner(ce.operand, parent, hooks, data, max_depth, depth + 1)) return false;
				if (ce.inner && !visit_inner(ce.inner, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case GROUP_EXPR:

			{
				GroupExpr* ge = node.as(GroupExpr);
				if (ge.inner && !visit_inner(ge.inner, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case SPLAT_EXPR:

			{
				SplatExpr* se = node.as(SplatExpr);
				if (se.inner && !visit_inner(se.inner, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case VASPLAT_EXPR:

			{
				VasplatExpr* ve = node.as(VasplatExpr);
				if (ve.range_expr && !visit_inner(
					ve.range_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case VAARG_EXPR:

			{
				VaargExpr* ve = node.as(VaargExpr);
				if (ve.expr && !visit_inner(ve.expr, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case NAMED_ARG_EXPR:

			{
				NamedArgExpr* nae = node.as(NamedArgExpr);
				if (nae.value && !visit_inner(nae.value, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case EVAL_NAMED_ARG_EXPR:

			{
				EvalNamedArgExpr* enae = node.as(EvalNamedArgExpr);
				if (enae.name && !visit_inner(enae.name, parent, hooks, data, max_depth, depth + 1)) return false;
				if (enae.value && !visit_inner(enae.value, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case CT_EVAL_EXPR:

			{
				CtEvalExpr* cee = node.as(CtEvalExpr);
				if (cee.inner_expr && !visit_inner(
					cee.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case CT_DEFINED_EXPR:

			{
				CtDefinedExpr* cde = node.as(CtDefinedExpr);
				foreach (val : cde.expr_list)
				{
					if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				break;
			}
		case CT_FEATURE_EXPR:

			{
				CtFeatureExpr* cfe = node.as(CtFeatureExpr);
				if (cfe.inner_expr && !visit_inner(
					cfe.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case CT_STRINGIFY_EXPR:

			{
				CtStringifyExpr* cse = node.as(CtStringifyExpr);
				if (cse.inner_expr && !visit_inner(
					cse.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case CT_REFLECT_EXPR:

			{
				CtReflectExpr* cre = node.as(CtReflectExpr);
				if (cre.inner_expr && !visit_inner(
					cre.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case LENGTHOF_EXPR:

			{
				LengthofExpr* le = node.as(LengthofExpr);
				if (le.inner_expr && !visit_inner(
					le.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case OPTIONAL_EXPR:

			{
				OptionalExpr* oe = node.as(OptionalExpr);
				if (oe.inner_expr && !visit_inner(
					oe.inner_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case MAYBE_DEREF_EXPR:

			{
				MaybeDerefExpr* mde = node.as(MaybeDerefExpr);
				if (mde.left && !visit_inner(mde.left, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case RANGE_EXPR:

			{
				RangeExpr* re = node.as(RangeExpr);
				if (re.start && !visit_inner(re.start, parent, hooks, data, max_depth, depth + 1)) return false;
				if (re.end && !visit_inner(re.end, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case DESIGNATOR_EXPR:

			{
				DesignatorExpr* de = node.as(DesignatorExpr);
				if (de.path && !visit_inner(de.path, parent, hooks, data, max_depth, depth + 1)) return false;
				// 'field' and 'range' share the same union slot, so one visit covers both forms.
				if (de.data.field && !visit_inner(
					de.data.field,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
		case DESIGNATED_INITIALIZER_EXPR:

			{
				DesignatedInitializerExpr* die = node.as(DesignatedInitializerExpr);
				if (die.path && !visit_inner(die.path, parent, hooks, data, max_depth, depth + 1)) return false;
				if (die.value && !visit_inner(die.value, parent, hooks, data, max_depth, depth + 1)) return false;
				break;
			}
		case INITIALIZER_LIST_EXPR:

			{
				InitializerListExpr* ile = node.as(InitializerListExpr);
				foreach (val : ile.exprs)
				{
					if (!visit_inner(val, parent, hooks, data, max_depth, depth + 1)) return false;
				}
				break;
			}
		case COMPOUND_LITERAL_EXPR:

			{
				CompoundLiteralExpr* cle = node.as(CompoundLiteralExpr);
				if (cle.type_expr && !visit_inner(
					cle.type_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				if (cle.initializer_expr && !visit_inner(
					cle.initializer_expr,
					parent,
					hooks,
					data,
					max_depth,
					depth + 1
				)) return false;
				break;
			}
			// Leaf expressions: an identifier, a literal or a keyword, with no child nodes.
		case PATH_EXPR:
		case LITERAL_EXPR:
		case BUILTIN_EXPR:
		case COMPILER_CONST_EXPR:
		case OVERLOAD_EXPR:
			break;
		default:
			// Not an expression kind; every expression kind is listed above.
			break;
	}

	return true;
}
