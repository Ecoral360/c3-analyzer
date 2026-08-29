module analyzer::parser;

import analyzer::core;
import analyzer::lexer;
import std::collections::list;

fn Node* parse_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current;

	diagnostics::log_debug("parse_stmt: current = %s (%s)", t.value, t.kind.description);

	if (is_type(ctx))
	{
		return parse_decl_stmt(scope);
	}

	switch (t.kind)
	{
		case LBRACE:
			return parse_compound_stmt(scope);
		case SWITCH:
			return parse_switch_stmt(scope);
		case CONTINUE:
		case BREAK:
			return parse_continue_break_stmt(scope);
		case NEXTCASE:
			return parse_nextcase_stmt(scope);
		case RETURN:
			return parse_return_stmt(scope);
		case DEFER:
			return parse_defer_stmt(scope);
		case CT_SWITCH:
			return parse_ct_switch_stmt(scope);
		case IF:
			return parse_if_stmt(scope);
		case CT_IF:
			return parse_ct_if_stmt(scope);
		case FOR:
			return parse_for_stmt(scope);
		case CT_FOR:
			return parse_ct_for_stmt(scope);
		case WHILE:
			return parse_while_stmt(scope);
		case DO:
			return parse_do_while_stmt(scope);
		case FOREACH:
		case FOREACH_R:
			return parse_foreach_stmt(scope);
		case CT_FOREACH:
			return parse_ct_foreach_stmt(scope);
		case CT_ASSERT:
			return parse_ct_assert_stmt(scope);
		case CT_ERROR:
			return parse_ct_error_stmt(scope);
		case CT_ECHO:
			return parse_ct_echo_stmt(scope);
		case VAR:
			return parse_var_decl(scope.with_flags({ .is_var = true, .is_local = true }), null);
		case CONST:
			advance(ctx);
			return parse_var_decl(scope.with_flags({ .is_const = true, .is_local = true }), null);
		case STATIC:
			advance(ctx);
			return parse_var_decl(scope.with_flags({ .is_static = true, .is_local = true }), null);
		case TLOCAL:
			advance(ctx);
			return parse_var_decl(scope.with_flags({ .is_tlocal = true, .is_local = true }), null);
		case ASSERT:
			return parse_assert_stmt(scope);
		case CT_EXPAND:
			return parse_ct_expand_stmt(scope);
		case ASM:
			return parse_asm_block_stmt(scope);
		case HASH_IDENT:
		case IDENT:
		case CONST_IDENT:
		case AMP:
		case AT_CONST_IDENT:
		case AT_IDENT:
		case AT_TYPE_IDENT:
		case BANG:
		case BIT_NOT:
		case BIT_OR:
		case BIT_XOR:
		case BUILTIN:
		case BYTES_LITERAL:
		case CHAR_LITERAL:
		case CT_AND_OP:
		case CT_CONCAT_OP:
		case CT_CONCAT_ASSIGN:
		case CT_CONST_IDENT:
		case CT_DEFINED:
		case CT_EMBED:
		case CT_EVAL:
		case CT_FEATURE:
		case CT_IDENT:
		case CT_OR_OP:
		case CT_REFLECT:
		case CT_STRINGIFY:
		case CT_TERNARY:
		case CT_VAARG:
		case FALSE:
		case INT_DECIMAL_LITERAL:
		case INT_BIN_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case LENGTHOF:
		case LPAREN:
		case MINUS:
		case MINUSMINUS:
		case NULL:
		case OR:
		case PLUS:
		case PLUSPLUS:
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
		case ASTERISK:
		case STRING_LITERAL:
		case TRUE:
			return parse_decl_or_expr_stmt(scope);
		case EOS:
			advance(ctx);
			return (Node*)ctx.ast.alloc_node(NopStmt, t.range);
		default:
			break;
	}


	diagnostics::error(ctx.context, t.range, "Unexpected '%s' found when expecting a statement, synchronizing!", t.kind.description);
	Node* error = ctx.ast.error(t.range);
	synchronize(ctx, STATEMENT);
	return error;
}

