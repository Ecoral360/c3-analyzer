module sema_tests @test;

import parser_tests;

import analyzer::core;
import analyzer::sema;

import std::io;

<*
 A contract is parsed as a child of the declaration it documents, but it is
 written above it, so its range sits outside that declaration's scope. The
 variable pass must not let that pull it back out to the file scope.
*>
fn void contract_does_not_leak_params_to_file_scope()
{
	String source_code = `
		module hello;

		<*
			@require a > 0 : "positive"
			@ensure return > 0
		*>
		fn int foo(int a) { return a; }

		fn int bar(int a) { return a; }

		<* doc macro *>
		macro @baz(int a) { return a; }
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

<*
 The redefinition check still fires for a real shadow in one scope.
*>
fn void redefinition_in_same_scope_is_reported()
{
	String source_code = `
		module hello;

		fn void foo()
		{
			int a = 1;
			int a = 2;
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 1);
}

<*
 Same name in two sibling blocks is not a redefinition.
*>
fn void sibling_scopes_may_reuse_a_name()
{
	String source_code = `
		module hello;

		fn void foo()
		{
			{
				int a = 1;
			}
			{
				int a = 2;
			}
			if (true)
			{
				int a = 3;
			}
			while (true)
			{
				int a = 4;
			}
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

<*
 A lambda has parameters of its own, so it needs a scope of its own. Both of
 these compile with c3c; neither is a redefinition.
*>
fn void lambda_params_are_scoped_to_the_lambda()
{
	String source_code = `
		module hello;

		fn void foo(int z)
		{
			int y = 1;
			var f = fn int(int z) => z + 1;
			var g = fn int(int z) => z + 2;
			var h = fn int(int y) => y + 3;
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

<*
 The same for attrdef parameters, which are otherwise registered at file scope.
*>
fn void attrdef_params_are_scoped_to_the_attrdef()
{
	String source_code = `
		module hello;

		attrdef @One(x) = @cname(x);
		attrdef @Two(x) = @cname(x);

		fn void foo(int x) {}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

<*
 c3c accepts a local that shadows a global, so lookup must stop at the
 function scope. A redefinition inside the lambda body is still caught.
*>
fn void locals_may_shadow_globals()
{
	String source_code = `
		module hello;

		int a = 1;

		fn void foo()
		{
			int a = 2;
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

fn void redefinition_inside_a_lambda_is_reported()
{
	String source_code = `
		module hello;

		fn void foo()
		{
			var f = fn int(int z)
			{
				int z = 2;
				return z;
			};
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 1);
}

fn void a_lambda_may_reuse_the_names_of_runtime_locals()
{
	String source_code = `
		module hello;

		const CONSTANT = "salut";
		String global_var = "allo";

		fn void main()
		{
			String local_var = "bonjour";
			const LOCAL_CONSTANT = "bonsoir";
			static String static_local = "static";

			var foo = fn void()
			{
				String local_var = "re";
				const LOCAL_CONSTANT = "re";
				static String static_local = "re";
				String global_var = "re";
			};
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 0);
}

<*
 A compile-time binding crosses the boundary, so redeclaring it in a nested
 function is the one case that still clashes.
*>
fn void a_lambda_may_not_reuse_a_comptime_name()
{
	String source_code = `
		module hello;

		fn void main()
		{
			var $comptime_var = "bon matin";

			var foo = fn void()
			{
				var $comptime_var = "re";
			};
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 1);
}

<*
 A local hidden behind a function boundary is invisible, not fatal: the walk
 has to carry on past it and land on the global of the same name.
*>
fn void a_hidden_local_does_not_hide_the_global()
{
	String source_code = `
		module hello;

		String x = "global";

		fn void main()
		{
			String x = "local";

			var foo = fn void()
			{
				String x = "lambda";
			};
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	// The lambda's 'x' finds the global, which a local may shadow.
	test::eq(parser_tests::error_diag_count, 0);
}

<*
 A block does not open a function boundary, so its locals still clash.
*>
fn void a_block_local_still_clashes_with_the_function_local()
{
	String source_code = `
		module hello;

		fn void main()
		{
			String a = "one";
			{
				String a = "two";
			}
		}
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 1);
}

<*
 The lookup rule on its own, without going through the parser: a binding
 hidden behind a function boundary must not end the search, because an outer
 binding of the same name can still be the one in view.
*>
fn void resolve_climbs_past_a_hidden_binding()
{
	Scope* file = scope::new(tmem, { }, null, FILE);
	Scope* outer_fn = scope::new(tmem, { }, file, FUNCTION);
	Scope* block = scope::new(tmem, { }, outer_fn, BLOCK);
	Scope* lambda = scope::new(tmem, { }, block, FUNCTION);

	scope::add_variable(file, tmem, "x", null, GLOBAL);
	scope::add_variable(outer_fn, tmem, "x", null, RUNTIME);
	scope::add_variable(block, tmem, "b", null, RUNTIME);

	// From inside the enclosing function the runtime local is what is in view.
	VariableInfo* from_block = scope::resolve(block, "x");
	test::ne(from_block, null);
	test::eq(from_block.scope, outer_fn);

	// From inside the lambda that local is hidden, and the global takes over.
	VariableInfo* from_lambda = scope::resolve(lambda, "x");
	test::ne(from_lambda, null);
	test::eq(from_lambda.scope, file);
	test::eq(from_lambda.binding, BindingKind.GLOBAL);

	// A runtime local of an enclosing block does not.
	test::eq(scope::resolve(lambda, "b"), null);
	test::eq(scope::resolve(block, "b").scope, block);

	test::eq(scope::resolve(lambda, "nope"), null);
}

<*
 Shadowing a global is a privilege of the code inside a function; at file
 scope the same name twice is a redefinition.
*>
fn void two_globals_of_the_same_name_clash()
{
	String source_code = `
		module hello;

		int a = 1;
		int a = 2;
	`;
	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");

	test::eq(parser_tests::error_diag_count, 1);
}
