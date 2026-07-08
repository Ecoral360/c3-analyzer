<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module analyzer::parser;
import analyzer::core;

import std::io;
import std::collections::list;

import analyzer::core::string_pool;

<*
 @require t.kind == IDENT
*>
fn Ident* parse_identifier(ContextScope scope, Token t) 
{   
	ParseContext* ctx = scope.ctx;
	String name = ctx.token_text(t);
	if (!constants::is_valid_name(name)) 
	{
		unexpected_at(ctx, t, "Reserved identifier");
		return null;
	}

	return ctx.ident(ctx.current());
}

<*
 parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray? parse_parameter_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	if (!flags.is_call)
	{
		expect(ctx, LPAREN)!;
	}

	List{Node*} temp_params;
	temp_params.init(tmem, 4);

	if (ctx.is(RPAREN))
	{
		if (!flags.is_macro)
		{
			advance(ctx)!;
		}
		return alloc::clone_slice(ctx.arena, temp_params.array_view());
	}

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		if (flags.is_macro && ctx.is(EOS))
		{
			break;
		}
		
		Node* param = parse_param_decl(scope)!;
		temp_params.push(param);

		if (!consume(ctx, COMMA)!) break;
	}
	if (!flags.is_call && !flags.is_macro)
	{
		expect(ctx, RPAREN)!;
	}
	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

fn void? parse_macro_params(ContextScope scope, Node* macro_node)
{
	ParseContext* ctx = scope.ctx;
	NodeArray params = parse_parameter_list(scope.with_flags({ .is_macro = true }))!;
	MacroDecl* mac   = macro_node.as(MacroDecl);
	mac.params = params;

	if (consume(ctx, EOS)!)
	{
		Token at_tok = ctx.current();
		expect(ctx, AT_IDENT)!;

		BodyParamDecl* body_param_node = ctx.ast.alloc_node(BodyParamDecl, at_tok.pos);
		
		if (ctx.is(LPAREN))
		{
			body_param_node.params = parse_parameter_list(scope)!;
		}
	}

	expect(ctx, RPAREN)!;
}

<*
 generic_param_list ::= '{' expr ( ',' expr )* '}'
*>
fn NodeArray? parse_generics_list(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	if (!consume(ctx, LBRACE)!) return { };
	List{Node*} params;
	params.init(tmem, 4);

	while (true)
	{
		if (ctx.is(RBRACE)) break;
		Node* param = parse_expr(scope)!;
		params.push(param);
		if (!consume(ctx, COMMA)!) break;
	}

	if (!consume(ctx, RBRACE)!)
	{
		ctx.error("Expected closing '}' after generic parameter list");
		return { };
	}

	return alloc::clone_slice(ctx.arena, params.array_view());
}

fn Node*? parse_contract_param(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start = ctx.current().pos;

	ContractParam* node = ctx.ast.alloc_node(ContractParam, start);
	defer node.offset.end = ctx.peek(-1)!!.end_pos();

	if (consume(ctx, LBRACKET)!)
	{
		node.by_ref = consume(ctx, AMP)!;
		String modifier_name = ctx.token_text(ctx.current());
		switch (modifier_name)
		{
			case "in":
				node.modifier = IN;
				advance(ctx)!;
				break;
			case "inout":
				node.modifier = INOUT;
				advance(ctx)!;
				break;
			case "out":
				node.modifier = OUT;
				advance(ctx)!;
				break;
			default:
				ctx.error("'in', 'out' or 'inout' expected");
				ctx.skip_until({ EOS, EOF })!;
				return ctx.ast.error(ctx.current().pos);
		}

		if (!consume(ctx, RBRACKET)!)
		{
			ctx.error("Expected a closing ']'");
			ctx.skip_until({ EOS, EOF })!;
			return ctx.ast.error(ctx.current().pos);
		}
	}

	switch (ctx.current().kind)
	{
		case IDENT:
		case CT_IDENT:
		case TYPE_IDENT:
		case CT_TYPE_IDENT:
		case HASH_IDENT:
		case ELLIPSIS:
			break;
		default:
			ctx.error("Expected parameter name");
			ctx.skip_until({ EOS, EOF })!;
			return ctx.ast.error(ctx.current().pos);
	}

	if (ctx.current().kind != ELLIPSIS)
	{
		node.ident = ctx.ident(ctx.current());
		advance(ctx)!;
	}

	if (ctx.is(COLON))
	{
		advance(ctx)!;
		node.description = ctx.ident(ctx.current());
		advance(ctx)!;
	}
	else if (ctx.is(STRING_LITERAL))
	{
		ctx.error("Expected ':' before string");
		ctx.skip_until({ EOS, EOF })!;
		return ctx.ast.error(ctx.current().pos);
	}

	return (Node*)node;
}

