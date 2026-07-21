module constdef_enum_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_enum()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA, BBB }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void values()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA = 1, BBB @if(true) = 2 }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
		test::ne(var_decl.init_expr, null);
		LiteralExpr* enum_value = var_decl.init_expr.as(LiteralExpr);
		test::eq(enum_value.literal_kind, LiteralKind.INT_LITERAL);
		assert(enum_value.integer == 1 || enum_value.integer == 2, "Failed to parse enum value");
	}
}

fn void char_backing_type()
{
	String source_code = `
	module hello;
	enum MyEnum : char { AAA, BBB }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TypeExpr);
	test::eq(backing_type_expr.type_kind, TypeExprKind.TYPE_IDENTIFIER);

	String type_name = backing_type_expr.unresolved.name.text;
	test::eq(type_name, "char");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void assoc_param_values()
{
	String source_code = `
	module hello;
	enum MyEnum : (int a, String b) { AAA {0, "aaa"}, BBB {1, "bbb"} }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.backing_type == null, true);

	test::eq(enum_decl.assoc_params.len, 2);

	VarDecl* a_param = enum_decl.assoc_params[0].as(VarDecl);
	TypeExpr* a_type = a_param.type.as(TypeExpr);
	test::eq(a_type.unresolved.name.text, "int");
	test::eq(a_param.name.text, "a");

	VarDecl* b_param = enum_decl.assoc_params[1].as(VarDecl);
	TypeExpr* b_type = b_param.type.as(TypeExpr);
	test::eq(b_type.unresolved.name.text, "String");
	test::eq(b_param.name.text, "b");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* variant_decl      = variant.as(VarDecl);
		String variant_description = variant_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
		InitializerListExpr* assoc_values = variant_decl.assoc_values.as(InitializerListExpr);
		test::eq(assoc_values.exprs.len, 2);

		foreach (expr : assoc_values.exprs)
		{
			LiteralExpr* lit_expr = expr.as(LiteralExpr);
			if (lit_expr.literal_kind == LiteralKind.INT_LITERAL)
			{
				assert(lit_expr.integer == 0 || lit_expr.integer == 1, "Failed to parse \"a\" assoc value");
			}
			if (lit_expr.literal_kind == LiteralKind.STRING_LITERAL)
			{
				String string_value = lit_expr.string;
				assert(string_value == "aaa" || string_value == "bbb", "Failed to parse \"b\" assoc value");
			}
		}
	}
}

fn void interfaces()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) { AAA, BBB }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");

	test::eq(enum_decl.interfaces.len, 2);
	TypeExpr* interface_type = enum_decl.interfaces[0].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "Printable");
	interface_type = enum_decl.interfaces[1].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "OutStream");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void constdef_interfaces_inline_backing()
{
	String source_code = `
	module hello;
	constdef MyConstdef (Printable, OutStream) : inline uint {
		AAA @tag("constdef_member_tag", 420) = 69
	}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyConstdef");
	test::eq(enum_decl.interfaces.len, 2);

	TypeExpr* interface_type = enum_decl.interfaces[0].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "Printable");
	interface_type = enum_decl.interfaces[1].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "OutStream");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TypeExpr);
	test::eq(backing_type_expr.unresolved.name.text, "uint");
	test::eq(enum_decl.is_inline_backing, true);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VarDecl);
	test::eq(var_decl.name.text, "AAA");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).attribute_kind, AttributeKind.TAG);
	test::ne(var_decl.init_expr, null);
	LiteralExpr* enum_value = var_decl.init_expr.as(LiteralExpr);
	test::eq(enum_value.literal_kind, LiteralKind.INT_LITERAL);
	test::eq(enum_value.integer, 69u);
}

fn void basic_constdef()
{
	String source_code = `
	module hello;
	constdef MyConstdef {
		AAA = 1,
		BBB,
		CCC
	}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyConstdef");
	test::eq(enum_decl.interfaces.len, 0);
	test::eq(enum_decl.backing_type == null, true);
	test::eq(enum_decl.is_inline_backing, false);
	test::eq(enum_decl.variants.len, 3);

	VarDecl* var_decl = enum_decl.variants[0].as(VarDecl);
	test::eq(var_decl.name.text, "AAA");
	test::ne(var_decl.init_expr, null);
	LiteralExpr* value = var_decl.init_expr.as(LiteralExpr);
	test::eq(value.integer, 1u);

	var_decl = enum_decl.variants[1].as(VarDecl);
	test::eq(var_decl.name.text, "BBB");
	test::eq(var_decl.init_expr == null, true);
}