fn Node* parse_decl_or_expr_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current;

	Node* expr = parse_expr(scope);

	Range start = t.range;
	if (expr.kind == TYPE_EXPR)
	{
		Node* decl = parse_var_decl(scope, expr);
		return decl;
	}

	diagnostics::log_debug("ParseExprStmt: %s", expr.kind.description);

	ExprStmt* node = ctx.ast.alloc_node(ExprStmt, start);
	node.expr_stmt = expr;
	node.range.end = ctx.current.range.end;

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' to terminate expr_stmt");
		node.flags.has_error = true;
		skip_until(ctx, { EOS, RBRACE });
		consume(ctx, EOS);
	}

	return (Node*)node;
}

<*
 decl_stmt ::= expr ';' | decl
*>
fn Node* parse_decl_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Node* type = parse_type_expr(scope);
	switch (ctx.current.kind)
	{
		case IDENT:
		case CT_IDENT:
			return parse_var_decl(scope, type);
		default:
	}

	Node* expr = parse_expr_resuming_with_left(scope, type, LOWEST);

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' to terminate decl_stmt");
		expr.flags.has_error = true;
		skip_until(ctx, { EOS, RBRACE });
		consume(ctx, EOS);
	}

	return expr;
}

<*
 compound_stmt ::= ('{' stmt* '}')
 @require scope.ctx.current.kind == LBRACE
*>
fn Node* parse_compound_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	CompoundStmt* node = ctx.ast.alloc_node(CompoundStmt, ctx.current.range);
	advance(ctx);

	List{Node*} temp_stmts;
	temp_stmts.init(tmem, 8);

	while (!ctx.is(RBRACE) && !ctx.eof())
	{
		Range start_range = ctx.current.range;
		Node* stmt = parse_stmt(scope);
		if (ctx.current.range == start_range)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in block");
			node.flags.has_error = true;
			skip_until(ctx, { EOS, RBRACE });
			if (consume(ctx, EOS)) continue;
		}
		else
		{
			if (stmt.flags.has_error) node.flags.has_error = true;
			temp_stmts.push(stmt);
		}
	}

	// Take the closing brace's end before consuming it. Reading
	// ctx.current afterwards would put the block's range end on the first
	// token of whatever follows, which pushes the body outside its own
	// declaration and breaks scope nesting.
	Range closing = ctx.current.range;

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '}' to terminate compound");
		node.flags.has_error = true;
	}

	node.range.end = closing.end;
	node.statements = alloc::clone_slice(ctx.allocator, temp_stmts.array_view());

	return (Node*)node;
}

<*
 switch_body ::= '{' (case_stmt | nextcase_stmt | default_stmt)* '}'
*>
fn bool parse_switch_body(ContextScope scope, List{Node*}* cases)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		if (!ctx.is(CASE) && !ctx.is(DEFAULT) && !ctx.is(NEXTCASE))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected 'case', 'nextcase', or 'default' inside switch body");
			skip_until(ctx, { CASE, DEFAULT, NEXTCASE, RBRACE });
			if (ctx.is(RBRACE) || ctx.eof()) break;
		}

		Node* result = null;
		TokenKind kind = ctx.current.kind;

		if (ctx.is(CASE))
		{
			result = parse_case_stmt(scope);
		}
		else if (ctx.is(DEFAULT))
		{
			result = parse_default_stmt(scope);
		}
		else if (ctx.is(NEXTCASE))
		{
			result = parse_nextcase_stmt(scope);
		}

		if (result)
		{
			cases.push(result);
		}
		else
		{
			skip_until(ctx, { CASE, DEFAULT, NEXTCASE, RBRACE });
		}
	}

	return true;
}

<*
 case_stmts ::= (compound_stmt, stmt*)
