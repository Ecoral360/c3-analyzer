module cursor_tests @test;

import parser_tests;

import analyzer::core;
import analyzer::cursor;

import std::io;

<*
 A function whose body holds 'return a + b;'. Written with explicit escapes so
 every line and column in the tests below can be counted by hand:

   line 0: module hello;
   line 1: fn int add(int a, int b)
   line 2: {
   line 3: \treturn a + b;
   line 4: }
*>
const String ADD_SOURCE = "module hello;\nfn int add(int a, int b)\n{\n\treturn a + b;\n}\n";

<*
 The lineage of a location is the chain of nodes that contain it, outermost
 first, ending on the smallest one.
*>
fn void lineage_walks_from_the_root_to_the_innermost_node()
{
	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, ADD_SOURCE);

	// The 'a' of 'return a + b;'.
	NodeArray chain = cursor::lineage(&sf.ast, { .line = 3, .column = 8 });

	test::eq(chain.len, 5);
	test::eq(chain[0].kind, NodeKind.FN_DECL);
	test::eq(chain[1].kind, NodeKind.COMPOUND_STMT);
	test::eq(chain[2].kind, NodeKind.RETURN_STMT);
	test::eq(chain[3].kind, NodeKind.BINARY_EXPR);
	test::eq(chain[4].kind, NodeKind.IDENT_EXPR);

	// Every node in the chain contains the one after it.
	for (usz i = 1; i < chain.len; i++)
	{
		test::eq(chain[i - 1].range.contains_range(chain[i].range), true);
	}

	// The innermost node is the 'a' itself.
	test::eq(chain[4].range.start.line, 3);
	test::eq(chain[4].range.start.column, 8);
	test::eq(chain[4].range.end.column, 9);
}

<*
 Stopping the cursor earlier in the same line stops the chain earlier too.
*>
fn void lineage_stops_at_the_node_under_the_location()
{
	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, ADD_SOURCE);

	// The 'return' keyword, which no expression covers.
	NodeArray chain = cursor::lineage(&sf.ast, { .line = 3, .column = 1 });

	test::eq(chain.len, 3);
	test::eq(chain[0].kind, NodeKind.FN_DECL);
	test::eq(chain[1].kind, NodeKind.COMPOUND_STMT);
	test::eq(chain[2].kind, NodeKind.RETURN_STMT);
}

<*
 A location no node covers - the blank line past the end of the file - has an
 empty lineage rather than a partial one.
*>
fn void lineage_is_empty_where_no_node_reaches()
{
	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, ADD_SOURCE);

	NodeArray chain = cursor::lineage(&sf.ast, { .line = 5, .column = 0 });

	test::eq(chain.len, 0);
}

<*
 A range ends inclusively: a location sitting right after the last character of
 a token still belongs to it, which is where an editor puts the caret when it
 sits at the end of a word.
*>
fn void lineage_includes_the_end_of_a_range()
{
	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, ADD_SOURCE);

	// Right after the 'a' of 'return a + b;'.
	NodeArray chain = cursor::lineage(&sf.ast, { .line = 3, .column = 9 });

	test::eq(chain.len, 5);
	test::eq(chain[4].kind, NodeKind.IDENT_EXPR);
	test::eq(chain[4].range.end.column, 9);
}

<*
 The walk enters only the root that contains the location: a sibling
 declaration contributes nothing, however deep it is.
*>
fn void lineage_follows_a_single_branch()
{
	String source_code = "module hello;\nfn int one() { return 1; }\nfn int two() { return 2 + 3; }\n";

	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, source_code);

	// The '3' of the second function.
	NodeArray chain = cursor::lineage(&sf.ast, { .line = 2, .column = 26 });

	test::eq(chain.len, 5);
	test::eq(chain[0].kind, NodeKind.FN_DECL);
	test::eq(chain[4].kind, NodeKind.LITERAL_EXPR);

	// Nothing from the module declaration or from 'one' is in the chain.
	foreach (node : chain)
	{
		test::eq(node.range.start.line, 2);
	}
}

<*
 A location on a top level declaration that has no children under it - the
 module path - still yields the declaration and that child.
*>
fn void lineage_of_a_top_level_declaration()
{
	AnalyzerContext* context = context::new(tmem);
	SourceFile* sf = parser_tests::parse_source(context, ADD_SOURCE);

	// The 'hello' of 'module hello;'.
	NodeArray chain = cursor::lineage(&sf.ast, { .line = 0, .column = 7 });

	test::eq(chain.len, 2);
	test::eq(chain[0].kind, NodeKind.MODULE_DECL);
	test::eq(chain[1].kind, NodeKind.PATH_EXPR);
}

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

	AnalyzerContext* context = context::new(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	Node* module_node       = mod.nodes[0];
	ModuleDecl* module_decl = module_node.as(ModuleDecl);

	Cursor hello_cursor = ws.find_top_level_statement_at_location("hello.c3", { .line = 4, .column = 10 });
	test::ne(hello_cursor.node, null);
	test::eq(hello_cursor.node.kind, NodeKind.FN_DECL);
}
/*
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
