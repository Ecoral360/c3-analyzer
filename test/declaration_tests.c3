module decl_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::lexer;
import analyzer::core;
import analyzer::sema;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_module()
{
	String source_code = `
		<* doc *>
		module hello <Type, Second> @local;

		fn void greet() {}
	`;
	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(mod.name, "hello");

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void function_with_params()
{
	String source_code = `
		module hello;
		fn void greet(int foo, Bar baz) => @pool() {}
		fn int get_int() => 10;
		fn void foo(Type... name) {}
		fn void default_value(Type name = 15) {}
		fn void untyped_variadic(...) {}
		fn void with_attributes(Type name @noalias) {}
		fn void untyped(args...) {}
		fn void path_prefixed(bar::Foo* foo) {}
	`;
	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 8);
}

fn void method_with_params()
{
	String source_code = `
		module hello;
		fn void Foo.greet(&self, Bar baz) {}
		fn void Foo.greet_2(self, Bar baz) {}
	`;
	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	// TODO should this work?
	FunctionInfo* func_info = context.registry.functions.get("hello::greet")!!;
	test::ne(func_info, null);
	FnDecl* func = func_info.node.as(FnDecl);
	TypeExpr* type = func.associated_type.as(TypeExpr);
	test::eq(type.unresolved.name.text, "Foo");


	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 2);
}

fn void macro_with_params()
{
	String source_code = `
		module hello;
		macro void greet(int foo, Bar baz) <Foo> {}
		macro foo(int foo, Bar baz) {}
		macro bar(int foo, Bar baz) => 2;
	`;
	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	assert(context.registry.macros.has_key("hello::greet"));
	assert(context.registry.macros.has_key("hello::foo"));
	assert(context.registry.macros.has_key("hello::bar"));

	MacroInfo* macro_info = context.registry.macros.get("hello::greet")!!;
	MacroDecl* macro_decl = macro_info.node.as(MacroDecl);
	test::eq(macro_decl.name.text, "greet");

	macro_info = context.registry.macros.get("hello::foo")!!;
	macro_decl = macro_info.node.as(MacroDecl);
	test::eq(macro_decl.name.text, "foo");

	macro_info = context.registry.macros.get("hello::bar")!!;
	macro_decl = macro_info.node.as(MacroDecl);
	test::eq(macro_decl.name.text, "bar");

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 3);
}

fn void macro_method_with_params()
{
	String source_code = `
		module hello;
		macro void Foo.greet(&self, Bar baz) {}
		macro Foo.wow(&self, Bar bar) {}
		macro @expect_else_skip(ParseContext* ctx, TokenKind kind, TokenKind[] targets; @body(err)) {}
	`;
	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	MacroDecl* mac = mod.nodes[1].as(MacroDecl);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 3);
}

