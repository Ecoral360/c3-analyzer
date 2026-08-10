module stmt_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::sema;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void switch_stmt()
{
	String source_code = `
		module hello;
		fn void foo()
		{
			int a = 5;
			switch LABEL: (a)
			{
				case 1: break;
				case 2:
					{
					}
				case 3:
				case 4: continue LABEL;
				case 5: break LABEL;
				case 6: continue;
				case 7: break;
				case 8:
					{
					}
					nextcase;
				default:
			}
		}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);
	SwitchStmt* sw        = fn_comp.statements[1].as(SwitchStmt);
	test::eq(sw.cases.len, 9);
	CondExpr* cond = sw.cond.as(CondExpr);
	test::eq(cond.exprs[0].as(IdentExpr).ident.text, "a");
	test::eq(sw.label.text, "LABEL");

	CaseStmt* case0      = sw.cases[0].as(CaseStmt);
	CompoundStmt* comp_0 = case0.body.as(CompoundStmt);
	test::eq(comp_0.statements[0].kind, NodeKind.CONTINUE_BREAK_STMT);
	CaseStmt* case1      = sw.cases[1].as(CaseStmt);
	CompoundStmt* comp_1 = case1.body.as(CompoundStmt);
	test::eq(comp_1.statements.len, 1);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_switch_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo()
		{
			$switch $x:
				$case 1:
					#y += $x * $x;
				$case 2:
					#y += $x;
				$case 3:
					#y *= $x;
				$default:
					#y -= $x;
			$endswitch
		}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);
	CtSwitchStmt* sw      = fn_comp.statements[0].as(CtSwitchStmt);
	test::eq(sw.cases.len, 4);
	test::eq(sw.cond[0].as(IdentExpr).ident.text, "$x");

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void if_elseif_else()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			if LABEL: (a > 0 && a < 10)
			{
			}
			else if (a == 5)
			{
			}
			else
			{
			}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);
	IfStmt* if_stmt       = fn_comp.statements[0].as(IfStmt);
	IfStmt* if_stmt_2     = if_stmt.else_body.as(IfStmt);
	test::eq(if_stmt_2.then_body.kind, NodeKind.COMPOUND_STMT);
	test::eq(if_stmt_2.else_body.kind, NodeKind.COMPOUND_STMT);
	test::eq(if_stmt.then_body.kind, NodeKind.COMPOUND_STMT);
	test::ne(if_stmt.else_body, null);
	test::eq(if_stmt.label.text, "LABEL");
	test::eq(fn_comp.statements.len, 1);
	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_if_else()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			$if $x > 3:
				#y += $x * $x;
			$else
				#y += $x;
			$endif

			$if $x > 3:
				#y += $x * $x;
			$endif
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void for_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			for (;;)
			{
			}

			for (sz i = 0; i < 10; i++)
			{
			}

			for (sz i = 0; i < 10;)
			{
			}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);
	ForStmt* for_stmt     = fn_comp.statements[0].as(ForStmt);

	test::eq(for_stmt.label, null);
	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void while_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			while FOO: (true)
			{
			}

			while (a > b)
			{
			}

			while (a > b) return a;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);

	WhileStmt* while_stmt = fn_comp.statements[0].as(WhileStmt);
	test::eq(while_stmt.label.text, "FOO");

	while_stmt = fn_comp.statements[1].as(WhileStmt);
	test::eq(while_stmt.label, null);
}

fn void ct_assert_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			$assert 2 == 2;
			$assert @bar() == MY_CONST;
			$assert 98 == -2 : "no no";
			$assert 98 == -2 : @sprintf("no %s", @bar());
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_error_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			$error @sprintf("no %s", @bar());
			$error "no no";
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void var_decl_stmt()
{
	// uses a function just to get a compound
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			static bool boolean = true;
			const String MY_STRING = "foo";
			tlocal bool bar = false;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* fn_comp = fn_decl.body.as(CompoundStmt);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void foreach_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach LOOP: (x : arr) {}

			foreach (x : arr) {}
			foreach (int x : arr) {}
			foreach (&x : arr) {}
			foreach (i, x : arr) {}
			foreach (i, &x : arr) {}

			foreach_r LOOP_R: (x : arr) {}

			foreach_r (x : arr) {}
			foreach_r (int x : arr) {}
			foreach_r (&x : arr) {}
			foreach_r (i, x : arr) {}
			foreach_r (i, &x : arr) {}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl          = func_info.node.as(FnDecl);
	CompoundStmt* body_stmt = fn_decl.body.as(CompoundStmt);

	// foreach LOOP: (x : arr) — labeled, no reverse,  no index, no type, no ref
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(ForeachStmt);
	test::eq(foreach_stmt.label.text, "LOOP");
	test::eq(foreach_stmt.is_reverse, false);
	test::eq(foreach_stmt.index, null);
	VarDecl* var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(var_decl.name.text, "x");

	// foreach (x : arr) — no label, no reverse, no index, no type, no ref
	foreach_stmt = body_stmt.statements[1].as(ForeachStmt);
	test::eq(foreach_stmt.label, null);
	test::eq(foreach_stmt.is_reverse, false);
	test::eq(foreach_stmt.index, null);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(var_decl.name.text, "x");

	// foreach (int x : arr) — typed value, no ref
	foreach_stmt = body_stmt.statements[2].as(ForeachStmt);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::ne(var_decl.type, null);
	TypeExpr* type_expr = var_decl.type.as(TypeExpr);
	test::eq(type_expr.unresolved.name.text, "int");
	test::eq(foreach_stmt.value_by_ref, false);

	// foreach (&x : arr) — ref value
	foreach_stmt = body_stmt.statements[3].as(ForeachStmt);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.var_flags.is_ref, true);
	test::eq(var_decl.name.text, "x");

	// foreach (i, x : arr) — index + value, no ref on either
	foreach_stmt = body_stmt.statements[4].as(ForeachStmt);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, false);
	VarDecl* var_idx_decl = foreach_stmt.index.as(VarDecl);
	test::eq(var_idx_decl.name.text, "i");
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.name.text, "x");

	// foreach (i, &x : arr) — index, ref value
	foreach_stmt = body_stmt.statements[5].as(ForeachStmt);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, true);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.var_flags.is_ref, true);

	// foreach_r LOOP_R: (x : arr) — reverse, label
	foreach_stmt = body_stmt.statements[6].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	test::eq(foreach_stmt.label.text, "LOOP_R");
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.name.text, "x");

	// foreach_r (x : arr) no index, no type, no ref
	foreach_stmt = body_stmt.statements[7].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	test::eq(foreach_stmt.index, null);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(var_decl.name.text, "x");

	// foreach_r (int x : arr) typed
	foreach_stmt = body_stmt.statements[8].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::ne(var_decl.type, null);
	type_expr = var_decl.type.as(TypeExpr);
	test::eq(type_expr.unresolved.name.text, "int");
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(var_decl.name.text, "x");

	// foreach_r (&x : arr) no type, ref
	foreach_stmt = body_stmt.statements[9].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.var_flags.is_ref, true);
	test::eq(var_decl.name.text, "x");

	// foreach_r (i, x : arr)
	foreach_stmt = body_stmt.statements[10].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, false);
	var_idx_decl = foreach_stmt.index.as(VarDecl);
	test::eq(var_idx_decl.name.text, "i");
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.name.text, "x");

	// foreach_r (i, &x : arr)
	foreach_stmt = body_stmt.statements[11].as(ForeachStmt);
	test::eq(foreach_stmt.is_reverse, true);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, true);
	var_decl = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.var_flags.is_ref, true);
	test::eq(var_decl.name.text, "x");
}

fn void err_foreach_missing_name_after_type()
{
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (int : arr) {}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl         = func_info.node.as(FnDecl);
	CompoundStmt* body_stmt = fn_decl.body.as(CompoundStmt);

	// foreach still produces a FOREACH_STMT node; value has type but name = -1
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(ForeachStmt);
	VarDecl* var_decl         = foreach_stmt.variable.as(VarDecl);
	test::ne(var_decl.type, null);
	test::eq(var_decl.name, null);
}

fn void err_foreach_missing_name_no_type()
{
	// '& :' — AMP consumed but no IDENT follows, no type was parsed
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (& : arr) {}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl         = func_info.node.as(FnDecl);
	CompoundStmt* body_stmt = fn_decl.body.as(CompoundStmt);

	// value_by_ref set, no type, name = -1
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(ForeachStmt);
	VarDecl* var_decl         = foreach_stmt.variable.as(VarDecl);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.var_flags.is_ref, true);
	test::eq(var_decl.name, null);
}

fn void err_foreach_missing_colon()
{
	// missing ':' between vars and collection — foreach node becomes ERROR
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (x arr) {}
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl         = func_info.node.as(FnDecl);
	CompoundStmt* body_stmt = fn_decl.body.as(CompoundStmt);

	// the foreach node has kind ERROR due to the missing colon
	test::eq(body_stmt.statements[0].flags.has_error, true);
}

fn void defer_stmt()
{
	String source_code = `
		module hello;
		fn void foo()
		{
			defer io::printn("");
			defer io::print("A");
			defer try io::print("X");
			defer catch io::print("B");
			defer (catch err) io::printf("%s", err);
			defer {
				defer (catch err) io::printf("%s", err);
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

fn void do_while_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			do
			{
				a++;
			} while (a < 10);

			do FOO:
			{
				a--;
			} while (a > 0);

			do
			{
				a = 0;
			};
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl         = func_info.node.as(FnDecl);
	CompoundStmt* func_body = fn_decl.body.as(CompoundStmt);
	test::eq(func_body.statements.len, 3);

	// do { ... } while (cond); — has cond, no label
	DoWhileStmt* do_while_stmt = func_body.statements[0].as(DoWhileStmt);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(do_while_stmt.label, null);

	// do LABEL: { ... } while (cond); — has cond and label
	do_while_stmt = func_body.statements[1].as(DoWhileStmt);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(do_while_stmt.label.text, "FOO");

	// do { ... }; — no while clause, parses successfully
	do_while_stmt = func_body.statements[2].as(DoWhileStmt);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(do_while_stmt.label, null);
}

fn void assert_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			assert(false, "urmom %s", foo);
			assert(false, "urmom");
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_expand_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			$expand("fn int foo() {}");
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}

fn void ct_foreach_stmt()
{
	String source_code = `
		module hello;

		macro AsciiCharset @create_set(String $string) @const
		{
			// std/core/ascii.c3 create_set
			$foreach $c : $string:
				$set |= 1ULL << $c;
			$endforeach
			return $set;
		}

		macro void format_members(value)
		{
			// std/io/formatter.c3 struct_to_format
			$foreach $i, $member : $Type::members:
				$if $i > 0:
					total += f.print(", ")!;
				$endif
				value.$member;
			$endforeach
		}

		// std/crypto/argon2.c3 inline foreach form
		fn void inline_foreach()
		{
			$foreach $x, $c : $indices: $indices[$x] = $i + $x; $endforeach
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 2);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);

	MacroInfo* macro_info = context.registry.macros.get("hello::@create_set")!!;

	// TODO Macro definitions in registry?
	MacroDecl* macro_decl = macro_info.node.as(MacroDecl);
	CompoundStmt* macro_body = macro_decl.body.as(CompoundStmt);
	CtForeachStmt* foreach_stmt = macro_body.statements[0].as(CtForeachStmt);
	VarDecl* foreach_value_decl = foreach_stmt.value.as(VarDecl);
	test::eq(foreach_stmt.index, null);
	test::eq(foreach_value_decl.name.text, "$c");
	test::eq(foreach_stmt.expr.as(IdentExpr).ident.text, "$string");
	CompoundStmt* foreach_body = foreach_stmt.body.as(CompoundStmt);
	test::eq(foreach_body.statements.len, 1);
	test::eq(foreach_body.statements[0].kind, NodeKind.EXPR_STMT);

	macro_info = context.registry.macros.get("hello::@create_set")!!;
	macro_decl = macro_info.node.as(MacroDecl);
	macro_body = macro_decl.body.as(CompoundStmt);
	foreach_stmt = macro_body.statements[0].as(CtForeachStmt);
	VarDecl* foreach_index_decl = foreach_stmt.value.as(VarDecl);
	foreach_value_decl = foreach_stmt.value.as(VarDecl);
	test::eq(foreach_index_decl.name.text, "$c");
	foreach_body = foreach_stmt.body.as(CompoundStmt);
	test::eq(foreach_body.statements.len, 1);
	test::eq(foreach_body.statements[0].kind, NodeKind.EXPR_STMT);

	FunctionInfo* func_info = context.registry.functions.get("hello::inline_foreach")!!;
	FnDecl* fn_decl = func_info.node.as(FnDecl);
	CompoundStmt* fn_body = fn_decl.body.as(CompoundStmt);
	foreach_stmt = fn_body.statements[0].as(CtForeachStmt);
	foreach_index_decl = foreach_stmt.index.as(VarDecl);
	foreach_value_decl = foreach_stmt.value.as(VarDecl);
	test::eq(foreach_index_decl.name.text, "$x");
	test::eq(foreach_value_decl.name.text, "$c");
	test::eq(foreach_stmt.expr.as(IdentExpr).ident.text, "$indices");
	foreach_body = foreach_stmt.body.as(CompoundStmt);
	test::eq(foreach_body.statements.len, 1);
	test::eq(foreach_body.statements[0].kind, NodeKind.EXPR_STMT);
}

fn void decl_stmt_ambiguity()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			String foo;
			foo::Bar bar;

			Status* my_ptr;
            x * y;
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FunctionInfo* func_info = context.registry.functions.get("hello::foo")!!;
	FnDecl* fn_decl         = func_info.node.as(FnDecl);

	CompoundStmt* func_body = fn_decl.body.as(CompoundStmt);
	test::eq(func_body.statements.len, 4);

	VarDecl* vardecl = func_body.statements[2].as(VarDecl);

	ExprStmt* expr_stmt = func_body.statements[3].as(ExprStmt);
	BinaryExpr* bin = expr_stmt.expr_stmt.as(BinaryExpr);

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);
}
