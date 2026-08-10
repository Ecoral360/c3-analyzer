<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module analyzer::parser;
import analyzer::core;
import analyzer::lexer;

import std::io;
import std::collections::list;

<*
 @require t.kind == IDENT
*>
fn Ident* parse_identifier(ContextScope scope, Token t) 
{   
	ParseContext* ctx = scope.ctx;
	String name = t.value;
	if (!constants::is_valid_name(name)) 
	{
		diagnostics::error(ctx.context, t.range, "Reserved identifier");
		return null;
	}

	return ctx.ident(ctx.current);
}

<*
 parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray parse_parameter_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	Range start = ctx.current.range;

	List{Node*} temp_params; temp_params.init(tmem, 4);

	if (!flags.is_call)
	{
		if (!consume(ctx, LPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '(' before parameter list");
			return alloc::clone_slice(ctx.allocator, temp_params.array_view());
		}
	}

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		if (flags.is_macro && ctx.is(EOS)) break;

		Range param_start = ctx.current.range;

		Node* param = parse_param_decl(scope);
		temp_params.push(param);

		if (ctx.current.range == param_start)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Invalid parameter declaration");
			skip_until(ctx, { COMMA, RPAREN, EOS });
			break;
		}

		if (consume(ctx, COMMA))
		{
			if (ctx.is(RPAREN))
			{
				diagnostics::error(ctx.context, ctx.current.range, "Trailing comma in parameter list");
				break;
			}
		}
		else if (!ctx.is(RPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ',' or ')' in parameter list");
			skip_until(ctx, { RPAREN, EOS });
			break;
		}
	}

	if (!flags.is_call && !flags.is_macro)
	{
		if (!consume(ctx, RPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close parameter list");
		}
	}

	return alloc::clone_slice(ctx.allocator, temp_params.array_view());
}

fn void parse_macro_params(ContextScope scope, Node* macro_node)
{
	ParseContext* ctx = scope.ctx;
	NodeArray params = parse_parameter_list(scope.with_flags({ .is_macro = true }));
	MacroDecl* mac   = macro_node.as(MacroDecl);
	mac.params = params;

	if (consume(ctx, EOS))
	{
		Token at_tok = ctx.current;
		expect(ctx, mac, AT_IDENT);

		BodyParamDecl* body_param_node = ctx.ast.alloc_node(BodyParamDecl, at_tok.range);
		
		if (ctx.is(LPAREN))
		{
			body_param_node.params = parse_parameter_list(scope);
		}
	}

	expect(ctx, mac, RPAREN);
}

<*
 generic_param_list ::= '{' expr ( ',' expr )* '}'
*>
fn NodeArray parse_generics_list(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	if (!consume(ctx, LBRACE)) return { };
	List{Node*} params;
	params.init(tmem, 4);

	while (!ctx.eof())
	{
		if (ctx.is(RBRACE)) break;
		Node* param = parse_expr(scope);
		params.push(param);
		if (!consume(ctx, COMMA)) break;
	}

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected closing '}' after generic parameter list");
	}

	return alloc::clone_slice(ctx.allocator, params.array_view());
}

fn Node* parse_contract_param(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ContractParam* node = ctx.ast.alloc_node(ContractParam, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;

	if (consume(ctx, LBRACKET))
	{
		node.by_ref = consume(ctx, AMP);

		String modifier_name = ctx.current.value;
		switch (modifier_name)
		{
			case "in":
				node.modifier = IN;
				break;
			case "inout":
				node.modifier = INOUT;
				break;
			case "out":
				node.modifier = OUT;
				break;
			default:
				diagnostics::error(ctx.context, ctx.current.range, "Expected 'in', 'out', or 'inout'");
				node.flags.has_error = true;
		}

		advance(ctx);

		if (!consume(ctx, RBRACKET))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ']' after contract modifier");
			node.flags.has_error = true;
			skip_until(ctx, { IDENT, CT_IDENT, TYPE_IDENT, CT_TYPE_IDENT, HASH_IDENT, ELLIPSIS });
		}
	}

	switch (ctx.current.kind)
	{
		case IDENT:
		case CT_IDENT:
		case TYPE_IDENT:
		case CT_TYPE_IDENT:
		case HASH_IDENT:
		case ELLIPSIS:
			break;
		default:
			diagnostics::error(ctx.context, ctx.current.range, "Expected parameter name or type");
			node.flags.has_error = true;
			break;
	}

	if (ctx.current.kind != ELLIPSIS)
	{
		node.ident = ctx.ident(ctx.current);
		advance(ctx);
	}

	if (consume(ctx, COLON))
	{
		if (ctx.is(STRING_LITERAL))
		{
			node.description = ctx.ident(ctx.current);
			advance(ctx);
		}
		else 
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected string description after ':'");
			node.flags.has_error = true;
		}
	}
	else if (ctx.is(STRING_LITERAL))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' before description string");
		node.description = ctx.ident(ctx.current);
		advance(ctx);
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 param_list ::= ('...' arg | arg (',' arg)*)?
 parameter ::= ((param_path '=')? expr) | param_path
