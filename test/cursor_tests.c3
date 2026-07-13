module cursor_tests @test;

/*

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import analyzer::cursor;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_cursor_test()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	String source_code_2 = `
		module foo;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process_batch(&ws, mem, { 
		{ .uri = "hello.c3", .source_text = source_code }, 
		{ .uri = "foo.c3",   .source_text = source_code_2 }
	})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* module_node       = s.nodes[0];
	ModuleDecl* module_decl = module_node.as(MODULE_DECL);

	foreach (node : s.nodes)
	{
		Location loc = s.source_file.line_map.resolve((sz)node.offset.start);
		io::printfn("Node (%s) - %s:%s", node.kind.description, loc.line, loc.column);
	}

	Cursor hello_cursor = ws.find_top_level_statement_at_location("hello.c3", { .line = 4, .column = 10 });
	test::ne(hello_cursor.node, null);
	test::eq(hello_cursor.node.kind, NodeKind.FN_DECL);
}

fn void node_path()
{
	String source_code = `
		module hello;
		fn Bar foo(FoFn x = fn () => abort(), Foo y = {}) {
			if (x())
			{
				return y;
			}
		}    
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();

	ProcessResult res = workspace::process_batch(&ws, mem, { 
		{ .uri = "hello.c3", .source_text = source_code }, 
	})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];


	Node* module_node       = s.nodes[0];
	ModuleDecl* module_decl = module_node.as(MODULE_DECL);

	List{Cursor} foo_cursors = ws.lookup_cursors("hello", "foo")!!;

	Cursor foo = foo_cursors[0];


	List{Node*} path = cursor::get_node_path(foo.node, 78, s.source_file);
	foreach(n : path)
	{
		io::printfn("%s (%s)", (Cursor){.node = n, .section = s}.spelling(tmem)!!, n.kind);
	}

	test::eq(path.len(), 6);
}

fn void signature_test()
{
	String source_code = `
		module hello;
		fn Bar foo(FoFn x = fn () => abort(), Foo y = {}) {
			if (x)
			{
				return y;
			}
		}    

		fn Bar foo2(FoFn x = fn () => abort(), Foo y = {}) => {};
		extern fn Bar foo3(FoFn x = fn () => abort(), Foo y = {});
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();

	ProcessResult res = workspace::process_batch(&ws, mem, { 
		{ .uri = "hello.c3", .source_text = source_code }, 
	})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* module_node       = s.nodes[0];
	ModuleDecl* module_decl = module_node.as(MODULE_DECL);

	List{Cursor} foo_cursors = ws.lookup_cursors("hello", "foo")!!;
	List{Cursor} foo2_cursors = ws.lookup_cursors("hello", "foo2")!!;
	List{Cursor} foo3_cursors = ws.lookup_cursors("hello", "foo3")!!;

	Cursor foo = foo_cursors[0];
	test::eq(foo.node.kind, NodeKind.FN_DECL);
	test::eq(foo.signature_text()!!, "fn Bar foo(FoFn x = fn () => abort(), Foo y = {})");

	Cursor foo2 = foo2_cursors[0];
	test::eq(foo2.signature_text()!!, "fn Bar foo2(FoFn x = fn () => abort(), Foo y = {})");

	Cursor foo3 = foo3_cursors[0];
	test::eq(foo3.signature_text()!!, "fn Bar foo3(FoFn x = fn () => abort(), Foo y = {})");
}