fn void alias_declarations_parse()
{
	String source_code = `module hello;
		alias IntList = List{int};
		alias Stack<Ty> = List{Ty};
		alias mc = module my::collection;
		alias old_name = new_name;
		alias OLD_CONST = constants::NEW_CONST;
		alias @old = @new;
		alias int_map = map::new {String, int};
		alias ElementPredicate = fn bool(Type *type);
		alias NamedList @private @AliasAttr = List{int};
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(mod.nodes.len(), 10);

	Node* type_node = mod.nodes[1];
	test::eq(type_node.kind, NodeKind.ALIAS_DECL);
	AliasDecl* type_alias = type_node.as(AliasDecl);
	test::eq(type_alias.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(type_alias.name_kind, TokenKind.TYPE_IDENT);
	test::eq(type_alias.name.text, "IntList");
	test::eq(type_alias.target.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_target = type_alias.target.as(TypeExpr);
	test::eq(type_target.type_kind, TypeExprKind.TYPE_GENERIC);
	test::eq(type_target.generic.params.len, 1);
	TypeExpr* type_base = type_target.generic.base.as(TypeExpr);
	test::eq(type_base.type_kind, TypeExprKind.TYPE_IDENTIFIER);
	test::eq(type_base.unresolved.name.text, "List");

	AliasDecl* stack_node = mod.nodes[2].as(AliasDecl);
	test::eq(stack_node.alias_kind, AliasDeclKind.TYPE_ALIAS);
	GenericDecl* generic = stack_node.generics.as(GenericDecl);
	test::eq(generic.params.len, 1);
	TypeExpr* first_type = generic.params[0].as(TypeExpr);
	test::eq(first_type.type_kind, TypeExprKind.TYPE_IDENTIFIER);
	test::eq(first_type.unresolved.name.text, "Ty");
	test::eq(stack_node.target.as(TypeExpr).type_kind, TypeExprKind.TYPE_GENERIC);

	Node* module_node       = mod.nodes[3];
	AliasDecl* module_alias = module_node.as(AliasDecl);
	test::eq(module_alias.alias_kind, AliasDeclKind.MODULE_ALIAS);
	test::eq(module_alias.name_kind, TokenKind.IDENT);
	test::eq(module_alias.target.kind, NodeKind.PATH_EXPR);
	PathExpr* module_path = module_alias.target.as(PathExpr);
	test::eq(module_path.path.text, "my::collection");

	Node* ident_node       = mod.nodes[4];
	AliasDecl* ident_alias = ident_node.as(AliasDecl);
	test::eq(ident_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	test::eq(ident_alias.name_kind, TokenKind.IDENT);

	AliasDecl* attr_alias = mod.nodes[6].as(AliasDecl);
	test::eq(attr_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	test::eq(attr_alias.name_kind, TokenKind.AT_IDENT);

	AliasDecl* generic_target_alias = mod.nodes[7].as(AliasDecl);
	test::eq(generic_target_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	GenericIdentExpr* generic_target_path = generic_target_alias.target.as(GenericIdentExpr);
	test::eq(generic_target_path.exprs.len, 2);

	AliasDecl* fn_ptr_alias = mod.nodes[8].as(AliasDecl);
	test::eq(fn_ptr_alias.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(fn_ptr_alias.name.text, "ElementPredicate");
	TypeExpr* fn_ptr_type = fn_ptr_alias.target.as(TypeExpr);
	test::eq(fn_ptr_type.type_kind, TypeExprKind.TYPE_FUNCTION);
	TypeExpr* fn_ret_type = fn_ptr_type.func.ret_type.as(TypeExpr);
	test::eq(fn_ret_type.type_kind, TypeExprKind.TYPE_IDENTIFIER);
	test::eq(fn_ret_type.unresolved.name.text, "bool");
	test::eq(fn_ptr_type.func.params.len, 1);
	VarDecl* fn_param = fn_ptr_type.func.params[0].as(VarDecl);
	test::eq(fn_param.var_kind, VarDeclKind.VAR_PARAM);
	test::eq(fn_param.name.text, "type");
	TypeExpr* param_type = fn_param.type.as(TypeExpr);
	test::eq(param_type.type_kind, TypeExprKind.TYPE_POINTER);
	TypeExpr* param_base_type = param_type.modify.base.as(TypeExpr);
	test::eq(param_base_type.unresolved.name.text, "Type");

	Node* node            = mod.nodes[9];
	AliasDecl* alias_decl = node.as(AliasDecl);
	test::eq(alias_decl.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(alias_decl.generics, null);
	test::eq(alias_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(alias_decl, 0).attribute_kind, AttributeKind.PRIVATE);
	test::eq(parser_tests::@attr(alias_decl, 1).name.text, "@AliasAttr");
	test::eq(node.flags.has_attributes, true);
	test::eq(node.visibility, Visibility.PRIVATE);
}

fn void typedef_declarations_parse()
{
	String source_code = `module hello;
		typedef MyId = int;
		typedef MyId2 @constinit = int;
		typedef Bcd @constinit = inline int;
		typedef IntAlign2 = int @align(2);
		typedef Float4 = float[<4>] @simd;
		typedef EnumSet (Printable) = EnumSetType;
		typedef Option<Type> = Type*;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(mod.nodes.len(), 8);

	TypedefDecl* my_id = mod.nodes[1].as(TypedefDecl);
	test::eq(my_id.name.text, "MyId");
	test::eq(my_id.is_inline, false);
	test::eq(my_id.attributes.len, 0);
	TypeExpr* my_id_base = my_id.base_type.as(TypeExpr);
	test::eq(my_id_base.type_kind, TypeExprKind.TYPE_IDENTIFIER);
	test::eq(my_id_base.unresolved.name.text, "int");

	TypedefDecl* my_id2 = mod.nodes[2].as(TypedefDecl);
	test::eq(my_id2.name.text, "MyId2");
	test::eq(my_id2.attributes.len, 1);

	TypedefDecl* bcd = mod.nodes[3].as(TypedefDecl);
	test::eq(bcd.name.text, "Bcd");
	test::eq(bcd.is_inline, true);
	test::eq(bcd.attributes.len, 1);

	TypedefDecl* int_align = mod.nodes[4].as(TypedefDecl);
	test::eq(int_align.name.text, "IntAlign2");
	test::eq(int_align.attributes.len, 1);

	TypedefDecl* float4 = mod.nodes[5].as(TypedefDecl);
	test::eq(float4.name.text, "Float4");
	test::eq(float4.attributes.len, 1);
	TypeExpr* float4_base = float4.base_type.as(TypeExpr);
	test::eq(float4_base.type_kind, TypeExprKind.TYPE_VECTOR);
	test::eq(float4_base.array.len_expr.kind, NodeKind.LITERAL_EXPR);

	TypedefDecl* enum_set = mod.nodes[6].as(TypedefDecl);
	test::eq(enum_set.name.text, "EnumSet");
	test::eq(enum_set.interfaces.len, 1);
	TypeExpr* interface_type = enum_set.interfaces[0].as(TypeExpr);
	test::eq(interface_type.unresolved.name.text, "Printable");
	TypeExpr* enum_set_base = enum_set.base_type.as(TypeExpr);
	test::eq(enum_set_base.unresolved.name.text, "EnumSetType");

	TypedefDecl* option = mod.nodes[7].as(TypedefDecl);
	test::eq(option.name.text, "Option");
	GenericDecl* option_generics = option.generics.as(GenericDecl);
	test::eq(option_generics.params.len, 1);
	TypeExpr* option_generic_param = option_generics.params[0].as(TypeExpr);
	test::eq(option_generic_param.unresolved.name.text, "Type");
	TypeExpr* option_base = option.base_type.as(TypeExpr);
	test::eq(option_base.type_kind, TypeExprKind.TYPE_POINTER);
	TypeExpr* option_inner = option_base.modify.base.as(TypeExpr);
	test::eq(option_inner.unresolved.name.text, "Type");
}

