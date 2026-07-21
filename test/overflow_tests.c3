module overflow_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_overflow()
{
	String source_code = `
		module hello;
	
		macro void foo()
		{
			$for var $i = 0; $i < $vaarg.len; $i++:
				$x += $vaarg[$i];

			foreach (foo : list)
			{

			}
		}
			
		fn void bar()
		{
		}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, MACRO_DECL), 1);
}
