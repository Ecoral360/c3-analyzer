module expr_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void test_literals()
{
	String source_code = `
		module test_module; 
		
		tlocal bool blocal = true;
		
		int [*] arr = {};
		int [*] arr2 = {1};
		
		// Primitives & Numbers
		void* ax = {};
		void* a = null;
		bool b = true;
		bool bx = {};
		bool c = false;
		ulong d = 1_000_000ul;
		uint e = 0xFF_AAu;
		int f = 0b1011_0101;
		int g = 0o755;
		
		// Floats & Real Exponents
		float h = 3.14159f32;
		double i = 2e+10f64;
		float j = 0x1.Ap-2f;

		// Strings
		String k = "Hello";
		String kx = {};
		String l = "Raw string with structural text";
		String lx = ``Raw string with structural text``;

		// Bytes and Specialized Encodings (Emits TokenKind::BYTES)
		char[*] m = x"4865 6c6c 6f20 776f 726c 6421";                  // Hex with interior spacing
		char[*] n = x"414243";                          // Hex with single quotes
		char[*] o = b64"SGVsbG8gV29ybGQ=";              // Base64 chunk

		char char_a = 'a';
		char char_b = '\n';
		char char_c = '\\';
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::ne(mod, null);
	io::printfn("%s", mod.name);
	test::eq(mod.name, "test_module");

	foreach (node : mod.nodes)
	{
		if (node.kind != VAR_DECL) continue;

		VarDecl* var_decl = node.as(VarDecl);
		test::eq(var_decl.var_kind, VarDeclKind.VAR_GLOBAL);
		String var_name = var_decl.name.text;

		test::ne(var_decl.init_expr, null);
		Node* expr_node = var_decl.init_expr;

		if (var_name == "blocal")
		{
			test::eq(var_decl.var_flags.is_thread_local, true);
			test::eq(expr_node.kind, NodeKind.LITERAL_EXPR);
			LiteralExpr* lit = expr_node.as(LiteralExpr);
			test::eq(lit.literal_kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, true);
			continue;
		}

		// {} is a zero initializer
		if (var_name == "ax" || var_name == "bx" || var_name == "kx" || var_name == "arr" || var_name == "arr2")
		{
			test::eq(expr_node.kind, NodeKind.INITIALIZER_LIST_EXPR);
			InitializerListExpr* init = expr_node.as(InitializerListExpr);
			test::eq(init.exprs.len, var_name == "arr2" ? 1 : 0);
			continue;
		}

		test::eq(expr_node.kind, NodeKind.LITERAL_EXPR);
		LiteralExpr* lit = expr_node.as(LiteralExpr);
		if (var_name == "a")
		{
			test::eq(lit.literal_kind, LiteralKind.NULL_LITERAL);
		}
		else if (var_name == "b")
		{
			test::eq(lit.literal_kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, true);
		}
		else if (var_name == "c")
		{
			test::eq(lit.literal_kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, false);
		} // Integers (Decimal, Hex, Binary, Octal)
		else if (var_name == "d")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 1000000u);
		}
		else if (var_name == "e")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0xFFAAu); // 65450
		}
		else if (var_name == "f")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0b10110101u); // 181
		}
		else if (var_name == "g")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0o755u); // 493
		}
		else if (var_name == "h")
		{
			test::eq(lit.literal_kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 3.14159);
		}
		else if (var_name == "i")
		{
			test::eq(lit.literal_kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 2e+10);
		}
		else if (var_name == "j")
		{
			test::eq(lit.literal_kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 0.40625); // 0x1.Ap-2 is 1.625 * 0.25 = 0.40625
		}
		else if (var_name == "k")
		{
			test::eq(lit.literal_kind, LiteralKind.STRING_LITERAL);
			test::eq(lit.string, "Hello");
		}
		else if (var_name == "l" || var_name == "lx")
		{
			test::eq(lit.literal_kind, LiteralKind.STRING_LITERAL);
			test::eq(lit.string, "Raw string with structural text");
		}
		else if (var_name == "m")
		{
			test::eq(lit.literal_kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 12);
			// "Hello world!" in bytes
			test::eq((char)lit.bytes[0], 'H');
			test::eq((char)lit.bytes[11], '!');
		}
		else if (var_name == "n")
		{
			test::eq(lit.literal_kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 3);
			// "ABC"
			test::eq((char)lit.bytes[0], 'A');
			test::eq((char)lit.bytes[1], 'B');
			test::eq((char)lit.bytes[2], 'C');
		}
		else if (var_name == "o")
		{
			test::eq(lit.literal_kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 11);
			// "Hello World" decoded from Base64
			test::eq((char)lit.bytes[0], 'H');
			test::eq((char)lit.bytes[6], 'W');
		}
		else if (var_name == "char_a")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 97u);
		}
		else if (var_name == "char_b")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 10u);
		}
		else if (var_name == "char_c")
		{
			test::eq(lit.literal_kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 92u);
		}
		else
		{
			unreachable("missing assertions for variable %s", var_name);
		}
	}
}

fn void unary()
{
	String source_code = `
		module hello;
		bool a = !foo;
        bool b = !!foo;
        int c = -foo;
        int d = ~foo;
        void* e = &foo;
        void* f = &&foo;
        int g = *foo;
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, VAR_DECL), 7);
}

