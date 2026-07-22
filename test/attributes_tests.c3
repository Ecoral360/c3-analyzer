module attributes_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core;
import analyzer::sema;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void module_private_test_weak_if()
{
	String source_code = `
		module hello @private @test @weak @if(1 == 1 && 2 == 2);
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	ModuleDecl* module_node = mod.module_decls[0];
	test::eq(module_node.visibility, Visibility.PRIVATE);

	test::eq(module_node.attributes.len, 4);

	// @private
	test::eq(parser_tests::@attr(module_node, 0).attribute_kind, AttributeKind.PRIVATE);
	// @weak
	test::eq(parser_tests::@attr(module_node, 1).attribute_kind, AttributeKind.TEST);
	// @test
	test::eq(parser_tests::@attr(module_node, 2).attribute_kind, AttributeKind.WEAK);

	// @if(1 == 1 && 2 == 2)
	AttributeDecl* attr = parser_tests::@attr(module_node, 3);
	test::eq(attr.attribute_kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);

	// (1 == 1 && 2 == 2)
	BinaryExpr* and_expr = attr.exprs[0].as(BinaryExpr);
	test::eq(and_expr.op, OperatorKind.OP_AND);

	// 1 == 1
	BinaryExpr* left_eq_expr = and_expr.left.as(BinaryExpr);
	test::eq(left_eq_expr.left.as(LiteralExpr).integer, 1u);
	test::eq(left_eq_expr.right.as(LiteralExpr).integer, 1u);

	// 2 == 2
	BinaryExpr* right_eq_expr = and_expr.right.as(BinaryExpr);
	test::eq(right_eq_expr.left.as(LiteralExpr).integer, 2u);
	test::eq(right_eq_expr.right.as(LiteralExpr).integer, 2u);
}


fn void module_tag_if()
{
	String source_code = `
		module hello @tag("my_tag", "my_value") @if($feature(MY_FEATURE));
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	ModuleDecl* module_decl = mod.module_decls[0];
	test::eq(module_decl.visibility, Visibility.PUBLIC);
	test::eq(module_decl.attributes.len, 2);

	// @tag("my_tag", "my_value")
	AttributeDecl* attr = parser_tests::@attr(module_decl, 0);
	test::eq(attr.attribute_kind, AttributeKind.TAG);
	test::eq(attr.exprs.len, 2);
	// "my_tag"
	LiteralExpr* lit_expr = attr.exprs[0].as(LiteralExpr);
	test::eq(lit_expr.literal_kind, LiteralKind.STRING_LITERAL);
	test::eq(lit_expr.string, "my_tag");
	// "my_value"
	lit_expr = attr.exprs[1].as(LiteralExpr);
	test::eq(lit_expr.literal_kind, LiteralKind.STRING_LITERAL);
	test::eq(lit_expr.string, "my_value");
	// end @tag()

	// @if($feature(MY_FEATURE))
	attr = parser_tests::@attr(module_decl, 1);
	test::eq(attr.attribute_kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);
	CtFeatureExpr* feat          = attr.exprs[0].as(CtFeatureExpr);
	IdentExpr* callee_ident_expr = feat.inner_expr.as(IdentExpr);
	test::eq(callee_ident_expr.ident.text, "MY_FEATURE");
	// end @if()
}