*>
fn Node* parse_case_stmts(ContextScope scope, int row) => @pool()
{
	ParseContext* ctx = scope.ctx;
	CompoundStmt* compound_node = ctx.ast.alloc_node(CompoundStmt, ctx.current.range);
	defer compound_node.range.end = ctx.current.range.end;

	if (token_type_ends_case(ctx.current.kind))
	{
		Location next_loc = ctx.current.range.start;

		if (next_loc.line > row + 1 && ctx.current.kind != RBRACE)
		{
			diagnostics::error(
				ctx.context,
				ctx.current.range,
				"Fallthrough cases with empty rows/comments need explicit 'break'/'nextcase' or remove spacing."
			);
			compound_node.flags.has_error = true;
		}
	}

	List{Node*} stmts;
	stmts.tinit();

	while (!ctx.eof() && !token_type_ends_case(ctx.current.kind))
	{
		int start_index = ctx.pos;
		Node* child_stmt = parse_stmt(scope.with_only_flags({}));

		// Progress check: Ensure the parser actually consumed tokens
		if (ctx.pos == start_index)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in case body; skipping to next case boundary");
			compound_node.flags.has_error = true;
			skip_until(ctx, { CASE, DEFAULT, NEXTCASE, RBRACE });
			break;
		}

		if (child_stmt)
		{
			if (child_stmt.flags.has_error) compound_node.flags.has_error = true;
			stmts.push(child_stmt);
		}
	}

	compound_node.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());
	compound_node.range.end = ctx.current.range.end;

	return (Node*)compound_node;
}

<*
 case_stmt ::= 'case' expr ('..' expr)? ':' stmt*

*>
fn Node* parse_case_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	Range start = ctx.current.range;
	TokenKind expected = flags.is_comptime ? CT_CASE : CASE;
	if (!ctx.is(expected))
	{
		return (Node*)ctx.ast.error(ctx.current.range);
	}
	advance(ctx); // consume CASE

	CaseStmt* node = ctx.ast.alloc_node(CaseStmt, start);
	defer node.range.end = ctx.current.range.end;

	node.expr = parse_expr(scope);
	if (consume(ctx, DOTDOT))
	{
		node.to_expr = parse_expr(scope);
	}

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after case expression");
		node.flags.has_error = true;
	}

	node.body = parse_case_stmts(scope, start.start.line);

	if (node.body && node.body.flags.has_error)
	{
		node.flags.has_error = true;
	}

	return node;
}

<*
 default_stmt ::= default | $default ':' case_stmts
*>
fn Node* parse_default_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	Range start = ctx.current.range;
	TokenKind expected = flags.is_comptime ? CT_DEFAULT : DEFAULT;
	if (!ctx.is(expected))
	{
		return (Node*)ctx.ast.error(ctx.current.range);
	}
	advance(ctx);

	DefaultStmt* node = ctx.ast.alloc_node(DefaultStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after default expression");
		node.flags.has_error = true;
	}

	node.body = parse_case_stmts(scope, start.start.line);

	if (node.body && node.body.flags.has_error)
	{
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 nextcase_stmt ::= NEXTCASE ((CONST_IDENT ':')? expression)? ';'
 @require scope.ctx.current.kind == NEXTCASE
*>
fn Node* parse_nextcase_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;

	NextcaseStmt* node = ctx.ast.alloc_node(NextcaseStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	advance(ctx); // Consume 'nextcase'

	if (consume(ctx, EOS))
	{
		return node;
	}
	if (ctx.is(CONST_IDENT) && ctx.peek(1).kind == COLON)
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx, 2);
	}
	if (consume(ctx, DEFAULT))
	{
		node.is_default = true;
	}
	else
	{
		node.expr = parse_expr(scope);
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' to terminate 'nextcase'");
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 continue_break_stmt ::= continue | break LABEL? ';'
*>
fn Node* parse_continue_break_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	bool is_continue = consume(ctx, CONTINUE);
	if (!is_continue) consume(ctx, BREAK);

	ContinueBreakStmt* node = ctx.ast.alloc_node(ContinueBreakStmt, start);
	defer node.range.end = ctx.current.range.end;

	node.is_continue = is_continue;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range,
			"Expected ';' after '%s' statement", is_continue ? "continue" : "break");

		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 switch ::= switch LABEL? ('(' cond ')')? switch_body
 @require scope.ctx.current.kind == SWITCH