fn void function_pointer_types_are_alias_only()
{
	String source_code = `module hello;
		alias CallbackDefault = fn void(int value = 0);
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	AliasDecl* alias_decl  = mod.nodes[1].as(AliasDecl);
	TypeExpr* alias_target = alias_decl.target.as(TypeExpr);
	test::eq(alias_target.type_kind, TypeExprKind.TYPE_FUNCTION);
	test::eq(alias_target.func.params.len, 1);
	VarDecl* alias_param = alias_target.func.params[0].as(VarDecl);
	test::eq(alias_param.init_expr.kind, NodeKind.LITERAL_EXPR);
}

fn void global_var_const()
{
	String source_code = `
		module hello;

		const int[4]* FOO = null;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
}

fn void global_var_multi_decl()
{
	String source_code = `
		module hello;

		int foo, bar, z;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	test::eq(decl.name.text, "foo");
	test::eq(decl.init_expr, null);
	test::eq(decl.type.as(TypeExpr).unresolved.name.text, "int");

	test::ne(decl.next, null);
	VarDecl* decl_2 = decl.next.as(VarDecl);
	test::eq(decl_2.name.text, "bar");
	test::eq(decl_2.init_expr, null);
	test::eq(decl_2.type.as(TypeExpr).unresolved.name.text, "int");

	test::ne(decl_2.next, null);
	VarDecl* decl_3 = decl_2.next.as(VarDecl);
	test::eq(decl_3.name.text, "z");
	test::eq(decl_3.next, null);
	test::eq(decl_3.init_expr, null);
	test::eq(decl_3.type.as(TypeExpr).unresolved.name.text, "int");
}

fn void global_var()
{
	String source_code = `
		module hello;

		int[4] foo;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
}