fn void constdef_backing_type_and_attributes()
{
	String source_code = `
	module hello;
	constdef MyConstdef : uint @tag("decl_tag", 1) @if(true) {
		AAA @tag("value_tag", 2) = 10
	}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyConstdef");
	test::eq(enum_decl.is_inline_backing, false);

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TypeExpr);
	test::eq(backing_type_expr.unresolved.name.text, "uint");
	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).attribute_kind, AttributeKind.TAG);
	test::eq(parser_tests::@attr(enum_decl, 1).attribute_kind, AttributeKind.IF);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VarDecl);
	test::eq(var_decl.name.text, "AAA");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).attribute_kind, AttributeKind.TAG);
	LiteralExpr* value = var_decl.init_expr.as(LiteralExpr);
	test::eq(value.integer, 10u);
}

fn void enum_interfaces_backing_type()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) : uint {
		BBB @tag("enum_member_tag", 240)
	}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.interfaces.len, 2);

	TypeExpr* interface_type = enum_decl.interfaces[0].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "Printable");
	interface_type = enum_decl.interfaces[1].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "OutStream");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TypeExpr);
	test::eq(backing_type_expr.unresolved.name.text, "uint");
	test::eq(enum_decl.is_inline_backing, false);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VarDecl);
	test::eq(var_decl.name.text, "BBB");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).attribute_kind, AttributeKind.TAG);
	test::eq(var_decl.init_expr == null, true);
}

fn void private_if_attributes()
{
	String source_code = `
	module hello;
	enum MyEnum @private @if(true) { AAA, BBB }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_node.visibility, Visibility.PRIVATE);

	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).attribute_kind, AttributeKind.PRIVATE);
	test::eq(parser_tests::@attr(enum_decl, 1).attribute_kind, AttributeKind.IF);

	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void values_if_attribute()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA @if(true), BBB @if(true) }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);

	test::eq(enum_decl.name.text, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");

		test::eq(var_decl.attributes.len, 1);
		test::eq(parser_tests::@attr(var_decl, 0).attribute_kind, AttributeKind.IF);
	}
}

fn void complex()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) : char (int a, String b @tag("enum_member_tag", 1)) @tag("tag_key", "tag_value") @if(true) {
		AAA @tag("tag_key", "AAA") @if(true) {0, "a"},
		BBB @tag("tag_key", "BBB") @if(true) {1, "b"} ,
	}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, ENUM_DECL), 1);

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);

	test::eq(enum_decl.name.text, "MyEnum");

	test::eq(enum_decl.interfaces.len, 2);
	TypeExpr* interface_type = enum_decl.interfaces[0].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "Printable");
	interface_type = enum_decl.interfaces[1].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "OutStream");

	test::eq(enum_decl.assoc_params.len, 2);

	VarDecl* a_param = enum_decl.assoc_params[0].as(VarDecl);
	TypeExpr* a_type = a_param.type.as(TypeExpr);
	test::eq(a_type.unresolved.name.text, "int");
	test::eq(a_param.name.text, "a");

	VarDecl* b_param = enum_decl.assoc_params[1].as(VarDecl);
	TypeExpr* b_type = b_param.type.as(TypeExpr);
	test::eq(b_type.unresolved.name.text, "String");
	test::eq(b_param.name.text, "b");

	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).attribute_kind, AttributeKind.TAG);
	test::eq(parser_tests::@attr(enum_decl, 1).attribute_kind, AttributeKind.IF);

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VarDecl);
		String variant_description = var_decl.name.text;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");

		test::eq(var_decl.attributes.len, 2);
		test::eq(parser_tests::@attr(var_decl, 0).attribute_kind, AttributeKind.TAG);
		test::eq(parser_tests::@attr(var_decl, 1).attribute_kind, AttributeKind.IF);
	}
}

fn void err_missing_name()
{
	String source_code = `
	module hello;
	enum { AAA, BBB }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.name, null);
	test::eq(enum_decl.variants.len, 0);
}

fn void err_invalid_variant_name()
{
	String source_code = `
	module hello;
	enum MyEnum { bad_name, GOOD }
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* enum_node     = mod.nodes[1];
	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.variants.len, 1);

	test::eq(enum_decl.variants[0].kind, NodeKind.VAR_DECL);

	VarDecl* good = enum_decl.variants[0].as(VarDecl);
	test::eq(good.name.text, "GOOD");
}

fn void err_missing_rbrace()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA, BBB
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	// Node kind is set to MISSING when RBRACE is not found,
	// but the EnumDecl data is still populated with what was parsed.
	Node* enum_node = mod.nodes[1];
	test::eq(enum_node.kind, NodeKind.ENUM_DECL);

	EnumDecl* enum_decl = enum_node.as(EnumDecl);
	test::eq(enum_decl.variants.len, 2);

	VarDecl* aaa = enum_decl.variants[0].as(VarDecl);
	test::eq(aaa.name.text, "AAA");
	VarDecl* bbb = enum_decl.variants[1].as(VarDecl);
	test::eq(bbb.name.text, "BBB");
}
