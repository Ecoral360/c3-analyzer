module analyzer::parser;

import analyzer::core;
import analyzer::lexer;

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
 @require scope.ctx.current.kind == FN
*>
fn Node* parse_fn_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	Range start = ctx.current.range;

	advance(ctx); // Consume 'fn'

	diagnostics::log_debug("parse_fn");

	FnDecl* node = scope.ctx.ast.alloc_node(FnDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (!parse_fn_name_and_type(scope, node))
	{
		node.flags.has_error = true;
		skip_until(ctx, { LPAREN, LBRACE, RBRACE, EOS });
		return (Node*)node;
	}

	node.params = parse_parameter_list(scope.with_flags({ .is_function = true }));

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}

	if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		node.attributes = parse_attributes(scope, node, { .allow_type_ident = true });
	}

	if (!parse_fn_body(scope, node))
	{
		node.flags.has_error = true;
		skip_until(ctx, { RBRACE, EOS });
	}

	return node;
}

fn bool parse_fn_name_and_type(ContextScope scope, FnDecl* func) @local 
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	func.ret_type = parse_type_expr(scope);
	if (!func.ret_type)
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected return type");
		return false;
	}

	if (is_type(ctx))
	{
		if (flags.is_interface)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Interfaces cannot be methods");
			return false;
		}

		diagnostics::log_debug("parse_fn - set associated: %s", ctx.current.value);

		func.associated_type = parse_type_expr(scope);
		if (!func.associated_type) return false;

		if (expect(ctx, func, DOT).kind == ERROR) return false;

		Token t = expect(ctx, func, IDENT);
		if (t.kind == ERROR) return false;
		func.name = ctx.ident(t);
	}
	else
	{
		Token t = expect(ctx, func, IDENT);		
		if (t.kind == ERROR) return false;
		func.name = ctx.ident(t);
	}

	return true;
}

fn bool parse_fn_body(ContextScope scope, FnDecl* func)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	Range start = ctx.current.range;

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			diagnostics::error(ctx.context, start, "Extern functions cannot have a structural block body");
			ctx.ast.error(start);
			return false;
		}

		if (flags.is_interface)
		{
			diagnostics::error(ctx.context, start, "Interface methods cannot have a body");
			ctx.ast.error(start);
			return false;
		}

		func.body = parse_compound_stmt(scope);
		if (func.body)
		{
			func.range.end = func.body.range.end;
		}
	}
	else if (consume(ctx, IMPLIES))
	{
		if (flags.is_extern)
		{
			diagnostics::error(ctx.context, start, "Extern functions cannot have an expression body");
			ctx.ast.error(start);
			return false;
		}

		func.body = parse_short_body(scope, true);
		if (func.body)
		{
			func.range.end = func.body.range.end;
		}
	}
	else
	{
		func.range.end = ctx.current.range.end;
		expect(ctx, func, EOS);
	}

	return true;
}
