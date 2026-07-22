module reparse_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void reparsing_simple()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	String source_code_2 = `
        module helloo;
        
        fn void greet() {}
        fn void new_function() {}
    `;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	test::ne(mod, null);
	success = context::process(context, source_code_2, "test");

	Module* mod2 = context.modules.get("helloo")!!;
	test::ne(mod2, null);
}

fn void multi_reparsing()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;


	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	for (int i = 0; i < 99; i++)
	{
		success = context::process(context, source_code, "test");
		test::eq(success, true);
		mod = context.modules.get("hello")!!;
		foreach(node : mod.nodes)
		{
			test::eq(node.flags.has_error, false);
		}
		
	}
}
