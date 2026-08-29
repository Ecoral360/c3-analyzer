module visitor_test_helpers;

import analyzer::core;
import analyzer::cursor;

struct KindSet
{
	bool[256] seen;
	int count;
}

fn ChildVisitResult collect(Node* cursor, Node* parent, void* user_data)
{
	KindSet* set = (KindSet*)user_data;
	set.seen[cursor.kind.ordinal] = true;
	set.count++;
	return RECURSE;
}

module visitor_tests @test;

import parser_tests;
import visitor_test_helpers;

import analyzer::core;
import analyzer::cursor;

import std::io;

<*
 Walk a source file that exercises every construct we can express, and check
 that the visitor descends into the nodes each declaration hangs onto.
*>
fn void visit_reaches_every_child()
{
	String source_code = `
		module hello;

		<* doc alias *>
		alias Ints = int[4];

		<* doc typedef *>
		typedef Meters = int;

		<* doc attrdef *>
		attrdef @Packed = @packed;

		<* doc faultdef *>
		faultdef OOPS, BAD;

		<* doc enum *>
		enum Color : char (String name) { RED {"r"}, GREEN {"g"} }

		<* doc interface *>
		interface Printable { fn void print(); }

		bitstruct Flags : char { bool a : 0; bool b : 1; }

		<*
			doc struct
			@param [in] x : "the x"
		*>
		struct Point @Packed
		{
			int x;
			int y;
		}

		<*
			@require a > 0 : "positive"
			@ensure return > 0
		*>
		fn int foo(int a) @inline
		{
			int[4] arr = { 1, 2, 3, 4 };
			Point p = { .x = 1, .y = 2 };
			int b = (int)a;
			int c = a > 0 ? a : -a;
			int d = arr[1..2].len;
			assert(a > 0, "boom %d", a);
			int n = $$sizeof(a);
			String fname = $$FUNC;
			$assert a != 1 : "nope";
			$echo "hi";
			defer c = 0;
			if (catch err = foo(a)) { return 0; }
			if (try v = foo(a)) { c += v; }
			foreach (i, e : arr) { c += e; }
			for (int i = 0; i < 4; i++) { c += i; }
			while (c > 0) { c--; }
			do { c++; } while (c < 3);
			switch (c)
			{
				case 1:
					nextcase 2;
				case 2:
					break;
				default:
					break;
			}
			return a + b + c + d + n;
		}

		<* doc macro *>
		macro @each(int a; @body(int x))
		{
			@body(1);
			return a * 2;
		}

		macro compile_time()
		{
			var $x = 0;
			$for var $i = 0; $i < 2; $i++:
				$x += $i;
			$endfor
			$if $defined($x):
			$endif
			$switch $x:
				$case 1:
				$default:
			$endswitch
			return $x;
		}

		fn void lambdas() @if($feature(SEMA))
		{
			int y = 1;
			var f = fn int(int z) => z + 1;
			int r = f(y);
		}

		<* doc global *>
		int counter @align(8) = 3;
	`;

	parser_tests::start_counting_diags();
	defer parser_tests::stop_counting_diags();

	AnalyzerContext* context = context::new(tmem);
	context::process(context, source_code, "test");
	test::eq(parser_tests::error_diag_count, 0);

	Module* mod = context.modules.get("hello")!!;

	KindSet set;
	foreach (node : mod.nodes)
	{
		if (node == null) continue;
		cursor::visit(node, null, { .on_enter = &visitor_test_helpers::collect }, &set);
	}

	NodeKind[] expected = {
		NodeKind.CONTRACT_DECL,
		NodeKind.CONTRACT_PARAM,
		NodeKind.CONTRACT_EXPR,
		NodeKind.ALIAS_DECL,
		NodeKind.TYPEDEF_DECL,
		NodeKind.ATTRDEF_DECL,
		NodeKind.FAULTDEF_DECL,
		NodeKind.FAULT_DECL,
		NodeKind.ENUM_DECL,
		NodeKind.INTERFACE_DECL,
		NodeKind.STRUCT_DECL,
		NodeKind.MACRO_DECL,
		NodeKind.ATTRIBUTE_DECL,
		NodeKind.BODY_PARAM_DECL,
		NodeKind.ASSERT_STMT,
		NodeKind.NEXTCASE_STMT,
		NodeKind.CT_ASSERT_STMT,
		NodeKind.CT_ECHO_STMT,
		NodeKind.DEFER_STMT,
		NodeKind.CT_FOR_STMT,
		NodeKind.CT_IF_STMT,
		NodeKind.CT_SWITCH_STMT,
		NodeKind.TERNARY_EXPR,
		NodeKind.CAST_EXPR,
		NodeKind.TRY_EXPR,
		NodeKind.CATCH_EXPR,
		NodeKind.LAMBDA_EXPR,
		NodeKind.CALL_EXPR,
		NodeKind.RANGE_EXPR,
		NodeKind.DESIGNATOR_EXPR,
		NodeKind.DESIGNATED_INITIALIZER_EXPR,
		NodeKind.INITIALIZER_LIST_EXPR,
		NodeKind.ACCESS_EXPR,
		NodeKind.LITERAL_EXPR,
		NodeKind.IDENT_EXPR,
		NodeKind.TYPE_EXPR,
		NodeKind.BUILTIN_EXPR,
		NodeKind.CT_DEFINED_EXPR,
		NodeKind.CT_FEATURE_EXPR,
	};

	foreach (kind : expected)
	{
		if (!set.seen[kind.ordinal])
		{
			test::@check(false, "visitor never reached %s", kind);
		}
	}
}
