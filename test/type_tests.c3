module type_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core::ast;
import analyzer::core::context;

import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void type_ident()
{
	String source_code = `
		module hello; 
		fn void greet(int foo, Bar baz) {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	io::printn(mod.nodes[1].kind);
	FnDecl* fn_decl = mod.nodes[1].as(FnDecl);
	VarDecl* var_decl = fn_decl.params[1].as(VarDecl);
	TypeExpr* type_expr = var_decl.type.as(TypeExpr);
	test::eq(type_expr.unresolved.name.text, "Bar");
}

fn void global_array_pointer()
{
	String source_code = `
		module hello;
		
		const int[4]* FOO = null;
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.name.text, "FOO");
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
	
	switch (type_data.type_kind)
	{
		case TypeExprKind.TYPE_POINTER:
			test::ne(type_data.modify.base, null);
			TypeExpr* inner_type = type_data.modify.base.as(TypeExpr);

			switch (inner_type.type_kind)
			{
				case TYPE_ARRAY:
					test::ne(inner_type.array.base, null);
					test::ne(inner_type.array.len_expr, null);

					test::eq(inner_type.array.base.as(TypeExpr).type_kind, TypeExprKind.TYPE_IDENTIFIER);
					test::eq(inner_type.array.len_expr.kind, NodeKind.LITERAL_EXPR);
					break;
				default:
					assert(false, "Expected TYPE_ARRAY directly wrapped under pointer modifier");
			}
			break;

		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_POINTER");
	}
}


fn void optional()
{
	String source_code = `
		module hello;
		
		int? foo;
		int*? fooo;
		int[4]? foooo = bar();
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
	test::eq(type_data.optional, true);

	Node* target_node_2 = mod.nodes[2];
	VarDecl* decl_2     = target_node_2.as(VarDecl);
	test::eq(decl_2.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl_2.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data_2 = decl_2.type.as(TypeExpr);
	test::eq(type_data_2.optional, true);

	Node* target_node_3 = mod.nodes[3];
	VarDecl* decl_3     = target_node_3.as(VarDecl);
	test::eq(decl_3.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl_3.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data_3 = decl_3.type.as(TypeExpr);
	test::eq(type_data_3.optional, true);
}

fn void global_inferred_array_pointer()
{
	String source_code = `
		module hello;
		
		const int[*]* FOO = null;
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.name.text, "FOO");
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);

	switch (type_data.type_kind)
	{
		case TYPE_POINTER:
			test::ne(type_data.modify.base, null);
			TypeExpr* inner_type = type_data.modify.base.as(TypeExpr);
			test::eq(inner_type.type_kind, TypeExprKind.TYPE_ARRAY);

			switch (inner_type.type_kind)
			{
				case TYPE_ARRAY:
					test::ne(inner_type.array.base, null);
					test::eq(inner_type.array.base.as(TypeExpr).type_kind, TypeExprKind.TYPE_IDENTIFIER);
					test::eq(inner_type.array.len_expr, null); // null = inferred
					break;
				default:
					assert(false, "Expected TYPE_ARRAY directly wrapped under pointer modifier");
			}
			break;
		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_POINTER");
	}
}

fn void global_generic()
{
	String source_code = `
		module hello;
		
		const List{String} CHANNELS = null;
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	VarDecl* decl = mod.nodes[1].as(VarDecl);
	test::eq(decl.name.text, "CHANNELS");
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);

	switch (type_data.type_kind)
	{
		case TYPE_GENERIC:
			test::ne(type_data.generic.base, null);
			test::eq(type_data.generic.base.as(TypeExpr).type_kind, TypeExprKind.TYPE_IDENTIFIER);
			test::eq(type_data.generic.params.len, 1);

			Node* first_param_node = type_data.generic.params[0];
			test::ne(first_param_node, null);
			test::eq(first_param_node.kind, NodeKind.TYPE_EXPR);

			TypeExpr* param_type = first_param_node.as(TypeExpr);
			switch (param_type.type_kind)
			{
				case TYPE_IDENTIFIER:
					test::eq(param_type.type_kind, TypeExprKind.TYPE_IDENTIFIER);
					break;
				default:
					assert(false, "Expected the first generic parameter argument to be a TYPE_IDENTIFIER");
			}
			break;

		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_GENERIC branch");
	}
}

fn void global_vec()
{
	String source_code = `
		module hello;
		
		const float[<*>] CHANNELS = { 1.0, 2.0 };
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	test::eq(mod.nodes.len(), 2);
	VarDecl* decl = mod.nodes[1].as(VarDecl);
	test::eq(decl.name.text, "CHANNELS");
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);

	switch (type_data.type_kind)
	{
		case TYPE_VECTOR:
			test::ne(type_data.array.base, null);
			test::eq(type_data.array.base.as(TypeExpr).type_kind, TypeExprKind.TYPE_IDENTIFIER);
			test::eq(type_data.array.len_expr, null);
			break;
		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_VECTOR branch");
	}
}

fn void typeof_typefrom()
{
	String source_code = `
		module hello;
		macro void foo()
		{
			$Typefrom($Typeof(value)::inner) $fallback;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	MacroDecl* mac =  mod.nodes[1].as(MacroDecl);
	CompoundStmt* comp = mac.body.as(CompoundStmt);
	VarDecl* vardecl = comp.statements[0].as(VarDecl);
	TypeExpr* type = vardecl.type.as(TypeExpr);
	test::eq(type.type_kind, TypeExprKind.TYPE_TYPEFROM);

	AccessExpr* access = type.expr.as(AccessExpr);

	CallExpr* left = access.left.as(CallExpr);
	TypeExpr* callee = left.callee.as(TypeExpr);
	test::eq(callee.unresolved.name.text, "$Typeof");
	test::eq(callee.type_kind, TypeExprKind.TYPE_IDENTIFIER);

	IdentExpr* member = access.member.as(IdentExpr);
	test::eq(member.ident.text, "inner");
}