*>
fn Node* parse_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);

	SwitchStmt* node = ctx.ast.alloc_node(SwitchStmt, start);

	if (ctx.is(CONST_IDENT))
	{
		Token label_tok = ctx.current;
		node.label = ctx.ident(label_tok);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after switch label");
			node.flags.has_error = true;
		}
	}

	if (consume(ctx, LPAREN))
	{
		node.cond = parse_cond_expr(scope);
		if (!consume(ctx, RPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close switch condition");
			node.flags.has_error = true;
		}
	}

	if (!consume(ctx, LBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '{' to start switch body");
		node.flags.has_error = true;
		// Synchronization: Since we missed the '{', we shouldn't attempt to parse the body
		skip_until(ctx, { RBRACE });
	}
	else
	{
		List{Node*} bodies; bodies.tinit();

		parse_switch_body(scope, &bodies);

		node.cases = alloc::clone_slice(ctx.allocator, bodies.array_view());

		if (!consume(ctx, RBRACE))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '}' to close switch body");
			node.flags.has_error = true;
		}
	}

	return node;
}

<*
 return_stmt ::= return expression | return ';'
 @require scope.ctx.current.kind == RETURN
*>
fn Node* parse_return_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	ReturnStmt* node = ctx.ast.alloc_node(ReturnStmt, start);

	if (!ctx.is(EOS))
	{
		node.expr = parse_expr(scope);
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 ct_switch_stmt ::= CT_SWITCH const_expr? ':' ct_case_statement* CT_ENDSWITCH
 ct_case_statement ::= (CT_CASE constant_expr | CT_DEFAULT) ':' opt_stmt_list
 @require scope.ctx.current.kind == CT_SWITCH
*>
fn Node* parse_ct_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	CtSwitchStmt* node = ctx.ast.alloc_node(CtSwitchStmt, start);
	defer node.range.end = ctx.current.range.end;

	if (!ctx.is(COLON))
	{
		node.cond = parse_constant_expr(scope);
		if (node.cond && node.cond.flags.has_error) node.flags.has_error = true;
	}

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after $switch expression");
		node.flags.has_error = true;
	}

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDSWITCH))
	{
		if (!ctx.is(CT_CASE) && !ctx.is(CT_DEFAULT))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '$case' or '$default' in $switch");
			node.flags.has_error = true;

			// Sync to the next recognizable part of the switch
			skip_until(ctx, { CT_CASE, CT_DEFAULT, CT_ENDSWITCH });
			continue;
		}

		Node* stmt = null;
		if (ctx.is(CT_CASE))
		{
			stmt = parse_case_stmt(scope.with_only_flags({ .is_comptime = true }));
		}
		else
		{
			stmt = parse_default_stmt(scope.with_only_flags({ .is_comptime = true }));
		}

		if (stmt)
		{
			if (stmt.flags.has_error) node.flags.has_error = true;
			stmts.push(stmt);
		}
	}

	if (!consume(ctx, CT_ENDSWITCH))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '$endswitch' to terminate $switch");
		node.flags.has_error = true;
	}

	node.cases = alloc::clone_slice(ctx.allocator, stmts.array_view());

	return node;
}

<*
 if_stmt ::= IF LABEL? '(' cond_expr ')' compound_stmt (ELSE compound_stmt)?
	| IF LABEL? '(' cond_expr ')' statement
	@require scope.ctx.current.kind == IF
*>
fn Node* parse_if_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);
	IfStmt* node = ctx.ast.alloc_node(IfStmt, start);
	defer node.range.end = ctx.current.range.end;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after if-label");
			node.flags.has_error = true;
		}
	}

	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '(' after 'if'");
		node.flags.has_error = true;
	}

	node.condition = parse_cond_expr(scope);

	if (!node.condition || node.condition.flags.has_error)
	{
		node.flags.has_error = true;
	}

	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close if-condition");
		node.flags.has_error = true;
	}

	node.then_body = parse_stmt(scope);
	if (!node.then_body || node.then_body.flags.has_error)
	{
		node.flags.has_error = true;
	}

	if (consume(ctx, ELSE))
	{
		node.else_body = parse_stmt(scope);
		if (!node.else_body || node.else_body.flags.has_error)
		{
			node.flags.has_error = true;
		}
	}

	return (Node*)node;
}

