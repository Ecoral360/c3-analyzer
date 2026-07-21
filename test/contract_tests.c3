module contract_tests @test;

import parser_tests;

import analyzer::parser;
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
	test::eq(decl.comment.text, "Hello there");
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
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;
	ModuleDecl* mod_decl = mod.nodes[0].as(ModuleDecl);

	test::eq(mod_decl.contract.get()!!.flags.has_error, true);
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
	test::eq(success, true);

	Module* mod = context.modules.get("hello")!!;

	foreach(node : mod.nodes)
	{
		io::printn(node.kind);
	}
	FnDecl* fn_decl = mod.nodes[1].as(FnDecl);
	test::eq(fn_decl.contract.get()!!.flags.has_error, true);
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
	test::eq(contract_decl.comment.text, "this is a comment");
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
	test::eq(decl.comment.text, "Hello there");
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