<*
 param_list ::= ('...' arg | arg (',' arg)*)?
 parameter ::= ((param_path '=')? expr) | param_path
*>
fn NodeArray? parse_arg_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} args;
	args.tinit();

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		int pos_before = ctx.pos;
		Node* expr    = null;
		int start_pos = ctx.current().pos;
		if (ctx.is(RPAREN)) break;

		plog::debug("parse arg - %s", ctx.current_text());

		if (ctx.is(ELLIPSIS) && ctx.can_peek(1) && ctx.peek(1)!.kind == CT_VAARG)
		{
			expr = parse_vasplat_expr(scope)!;
		}
		else
		{
			expr = parse_expr(scope.with_only_flags({ .type_as_expression = true }))!;

			if (expr.kind == IDENT_EXPR && consume(ctx, COLON)!)
			{
				IdentExpr* ident  = expr.as(IdentExpr);
				expr = (Node*)ctx.ast.alloc_node(NamedArgExpr, start_pos);
				NamedArgExpr* named = expr.as(NamedArgExpr);
				named.name = ident.ident;

				named.value = parse_expr(scope)!;
				expr.offset.end = ctx.current().pos;
			}
			else if (expr.kind == CT_EVAL_EXPR && consume(ctx, COLON)!)
			{
				Node* inner = expr;
				expr = (Node*)ctx.ast.alloc_node(EvalNamedArgExpr, start_pos);
				EvalNamedArgExpr* eval_named = expr.as(EvalNamedArgExpr);

				eval_named.name = inner;
				eval_named.value = parse_expr(scope)!;
				expr.offset.end = ctx.current().pos;
			}
		}

		plog::debug("parse arg AFTER - %s", ctx.current_text());

		args.push(expr);

		if (ctx.pos == pos_before)
		{
			plog::error("Parser loop stalled in argument list at token: %s", ctx.current().kind);
			advance(ctx)!; 
		}

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(RPAREN)) break;
	}

	return alloc::clone_slice(ctx.arena, args.array_view());
}

<*
 parse short body: =>
 wraps the short body in a compound and a return
*>
fn Node*? parse_short_body(ContextScope scope, bool is_regular)
{
	ParseContext* ctx = scope.ctx;
	int pos = ctx.current().pos;

	Node* expr = parse_expr(scope)!;
	Node* stmt = null;
	
	bool is_macro_call = (expr.kind == CALL_EXPR && expr.as(CallExpr).macro_body_expr);

	if (is_macro_call)
	{
		ExprStmt* ex_stmt = ctx.ast.alloc_node(ExprStmt, pos);
		ex_stmt.expr_stmt = expr;
		stmt = (Node*)ex_stmt;
		
		expr.as(CallExpr).is_outer_call = true;
		is_regular = false;
	}
	else
	{
		ReturnStmt* ret = ctx.ast.alloc_node(ReturnStmt, pos);
		ret.expr = expr;
		stmt = (Node*)ret;
	}

	CompoundStmt* node_comp = ctx.ast.alloc_node(CompoundStmt, pos);
	node_comp.statements = alloc::alloc_array(ctx.arena, Node*, 1);
	node_comp.statements[0] = stmt;

	if (is_regular)
	{
		expect(ctx, EOS)!;
	}
	
	return (Node*)node_comp;
}
