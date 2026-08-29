module contract_tests @test;

import parser_tests;

import analyzer::parser;
import analyzer::cursor;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;


fn void contract_with_expr_checks()
{
	String source_code = `
		module hello;

		<*
			Hello there
			@param [in] a : "my param"
			@require a > 0
			@ensure return > 0
		*>
		fn int foo(int a) {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	FnDecl* fn_decl = mod.nodes[1].as(FnDecl);
	ContractDecl* decl = fn_decl.contract.get()!!.as(ContractDecl);
	test::ne(decl.comment, null);
	test::eq(decl.comment.text.trim(), "Hello there");
	test::eq(decl.deprecated, null);
	test::eq(decl.ensures.len, 1);
	test::eq(decl.requires.len, 1);
	test::eq(decl.params.len, 1);

	{
		Node* req_expr     = decl.requires[0];
		ContractExpr* expr = req_expr.as(ContractExpr);
		ExprList* list     = expr.exprs.as(ExprList);
		BinaryExpr* bin    = list.exprs[0].as(BinaryExpr);
		test::eq(bin.left.as(IdentExpr).ident.text, "a");
		test::eq(bin.op, OperatorKind.OP_GT);
		test::eq(bin.right.as(LiteralExpr).integer, 0u);
	}

	{
		Node* req_expr     = decl.ensures[0];
		ContractExpr* expr = req_expr.as(ContractExpr);
		ExprList* list     = expr.exprs.as(ExprList);
		BinaryExpr* bin    = list.exprs[0].as(BinaryExpr);
		test::ne(bin.left, null);
		test::eq(bin.left.as(IdentExpr).ident.text, "return");
		test::eq(bin.op, OperatorKind.OP_GT);
		test::eq(bin.right.as(LiteralExpr).integer, 0u);
	}

	{
		Node* param         = decl.params[0];
		ContractParam* expr = param.as(ContractParam);
		test::eq(expr.ident.text, "a");
		test::eq(expr.modifier, InOutModifier.IN);
		test::eq(expr.description.text, "\"my param\"");
	}
}

fn void module_duplicate_contract_error()
{
	String source_code = `
		<* first doc *>
		<* second doc *>
		module hello;

		fn void foo() {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, false);
}

fn void function_duplicate_contract_error()
{
	String source_code = `
		module hello;

		<* first doc *>
		<* second doc *>
		fn void foo() {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, false);
}

fn void contract_description()
{
	String source_code = `
		module hello;

		<*
		 this is a comment
		*>
		fn void foo() {}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	FnDecl* fn_decl = mod.nodes[1].as(FnDecl);
	ContractDecl* contract_decl = fn_decl.contract.get()!!.as(ContractDecl);
	test::ne(contract_decl.comment, null);
	test::eq(contract_decl.comment.text.trim(), "this is a comment");
}

fn void contract_with_deprecated()
{
	String source_code = `
		module hello;

		<*
			Hello there
			@param [in] a : "my param"
			@require a > 0
			@ensure return > 0
			@deprecated "This is deprecated!"
			@pure
		*>
		fn int foo(int a) {}
	`;

	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	test::eq(parser_tests::count_kind(mod, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(mod, FN_DECL), 1);

	FnDecl* fn_decl = mod.nodes[1].as(FnDecl);
	ContractDecl* decl = fn_decl.contract.get()!!.as(ContractDecl);
	test::ne(decl.comment, null);
	test::eq(decl.comment.text.trim(), "Hello there");
	test::eq(decl.ensures.len, 1);
	test::eq(decl.requires.len, 1);
	test::eq(decl.params.len, 1);
	test::eq(decl.is_pure, true);

	{
		AttributeDecl* attr = decl.deprecated.as(AttributeDecl);
		test::eq(attr.attribute_kind, AttributeKind.DEPRECATED);
		LiteralExpr* lit = attr.exprs[0].as(LiteralExpr);
		test::eq(lit.string, "This is deprecated!");
	}

	{
		Node* req_expr     = decl.requires[0];
		ContractExpr* expr = req_expr.as(ContractExpr);
		ExprList* list     = expr.exprs.as(ExprList);
		BinaryExpr* bin    = list.exprs[0].as(BinaryExpr);
		test::eq(bin.left.as(IdentExpr).ident.text, "a");
		test::eq(bin.op, OperatorKind.OP_GT);
		test::eq(bin.right.as(LiteralExpr).integer, 0u);
	}

	{
		Node* req_expr     = decl.ensures[0];
		ContractExpr* expr = req_expr.as(ContractExpr);
		ExprList* list     = expr.exprs.as(ExprList);
		BinaryExpr* bin    = list.exprs[0].as(BinaryExpr);
		test::ne(bin.left.kind, NodeKind.ERROR);
		test::eq(bin.left.as(IdentExpr).ident.text, "return");
		test::eq(bin.op, OperatorKind.OP_GT);
		test::eq(bin.right.as(LiteralExpr).integer, 0u);
	}

	{
		Node* param         = decl.params[0];
		ContractParam* expr = param.as(ContractParam);
		test::eq(expr.ident.text, "a");
		test::eq(expr.modifier, InOutModifier.IN);
		test::eq(expr.description.text, "\"my param\"");
	}
}

fn void contract_on_every_decl_kind()
{
	String source_code = `
		module hello;

		<* doc module *>
		module hello::sub;

		<* doc enum *>
		enum Color { RED, GREEN }

		<* doc alias *>
		alias Ints = int[4];

		<* doc typedef *>
		typedef Meters = int;

		<* doc attrdef *>
		attrdef @Packed = { @packed };

		<* doc struct *>
		struct Point { int x; }

		<* doc interface *>
		interface Printable { fn void print(); }

		<* doc faultdef *>
		faultdef OOPS;

		<* doc global *>
		int counter;

		<* doc macro *>
		macro one() { return 1; }

		<* doc fn *>
		fn void go() {}
	`;
	AnalyzerContext* context = context::create(tmem);
	bool success = context::process(context, source_code, "test");
	test::eq(success, true);

	NodeKind[] kinds = {
		NodeKind.ENUM_DECL,
		NodeKind.ALIAS_DECL,
		NodeKind.TYPEDEF_DECL,
		NodeKind.ATTRDEF_DECL,
		NodeKind.STRUCT_DECL,
		NodeKind.INTERFACE_DECL,
		NodeKind.FAULTDEF_DECL,
		NodeKind.VAR_DECL,
		NodeKind.MACRO_DECL,
		NodeKind.FN_DECL,
		NodeKind.MODULE_DECL,
	};

	foreach (kind : kinds)
	{
		Node* found;

		Module*[2] mods = { context.modules.get("hello")!!, context.modules.get("hello::sub")!! };

		foreach (mod_entry : mods)
		{
			foreach (node : mod_entry.nodes)
			{
				if (node != null && node.kind == kind && cursor::contract(node) ?? null)
				{
					found = node;
					break;
				}
			}
			if (found) break;
		}

		if (!found)
		{
			io::printfn("no contract found for %s", kind);
			test::@check(false, "missing contract for %s", kind);
			continue;
		}

		ContractDecl* decl = cursor::contract(found)!!;
		test::ne(decl, null);
		test::ne(decl.comment, null);
	}
}