<*
 ct_if_statement ::= "$if" constant_expression ":" statement* ("$else" statement*)? "$endif"
 @require scope.ctx.current.kind == CT_IF
*>
fn Node* parse_ct_if_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	CtIfStmt* node = ctx.ast.alloc_node(CtIfStmt, start);
	defer node.range.end = ctx.current.range.end;

	node.expr = parse_expr(scope);
	if (node.expr && node.expr.flags.has_error)
	{
		node.flags.has_error = true;
	}

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after $switch expression");
		node.flags.has_error = true;
	}

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
	{
		int start_pos = ctx.pos;
		Node* child_stmt = parse_stmt(scope);

		// Progress check
		if (ctx.pos == start_pos)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in $if body");
			node.flags.has_error = true;
			// Sync to the next branch or end
			skip_until(ctx, { CT_ELSE, CT_ENDIF });
			break;
		}

		if (child_stmt)
		{
			if (child_stmt.flags.has_error) node.flags.has_error = true;
			stmts.push(child_stmt);
		}
	}

	node.then_stmts = alloc::clone_slice(ctx.allocator, stmts.array_view());
	if (consume(ctx, CT_ELSE))
	{
		List{Node*} else_stmts;
		else_stmts.init(tmem, 8);

		while (!ctx.eof() && !ctx.is(CT_ENDIF))
		{
			int start_index = ctx.pos;
			Node* child_stmt = parse_stmt(scope);

			if (ctx.pos == start_index)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in $else body");
				node.flags.has_error = true;
				skip_until(ctx, { CT_ENDIF });
				break;
			}

			if (child_stmt)
			{
				if (child_stmt.flags.has_error) node.flags.has_error = true;
				else_stmts.push(child_stmt);
			}
		}

		node.else_stmts = alloc::clone_slice(ctx.allocator, else_stmts.array_view());
	}

	if (!consume(ctx, CT_ENDIF))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '$endif' to terminate $if block");
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 for_stmt ::= 'for' LABEL? '(' expression_list? ';' cond? ';' expression_list? ')' statement
 @require scope.ctx.current.kind == FOR
*>
fn Node* parse_for_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	ForStmt* node = ctx.ast.alloc_node(ForStmt, start);
	defer node.range.end = ctx.current.range.end;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after label");
			node.flags.has_error = true;
		}
	}

	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '(' after 'for'");
		node.flags.has_error = true;
	}

	if (!ctx.is(EOS))
	{
		node.init.set(parse_expr_list(scope));
	}
	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' in for-loop header");
		node.flags.has_error = true;
	}

	if (!ctx.is(EOS))
	{
		node.cond.set(parse_cond_expr(scope));
	}
	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' in for-loop header");
		node.flags.has_error = true;
	}

	if (!ctx.is(RPAREN))
	{
		node.incr.set(parse_expr_list(scope));
	}
	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close for-loop header");
		node.flags.has_error = true;
	}

	Location prev_loc = ctx.current.range.start;
	node.body = parse_stmt(scope);

	if (node.body && node.body.kind != COMPOUND_STMT)
	{
		Location body_loc = node.body.range.start;
		if (prev_loc.line != body_loc.line)
		{
			diagnostics::error(ctx.context, node.body.range,
				"Single statement after 'for' must be on the same line or in {}");
			node.flags.has_error = true;
		}
	}

	return (Node*)node;
}

<*
 ct_for_stmt ::= "$for" for_condition ":" statement* "$endfor"
 for_condition ::= init_list? ";" condition? ";" update_list?
 @require scope.ctx.current.kind == CT_FOR