*>
fn NodeArray parse_arg_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} args;
	args.tinit();

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		int pos_before = ctx.pos;
		Node* expr = null;
		Range start_pos = ctx.current.range;
		if (ctx.is(RPAREN)) break;

		diagnostics::log_debug("parse arg - %s", ctx.current.value);

		if (ctx.is(ELLIPSIS) && ctx.peek(1).kind == CT_VAARG)
		{
			expr = parse_vasplat_expr(scope);
		}
		else
		{
			expr = parse_expr(scope.with_only_flags({ .type_as_expression = true }));

			if (expr.kind == IDENT_EXPR && consume(ctx, COLON))
			{
				IdentExpr* ident  = expr.as(IdentExpr);
				expr = (Node*)ctx.ast.alloc_node(NamedArgExpr, start_pos);
				NamedArgExpr* named = expr.as(NamedArgExpr);
				named.name = ident.ident;

				named.value = parse_expr(scope);
				named.range.end = ctx.peek(-1).range.end;
			}
			else if (expr.kind == CT_EVAL_EXPR && consume(ctx, COLON))
			{
				Node* inner = expr;
				expr = (Node*)ctx.ast.alloc_node(EvalNamedArgExpr, start_pos);
				EvalNamedArgExpr* eval_named = expr.as(EvalNamedArgExpr);

				eval_named.name = inner;
				eval_named.value = parse_expr(scope);
				eval_named.range.end = ctx.peek(-1).range.end;
			}
		}

		diagnostics::log_debug("parse arg AFTER - %s", ctx.current.value);

		args.push(expr);

		if (ctx.pos == pos_before)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Parser loop stalled in argument list at token: %s", ctx.current.kind);
			advance(ctx); 
		}

		if (!consume(ctx, COMMA)) break;
		if (ctx.is(RPAREN)) break;
	}

	return alloc::clone_slice(ctx.allocator, args.array_view());
}

<*
 parse short body: =>
 wraps the short body in a compound and a return
*>
fn Node* parse_short_body(ContextScope scope, bool is_regular)
{
	ParseContext* ctx = scope.ctx;
	Range pos = ctx.current.range;

	Node* expr = parse_expr(scope);
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
	node_comp.statements = alloc::alloc_array(ctx.allocator, Node*, 1);
	node_comp.statements[0] = stmt;

	if (is_regular)
	{
		if (!consume(ctx, EOS))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected valid interface type");
			error_node(ctx, node_comp);
		}
	}
	
	return (Node*)node_comp;
}

<*
 Parse an optional parenthesized list of interface type expressions.
 interface_type_list ::= '(' type_expr (',' type_expr)* ')' | empty
*>
fn NodeArray parse_interface_type_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} interfaces;
	interfaces.init(tmem, 4);

	if (!consume(ctx, LPAREN))
	{
		return alloc::clone_slice(ctx.allocator, interfaces.array_view());
	}

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		Node* interface_type = parse_type_expr(scope, null);

		if (interface_type) 
		{
			interfaces.push(interface_type);
		} 
		else 
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected valid interface type");
			skip_until(ctx, { COMMA, RPAREN });
		}

		if (consume(ctx, COMMA)) 
		{
			if (ctx.is(RPAREN)) 
			{
				diagnostics::error(ctx.context, ctx.current.range, "Unexpected trailing comma in interface list");
				break;
			}
		} 
		else if (!ctx.is(RPAREN)) 
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ',' or ')'");
			skip_until(ctx, { RPAREN });
			break;
		}
	}

	if (!consume(ctx, RPAREN)) 
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close interface list");
	}

	return alloc::clone_slice(ctx.allocator, interfaces.array_view());
}