fn void function_if()
{
	String source_code = `
		module hello;
		fn void greet() @private @if($feature(MY_FEATURE)) {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	test::ne(mod, null);

	FunctionInfo* func_info = context.registry.functions.get("hello::greet")!!;
	test::eq(func_info.mod, "hello");
	Node* node = func_info.node;
	test::eq(node.kind, NodeKind.FN_DECL);
	test::eq(node.visibility, Visibility.PRIVATE);

	FnDecl* fn_decl = node.as(FnDecl);
	test::eq(fn_decl.attributes.len, 2);

	// @private
	AttributeDecl* attr = parser_tests::@attr(fn_decl, 0);
	test::eq(attr.attribute_kind, AttributeKind.PRIVATE);
	test::eq(attr.exprs.len, 0);

	// @if($feature(MY_FEATURE))
	attr = parser_tests::@attr(fn_decl, 1);
	test::eq(attr.attribute_kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);

	CtFeatureExpr* feat          = attr.exprs[0].as(CtFeatureExpr);
	IdentExpr* callee_ident_expr = feat.inner_expr.as(IdentExpr);
	test::eq(callee_ident_expr.ident.text, "MY_FEATURE");
}


fn void const_var_private_if()
{
	String source_code = `
		module hello;
		
		const MY_CONST @private @if($feature(MY_FEATURE)) = 1;
		void* my_var @private @if($feature(MY_FEATURE)) = null;
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	test::@check(mod.nodes.len() > 0);

	int var_decl_count = 0;
	foreach (node : mod.nodes)
	{
		if (node.kind != VAR_DECL) continue;

		var_decl_count++;
		VarDecl* var_decl = node.as(VarDecl);

		test::eq(node.visibility, Visibility.PRIVATE);
		test::eq(node.flags.has_attributes, true);

		String var_name = var_decl.name.text;

		test::eq(var_decl.var_kind, VarDeclKind.VAR_GLOBAL);
		test::eq(var_decl.attributes.len, 2);
		if (var_decl.var_flags.is_const)
		{
			test::eq(var_name, "MY_CONST");
		}
		else
		{
			test::eq(var_name, "my_var");
		}

		// @if($feature(MY_FEATURE))
		AttributeDecl* attr = parser_tests::@attr(var_decl, 1);
		test::eq(attr.attribute_kind, AttributeKind.IF);
		test::eq(attr.exprs.len, 1);

		// $feature()
		CtFeatureExpr* call          = attr.exprs[0].as(CtFeatureExpr);
		IdentExpr* callee_ident_expr = call.inner_expr.as(IdentExpr);
		test::eq(callee_ident_expr.ident.text, "MY_FEATURE");
	}
	test::eq(var_decl_count, 2);
}

fn void op_overloads()
{
	String source_code = `
		module hello;
		struct Foo
		{	
			float a;
			double[] x;
		}

		fn Foo Foo.minus_float(self, float f) @operator(-) => { .a = self.a - f };
		fn Foo Foo.minus_double(self, double d) @operator(-) => { .a = self.a - d };
		fn Foo Foo.add(self, Foo other) @operator(+) => { .a = self.a + other.a };
		fn Foo Foo.add_self(&self, Foo other) @operator(+=)
		{
			self.a += other.a;
			return *self;
		}
		fn bool Foo.eq(self, Foo other) @operator(==)
		{
			return self.a == other.a;
		}
		fn double Foo.get(&self, sz i) @operator([])
		{
			return self.x[i];
		}
		fn double* Foo.get_ref(&self, sz i) @operator(&[])
		{
			return &self.x[i];
		}
		fn void Foo.set(&self, sz i, double new_val) @operator([]=)
		{
			return self.x[i] = new_val;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	int fn_decl_count = 0;
	foreach (node : mod.nodes)
	{
		if (node.kind != FN_DECL) continue;
		fn_decl_count++;

		FnDecl* fn_decl = node.as(FnDecl);
		String fn_name = fn_decl.name.text;
		test::eq(fn_decl.attributes.len, 1);

		AttributeDecl* attr = parser_tests::@attr(fn_decl, 0);
		test::eq(attr.attribute_kind, AttributeKind.OPERATOR);
		OverloadExpr* overload_expr = attr.exprs[0].as(OverloadExpr);
		switch (fn_name) {
			case "minus_float":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_MINUS);
			case "minus_double":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_MINUS);
			case "add":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_PLUS);
			case "add_self":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_PLUS_ASSIGN);
			case "eq":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_EQUAL);
			case "get":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_ELEMENT_AT);
			case "get_ref":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_ELEMENT_REF);
			case "set":
				test::eq(overload_expr.overload_kind, OverloadKind.OV_ELEMENT_SET);
		}
	}
	test::eq(fn_decl_count, 8);
}