fn void try_catch()
{
	String source_code = `
		module hello;

		fn void hello()
		{
			int? a = bar();
			if (try foo)
			{
			}

			if (try val = foo)
			{
			}

			if (catch err = foo)
			{
			}

			if (catch foo)
			{
			}

			if (try a = func() && try b = func())
			{
			}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}
/*
fn void call()
{
	String source_code = `
		module hello;

		fn void hello()
		{
			int a = foo() @inline;
			int b = bar() @noinline;
			int c = bar() @pure;

			int a = baz(a, b, c; err)
			{
				Foo foo;
			};

			foo.@each(; name, mod)
			{
			};
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void builtin()
{
	String source_code = `
		module hello;

		fn void hello()
		{
			return $$swizzle(v, ...$vaarg);
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void lambda()
{
	String source_code = `
		module hello;

		alias IntTransform = fn int(int);
		fn void apply(int[] arr, IntTransform t)
		{
		}
		
		fn void main()
		{
			int[] x = { 1, 2, 5 };
			apply(x, fn (i) => i * i);
			io::printfn("%s", x);
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 2);
}

fn void group_and_cast()
{
	String source_code = `
		module hello;
		
		fn void foo(char[] value)
		{
			String cast = (String)value;
			String group = ((String)value);
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);
	VarDecl* cast_decl = comp.statements[0].as(VarDecl);
	test::ne(cast_decl.init_expr, null);
	CastExpr* cast     = cast_decl.init_expr.as(CastExpr);

	test::eq(cast.inner.kind, NodeKind.TYPE_EXPR);
	test::eq(cast.operand.kind, NodeKind.IDENT_EXPR);

	VarDecl* group_decl  = comp.statements[1].as(VarDecl);
	GroupExpr* group     = group_decl.init_expr.as(GroupExpr);
	CastExpr* group_cast = group.inner.as(CastExpr);

	test::eq(group_cast.inner.kind, NodeKind.TYPE_EXPR);
	test::eq(group_cast.operand.kind, NodeKind.IDENT_EXPR);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void initializers()
{
	String source_code = `
		module hello;
		
		fn void foo()
		{
			String[*] strings = { "Foo", "Bar" };
			Foo foo = { .foo = "fafsfaf", .bar = "rfasfafa" };
			Foo foo = (Foo){ .foo = "fafsfaf", .bar = "rfasfafa" };
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void access()
{
	String source_code = `
		module hello;
		
		fn void foo(Bar bar)
		{
			int type = bar.type;
			String name = Bar::name;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);
	VarDecl* type      = comp.statements[0].as(VarDecl);
	VarDecl* name      = comp.statements[1].as(VarDecl);

	test::ne(type.init_expr, null);
	AccessExpr* bar_type = type.init_expr.as(AccessExpr);
	AccessExpr* bar_name = name.init_expr.as(AccessExpr);
	test::eq(bar_type.access_kind, AccessKind.INSTANCE);
	test::eq(bar_name.access_kind, AccessKind.STATIC);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

<*
 todo: verify with json
*>
fn void range()
{
	String source_code = `
		module hello;
		
		fn void foo()
		{
			int[5] a = { 1, 20, 50, 100, 200 };
			int[] b1 = a[1 .. ^1];  // { 20, 50, 100, 200 } a[1 .. (a.len-1)]
			int[] b2 = a[1 .. ^2];  // { 20, 50, 100 }      a[1 .. (a.len-2)]
			int[] b3 = a[1 .. ^3];  // { 20, 50 }           a[1 .. (a.len-3)]
			int[] c1 = a[^1..];     // { 200 }              a[(a.len-1)..]
			int[] c2 = a[^2..];     // { 100, 200 }         a[(a.len-2)..]
			int[] c3 = a[^3..];     // { 50, 100, 200 }     a[(a.len-3)..]
			int[] d = a[^3 : 2];    // { 50, 100 }          a[(a.len-3) : 2]
			// Slicing a whole array, the inclusive index of : gives the difference
			int[] e = a[0 .. ^1];   // a[0 .. a.len-1]
			int[] f = a[0 : ^0];    // a[0 : a.len]
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void optional_expr()
{
	String source_code = `
		module hello;
		
		faultdef FOO;

		fn void foo()
		{
			return FOO~;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[2].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_defined()
{
	String source_code = `
		module hello;
	
		fn void foo()
		{
			$if $defined(Option{Node} x = item):

			$endif
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void lengthof_expr()
{
	String source_code = `
		module hello;
	
		fn void foo()
		{
			sz len = lengthof(foo);
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* func       = mod.nodes[1].as(FnDecl);
	CompoundStmt* comp = func.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_stringify_expr()
{
	String source_code = `
		module hello;
	
		macro void foo()
		{
			var $out = "";
			$out +++= $eval($stringify($vaarg[$i]))($typename);
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 1);
}

fn void vaarg_expr()
{
	String source_code = `
		module hello;
	
		macro compile_time_sum(...)
		{
			var $x = 0;
			$for var $i = 0; $i < $vaarg.len; $i++:
				$x += $vaarg[$i];
			$endfor
			return $x;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 1);
}

fn void ct_reflect_expr()
{
	String source_code = `
		module hello;
	
		macro compile_time_sum(x)
		{
			$if $defined($reflect(x).some_property):
		
			$endif
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 1);
}