*>
fn Node* parse_ct_for_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	CtForStmt* node = ctx.ast.alloc_node(CtForStmt, start);
	defer node.range.end = ctx.current.range.end;

	// init
	if (!ctx.is(EOS))
	{
		node.init.set(parse_expr_list(scope.with_only_flags({ .is_comptime = true })));
	}
	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' after init expression");
		node.flags.has_error = true;
	}

	// cond
	if (!ctx.is(EOS))
	{
		node.cond = parse_expr(scope.with_only_flags({ .is_comptime = true }));
	}
	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' after loop condition");
		node.flags.has_error = true;
	}

	// Update List
	if (!ctx.is(COLON))
	{
		node.incr.set(parse_expr_list(scope.with_only_flags({ .is_comptime = true })));
	}
	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after loop update");
		node.flags.has_error = true;
	}

	CompoundStmt* comp_node = ctx.ast.alloc_node(CompoundStmt, ctx.current.range);
	node.body = comp_node;

	List{Node*} stmts; stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDFOR))
	{
		int start_pos = ctx.pos;
		Node* stmt = parse_stmt(scope);

		// Synchronization check: if we didn't advance, skip to next likely token
		if (ctx.pos == start_pos)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in $for body");
			node.flags.has_error = true;
			skip_until(ctx, { CT_ENDFOR });
			break;
		}

		if (stmt)
		{
			if (stmt.flags.has_error) node.flags.has_error = true;
			stmts.push(stmt);
		}
	}

	if (!consume(ctx, CT_ENDFOR))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '$endfor' to terminate loop");
		node.flags.has_error = true;
	}

	comp_node.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());

	return (Node*)node;
}

<*
 while_stmt ::= 'while' LABEL? '(' cond_expr ')' statement
 @require scope.ctx.current.kind == WHILE
*>
fn Node* parse_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	WhileStmt* node = ctx.ast.alloc_node(WhileStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after label");
			node.flags.has_error = true;
		}
	}

	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '(' to open while header");
		node.flags.has_error = true;
	}

	node.cond = parse_cond_expr(scope);

	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' to close while header");
		node.flags.has_error = true;
	}

	Location prev_loc = ctx.current.range.start;

	node.body = parse_stmt(scope);

	Location body_loc = node.body.range.start;
	if (node.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		diagnostics::error(ctx.context, node.body.range,
				"Single statement after 'while' must be on the same line or in {}");
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 do_while_stmt ::= 'do' LABEL? compound_stmt ('while' '(' cond_expr ')')? ';'
 @require scope.ctx.current.kind == DO
*>
fn Node* parse_do_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	advance(ctx);

	DoWhileStmt* node = ctx.ast.alloc_node(DoWhileStmt, start);
	defer node.range.end = ctx.current.range.end;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after label");
			node.flags.has_error = true;
		}
	}

	node.body = parse_compound_stmt(scope);

	if (consume(ctx, WHILE))
	{
		if (!consume(ctx, LPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '()' to open do header");
			node.flags.has_error = true;
		}

		node.cond.set(parse_cond_expr(scope));

		if (!consume(ctx, RPAREN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ')' after do header");
			node.flags.has_error = true;
		}
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		node.flags.has_error = true;
	}

	return (Node*)node;
}

fn Node* parse_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start  = ctx.current.range;
	VarDecl* var_node = ctx.ast.alloc_node(VarDecl, start);
	defer var_node.range.end = ctx.current.range.end;
	var_node.var_kind = VAR_LOCAL;

	// Parse optional type: if not a plain identifier or '&', a type is expected.
	if (!ctx.is(IDENT) && !ctx.is(AMP))
	{
		var_node.type = parse_type_expr(scope);
	}

	var_node.var_flags.is_ref = consume(ctx, AMP);

	if (!ctx.is(IDENT))
	{
		if (var_node.type != null)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected an identifier after the type.");
			var_node.node.flags.has_error = true;
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected an identifier or type.");
			var_node.node.flags.has_error = true;
		}
		skip_until(ctx, { COMMA, COLON, RPAREN });
		return var_node;
	}

	var_node.name = ctx.ident(ctx.current);
	advance(ctx);

	return (Node*)var_node;
}

