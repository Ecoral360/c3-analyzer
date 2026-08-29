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
