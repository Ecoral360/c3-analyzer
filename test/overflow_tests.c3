module overflow_tests @test;

import parser_tests;

import analyzer::workspace;
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

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, MACRO_DECL), 1);
}