<*
 foreach_stmt ::= ("foreach" | "foreach_r") label? "(" foreach_vars ":" expression ")" statement
 foreach_vars ::= foreach_var ("," foreach_var)?
 foreach_var  ::= type? "&"? IDENTIFIER
 @require scope.ctx.current.kind == FOREACH ||scope.ctx.current.kind == FOREACH_R
*>
fn Node* parse_foreach_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	Range start = ctx.current.range;
	bool is_reverse = ctx.is(FOREACH_R);
	advance(ctx);

	ForeachStmt* node = ctx.ast.alloc_node(ForeachStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;
	node.is_reverse = is_reverse;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx);
		if (!consume(ctx, COLON))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after label");
			error_node(ctx, node);
		}
	}

	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '(' after 'foreach'");
		error_node(ctx, node);
	}

	Node* idx_or_variable = parse_foreach_var(scope);
	VarDecl* var_decl = idx_or_variable.as(VarDecl);

	if (consume(ctx, COMMA))
	{
		node.index = idx_or_variable;
		node.index_by_ref = var_decl.var_flags.is_ref;

		node.variable = parse_foreach_var(scope);
		var_decl = node.variable.as(VarDecl);
		node.value_by_ref = var_decl.var_flags.is_ref;
	}
	else
	{
		node.variable = idx_or_variable;
		node.value_by_ref = var_decl.var_flags.is_ref;
	}

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' in foreach");
		node.flags.has_error = true;
	}

	node.enumeration = parse_expr(scope);
	if (!node.enumeration || node.enumeration.flags.has_error)
	{
		error_node(ctx, node);
	}

	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' after foreach statement");
		node.flags.has_error = true;
	}

	node.body = parse_stmt(scope);

	if (!node.body || node.body.flags.has_error)
	{
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 ct_assert_stmt ::= '$assert' constant_expression (":" constant_expression)? ";"
 @require scope.ctx.current.kind == CT_ASSERT
*>
fn Node* parse_ct_assert_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtAssertStmt* node = ctx.ast.alloc_node(CtAssertStmt, start);

	node.expr = parse_constant_expr(scope);
	if (consume(ctx, COLON))
	{
		node.msg_expr.set(parse_constant_expr(scope));

		List{Node*} args; args.tinit();

		while (!ctx.eof() && consume(ctx, COMMA))
		{
			args.push(parse_constant_expr(scope));
		}

		node.args = alloc::clone_slice(ctx.allocator, args.array_view());
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 ct_error_stmt ::= '$error' constant_expression ";"
 @require scope.ctx.current.kind == CT_ERROR
*>
fn Node* parse_ct_error_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtErrorStmt* node = ctx.ast.alloc_node(CtErrorStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	node.expr = parse_constant_expr(scope);

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 ct_echo_stmt ::= '$echo' constant_expression ";"
*>
fn Node* parse_ct_echo_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtEchoStmt* node = ctx.ast.alloc_node(CtEchoStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	node.expr = parse_constant_expr(scope);

	if (!node.expr || node.expr.flags.has_error)
	{
		error_node(ctx, node);
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 defer_statement ::= "defer" defer_kind? statement
 defer_kind      ::= "try"
				  |  "catch"
				  |  "(" "catch" IDENTIFIER ")"
 @require scope.ctx.current.kind == DEFER
*>
fn Node* parse_defer_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	DeferStmt* node = ctx.ast.alloc_node(DeferStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;
	DeferKind kind = NORMAL;

	diagnostics::log_debug("parse_defer");

	if (consume(ctx, TRY))
	{
		node.defer_kind = TRY;
	}
	else if (consume(ctx, CATCH))
	{
		node.defer_kind = CATCH;
	}
	else if (consume(ctx, LPAREN))
	{
		if (consume(ctx, CATCH))
		{
			node.ident = parse_expr(scope);

			// Validate that we actually got an identifier
			if (!node.ident || node.ident.kind != IDENT_EXPR)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected identifier after 'catch'");
				node.flags.has_error = true;
			}

			node.defer_kind = CATCH_VAR;

			if (!consume(ctx, RPAREN))
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected ')'");
				node.flags.has_error = true;
				skip_until(ctx, { RPAREN });
			}
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected 'catch' inside parenthesis");
			node.flags.has_error = true;
			skip_until(ctx, { RPAREN });
		}
	}

	node.defer_kind = kind;

	node.body = parse_stmt(scope);

	if (!node.body || node.flags.has_error)
	{
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 assert_stmt ::= ASSERT '(' assert_expr (',' expr)? ')' ';'
 @require scope.ctx.current.kind == ASSERT
*>
fn Node* parse_assert_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	AssertStmt* node = ctx.ast.alloc_node(AssertStmt, start);

	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '('");
		error_node(ctx, node);
	}

	node.expr = parse_expr(scope);

	if (!node.expr || node.flags.has_error)
	{
		error_node(ctx, node);
	}

	if (consume(ctx, COMMA))
	{
		node.message = parse_constant_expr(scope);

		@pool()
		{
			List{Node*} args;
			args.tinit();

			while (!ctx.eof() && consume(ctx, COMMA))
			{
				args.push(parse_expr(scope));
			}

			node.args = alloc::clone_slice(ctx.allocator, args.array_view());
		};
	}

	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')'");
		error_node(ctx, node);
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
		error_node(ctx, node);
	}

	return (Node*)node;
}

<*
 ct_foreach_stmt ::= '$foreach' ct_foreach_vars ':' expression ':' statement* '$endforeach'
 ct_foreach_vars ::= CT_IDENT (',' CT_IDENT)?
*>
fn Node* parse_ct_foreach_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	CtForeachStmt* node = ctx.ast.alloc_node(CtForeachStmt, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;
	advance(ctx);

	Node* idx_or_variable = parse_ct_foreach_var(scope);

	if (idx_or_variable && idx_or_variable.flags.has_error)
	{
		error_node(ctx, node);
	}

	if (consume(ctx, COMMA))
	{
		node.index = idx_or_variable;
		node.value = parse_ct_foreach_var(scope);
		if (node.value && node.value.flags.has_error)
		{
			error_node(ctx, node);
		}
	}
	else
	{
		node.value = idx_or_variable;
	}

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after foreach variables");
		node.flags.has_error = true;
	}

	node.expr = parse_expr(scope);

	if (!consume(ctx, COLON))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ':' after expression");
		node.flags.has_error = true;
	}

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDFOREACH))
	{
		Range start = ctx.current.range;
		Node* stmt = parse_stmt(scope);

		// Progress check
		if (ctx.current.range == start)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in $foreach body");
			node.flags.has_error = true;
			skip_until(ctx, { CT_ENDFOREACH });
			break;
		}

		if (stmt)
		{
			if (stmt.flags.has_error) error_node(ctx, node);
			stmts.push(stmt);
		}
	}

	if (!consume(ctx, CT_ENDFOREACH))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '$endforeach' to terminate loop");
		node.flags.has_error = true;
	}

	CompoundStmt* body = ctx.ast.alloc_node(CompoundStmt, ctx.current.range);
	body.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());
	node.body = (Node*)body;

	return node;
}

fn Node* parse_ct_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	VarDecl* node = ctx.ast.alloc_node(VarDecl, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;
	node.var_kind = VAR_LOCAL;

	if (ctx.is(CT_IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "$foreach must have a 'IDENT' identifier");
		node.node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 ct_expand_stmt :: CT_EXPAND '(' expr ')'
 @require scope.ctx.current.kind == CT_EXPAND
*>
fn Node* parse_ct_expand_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtExpandStmt* node = ctx.ast.alloc_node(CtExpandStmt, start);
	defer node.range.end = ctx.peek(-1).range.end;

	// Open Paren
	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '(' after '$expand'");
		error_node(ctx, node);
	}

	// Expression
	node.expr = parse_expr(scope);
	if (!node.expr || node.expr.flags.has_error)
	{
		error_node(ctx, node);
	}

	// Close Paren
	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ')' after '$expand' expression");
		error_node(ctx, node);
	}

	// Terminator
	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' after '$expand' statement");
		error_node(ctx, node);
	}

	return (Node*)node;
}