fn void global_var_tlocal()
{
	String source_code = `
		module hello;

		tlocal int foo = 1;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
}

fn void global_var_extern()
{
	String source_code = `
		module hello;

		extern int foo;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	VarDecl* decl     = target_node.as(VarDecl);
	test::eq(decl.var_kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TypeExpr);
}

fn void expand()
{
	String source_code = `
		module hello;

		$expand("fn void foo();");
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node    = mod.nodes[1];
	CtExpandDecl* decl   = target_node.as(CtExpandDecl);
	LiteralExpr* literal = decl.expr.as(LiteralExpr);
	test::eq(literal.string, "fn void foo();");
}

fn void struct_decl()
{
	String source_code = `
		module hello;

		<*
		*>
		struct Foo (Printable) <Type> @local
		{
			<*
				Comment
			*>
			int a;
			inline Bar b;

			struct sub
			{
				int sub_a;

				union sub_union
				{
					int faf;
				}
			}

			struct
			{
				int a;
			}

			union
			{
				int a;
			}

			bitstruct bits
			{
				bool a;
				bool b;
				bool c;
			}
		}
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];
	StructDecl* head  = target_node.as(StructDecl);
	test::ne(head.next, null);
	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, STRUCT_DECL), 1);
}


fn void bitstruct_decl()
{
	String source_code = `
		module hello;

		<*
		*>
		bitstruct Foo : char[4] @bigendian
		{
			ushort v : 0..15;
		}

		bitstruct Bar : short
		{
			int a : 0..2; // Exact bit ranges, bits 0-2
			uint b : 3..6;
			MyEnum c : 7..13;
		}
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[2];
	StructDecl* head  = target_node.as(StructDecl);
	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, STRUCT_DECL), 2);
}

fn void union_decl()
{
	String source_code = `
		module hello;

		union Foo
		{
			int a;
			Foo b;

			struct bar
			{
				int x;
				int y;
			}

			struct baz
			{
				int z;
				int w;
			}
		}
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, STRUCT_DECL), 1);
}

fn void faultdef_decl()
{
	String source_code = `
		module hello;

		<*
		 My Faultdef
		*>
		faultdef ERROR, FOO, BAR;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FAULTDEF_DECL), 1);
}


fn void interface_decl()
{
	String source_code = `
		module hello;

		interface MyInterface : Foo, Bar @local
		{
			fn void foo() @optional;
			fn bool bar(int a);
		}
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, INTERFACE_DECL), 1);
}

fn void attrdef_decl()
{
	String source_code = `
		module hello;

		attrdef @MyAttribute       = @noreturn, @inline;
		attrdef @MyCname(x)        = @cname(x);
		attrdef @TagFoo(value)     = @tag("foo", value);
		attrdef @MyAttributeEmpty;
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, ATTRDEF_DECL), 4);
}

fn void ct_assert_decl()
{
	String source_code = `
		module hello;

		$assert 2 == 2;
		$assert @bar() == MY_CONST;
		$assert 98 == -2 : "no no";
		$assert 98 == -2 : @sprintf("no %s", @bar());
	`;

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* target_node = mod.nodes[1];

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, CT_ASSERT_DECL), 4);
}

fn void macro_body_params()
{
	String source_code = `
		module hello;
		macro @each(int a; @body(int x)) {}
		macro @twice(int a; @body) {}
		macro @plain(int a) {}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");
	test::eq(parser_tests::error_diag_count, 0);

	Module* mod = context.modules.get("hello")!!;

	MacroDecl* each = mod.nodes[1].as(MacroDecl);
	test::eq(each.params.len, 1);
	test::ne(each.body_params, null);
	BodyParamDecl* body_params = each.body_params.as(BodyParamDecl);
	test::eq(body_params.params.len, 1);

	MacroDecl* twice = mod.nodes[2].as(MacroDecl);
	test::ne(twice.body_params, null);
	test::eq(twice.body_params.as(BodyParamDecl).params.len, 0);

	MacroDecl* plain = mod.nodes[3].as(MacroDecl);
	test::eq(plain.body_params, null);
}
