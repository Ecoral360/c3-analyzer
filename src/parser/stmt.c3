module analyzer::parser;

import analyzer::core;
import std::collections::list;

fn Node*? parse_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current;

	diagnostics::log_debug("parse_stmt: current = %s (%s)", ctx.token_text(t), t.kind.description);

	if (is_type(ctx))
	{
		return parse_decl_stmt(scope)!;
	}

	switch (t.kind)
	{
		case LBRACE:
			return parse_compound_stmt(scope)!;
		case SWITCH:
			return parse_switch_stmt(scope)!;
		case CONTINUE:
		case BREAK:
			return parse_continue_break_stmt(scope)!;
		case NEXTCASE:
			return parse_nextcase_stmt(scope)!;
		case RETURN:
			return parse_return_stmt(scope)!;
		case DEFER:
			return parse_defer_stmt(scope)!;
		case CT_SWITCH:
			return parse_ct_switch_stmt(scope)!;
		case IF:
			return parse_if_stmt(scope)!;
		case CT_IF:
			return parse_ct_if_stmt(scope)!;
		case FOR:
			return parse_for_stmt(scope)!;
		case CT_FOR:
			return parse_ct_for_stmt(scope)!;
		case WHILE:
			return parse_while_stmt(scope)!;
		case DO:
			return parse_do_while_stmt(scope)!;
		case FOREACH:
		case FOREACH_R:
			return parse_foreach_stmt(scope)!;
		case CT_FOREACH:
			return parse_ct_foreach_stmt(scope)!;
		case CT_ASSERT:
			return parse_ct_assert_stmt(scope)!;
		case CT_ERROR:
			return parse_ct_error_stmt(scope)!;
		case CT_ECHO:
			return parse_ct_echo_stmt(scope)!;
		case VAR:
			return parse_var_decl(scope.with_flags({ .is_var = true, .is_local = true }), null);
		case CONST:
			advance(ctx)!;
			return parse_var_decl(scope.with_flags({ .is_const = true, .is_local = true }), null)!;
		case STATIC:
			advance(ctx)!;
			return parse_var_decl(scope.with_flags({ .is_static = true, .is_local = true }), null)!;
		case TLOCAL:
			advance(ctx)!;
			return parse_var_decl(scope.with_flags({ .is_tlocal = true, .is_local = true }), null)!;
		case ASSERT:
			return parse_assert_stmt(scope)!;
		case CT_EXPAND:
			return parse_ct_expand_stmt(scope)!;
		case ASM:
			return parse_asm_block_stmt(scope)!;
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
			return parse_decl_or_expr_stmt(scope)!;
		case EOS:
			advance(ctx)!;
			return (Node*)ctx.ast.alloc_node(NopStmt, t.pos);
		default:
			break;
	}

	advance(ctx)!;
	return unexpected_at(ctx, t, "Unexpected '%s' found when expecting a statement", t.kind.description);
}

fn Node*? parse_decl_or_expr_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current;

	Node* expr = parse_expr(scope)!;
	
	int start_pos = t.pos;
	if (expr.kind == TYPE_EXPR)
	{
		Node* decl = parse_var_decl(scope, expr)!;
		return decl;
	}

	ExprStmt* node = ctx.ast.alloc_node(ExprStmt, start_pos);
	node.expr_stmt = expr;
	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;
	return (Node*)node;
}

<*
 parse a expression inside a statement
	expr_stmt ::= expr ';'
*>
fn Node*? parse_expr_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current.pos;
	ExprStmt* node = ctx.ast.alloc_node(ExprStmt, start_pos);
	node.expr_stmt = parse_expr(scope)!;
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS);
	return (Node*)node;
}

<*
 decl_stmt ::= expr ';' | decl
*>
fn Node*? parse_decl_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;

	Node* type = parse_type_expr(scope)!;
	switch (ctx.current.kind)
	{
		case IDENT:
		case CT_IDENT:
			return parse_var_decl(scope, type);
		default:
	}

	Node* expr = parse_expr_resuming_with_left(scope, type, LOWEST)!;
	expect(ctx, EOS)!;
	return expr;
}

<*
 compound_stmt ::= ('{' stmt* '}')
*>
fn Node*? parse_compound_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, LBRACE)!;
	CompoundStmt* node = ctx.ast.alloc_node(CompoundStmt, start_pos);

	List{Node*} temp_stmts;
	temp_stmts.init(tmem, 8);

	while (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node*? stmt = parse_stmt(scope);
		if (catch err = stmt)
		{
			ctx.error("Malformed statement inside compound");
			Node* err_node = ctx.ast.error(ctx.current.pos);
			temp_stmts.push(err_node);
			ctx.skip_until({ RBRACE, EOS })!;
			continue;
		}

		if (stmt != null)
		{
			temp_stmts.push(stmt);
		}
	}
	
	node.offset.end = ctx.current_pos();

	expect(ctx, RBRACE)!;

	node.statements = alloc::clone_slice(ctx.allocator, temp_stmts.array_view());

	return (Node*)node;
}

<*
 switch_body ::= '{' (case_stmt | nextcase_stmt | default_stmt)* '}'
*>
fn bool? parse_switch_body(ContextScope scope, List{Node*}* cases)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		if (ctx.eof())
		{
			ctx.error("Unexpected EOF, expected closing '}' for switch body");
			return false;
		}

		Node* result   = null;
		TokenKind kind = ctx.current.kind;

		switch (kind)
		{
			case CASE:
				result = parse_case_stmt(scope)!;
				if (result.kind == ERROR) return false;
			case DEFAULT:
				result = parse_default_stmt(scope)!;
				if (result.kind == ERROR) return false;
			default:
				ctx.error("Expected 'case' or 'default' inside switch body, got '%s'", kind.description);
				return false;
		}

		cases.push(result);
	}

	return true;
}

<*
 case_stmts ::= (compound_stmt, stmt*)
*>
fn Node*? parse_case_stmts(ContextScope scope, sz row) => @pool()
{
	ParseContext* ctx = scope.ctx;

	if (token_type_ends_case(ctx.current.kind))
	{
		Location next_loc = ctx.line_map.resolve(ctx.current.pos);

		if (next_loc.line > row + 1 && ctx.current.kind != RBRACE)
		{
			ctx.error(
				"Fallthrough cases with empty rows or comments have unclear meaning, an explicit 'break' or 'nextcase' is needed (or remove the spacing)."
			);
			return ctx.ast.error(ctx.current.pos);
		}
	}

	CompoundStmt* compound_node = ctx.ast.alloc_node(CompoundStmt, ctx.current.pos);

	List{Node*} stmts;
	stmts.tinit();

	while (!ctx.eof() && !token_type_ends_case(ctx.current.kind))
	{
		Node* child_stmt = parse_stmt(scope.with_only_flags({}))!;
		if (child_stmt.kind == ERROR) return child_stmt;
		stmts.push(child_stmt);
	}

	compound_node.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());
	compound_node.offset.end = ctx.current.pos;

	return (Node*)compound_node;
}

<*
 case_stmt ::= 'case' expr ('..' expr)? ':' stmt*

*>
fn Node*? parse_case_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int pos            = ctx.current.pos;
	TokenKind expected = flags.is_comptime ? CT_CASE : CASE;
	expect(ctx, expected);

	Location loc = ctx.line_map.resolve((sz)pos);
	sz case_row  = loc.line;

	CaseStmt* node = ctx.ast.alloc_node(CaseStmt, pos);
	defer node.offset.end = ctx.current.pos;

	node.expr = parse_expr(scope)!;
	if (consume(ctx, DOTDOT)!)
	{
		node.to_expr = parse_expr(scope)!;
	}
	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	node.body = parse_case_stmts(scope, case_row)!;

	return node;
}

<*
 default_stmt ::= default | $default ':' case_stmts
*>
fn Node*? parse_default_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int start_pos      = ctx.current.pos;
	TokenKind expected = flags.is_comptime ? CT_DEFAULT : DEFAULT;
	@expect_else(ctx, expected ; err)
	{
		return err;
	}!;

	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	DefaultStmt* node = ctx.ast.alloc_node(DefaultStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	Location loc = ctx.line_map.resolve((sz)start_pos);
	sz row       = loc.line;

	node.body = parse_case_stmts(scope, row)!;

	return (Node*)node;
}

<*
 nextcase_stmt ::= NEXTCASE ((CONST_IDENT ':')? expression)? ';'
*>
fn Node*? parse_nextcase_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, NEXTCASE ; err)
	{
		return err;
	}!;

	NextcaseStmt* node = ctx.ast.alloc_node(NextcaseStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	if (consume(ctx, EOS)!)
	{
		return node;
	}
	if (ctx.is(CONST_IDENT) && ctx.peek(1).kind == COLON)
	{
		node.label = ctx.ident(ctx.current);;
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			return err;
		}!;
	}
	if (consume(ctx, DEFAULT)!)
	{
		node.is_default = true;
	}
	else
	{
		node.expr = parse_expr(scope)!;
	}
	return (Node*)node;
}

<*
 continue_break_stmt ::= continue | break LABEL? ';'
*>
fn Node*? parse_continue_break_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos    = ctx.current.pos;
	bool is_continue = consume(ctx, CONTINUE)!;
	if (!is_continue) consume(ctx, BREAK)!;

	ContinueBreakStmt* node = ctx.ast.alloc_node(ContinueBreakStmt, start_pos);

	node.is_continue = is_continue;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);;
		advance(ctx)!;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 switch ::= switch LABEL? ('(' cond ')')? switch_body
*>
fn Node*? parse_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current.pos;
	@expect_else(ctx, SWITCH ; err)
	{
		return err;
	}!;

	SwitchStmt* node = ctx.ast.alloc_node(SwitchStmt, start_pos);

	if (ctx.is(CONST_IDENT))
	{
		Token label_tok = ctx.current;
		node.label = ctx.ident(label_tok);;
		advance(ctx)!;
		expect(ctx, COLON)!;
	}

	if (consume(ctx, LPAREN)!)
	{
		node.cond = parse_cond_expr(scope)!;
		expect(ctx, RPAREN)!;
	}

	expect(ctx, LBRACE)!;

	List{Node*} bodies;
	bodies.tinit();
	bool success = parse_switch_body(scope, &bodies)!;
	if (!success)
	{
		ctx.skip_until({ RBRACE, EOF })!;
	}
	
	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	node.cases = alloc::clone_slice(ctx.allocator, bodies.array_view());
	return node;
}

<*
 return_stmt ::= return expression | return ';'
*>
fn Node*? parse_return_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, RETURN)!;

	ReturnStmt* node = ctx.ast.alloc_node(ReturnStmt, start_pos);

	if (!ctx.is(EOS))
	{
		node.expr = parse_expr(scope)!;
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 ct_switch_stmt ::= CT_SWITCH const_expr? ':' ct_case_statement* CT_ENDSWITCH
 ct_case_statement ::= (CT_CASE constant_expr | CT_DEFAULT) ':' opt_stmt_list
*>
fn Node*? parse_ct_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, CT_SWITCH)!;

	CtSwitchStmt* node = ctx.ast.alloc_node(CtSwitchStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	if (!ctx.is(COLON))
	{
		if (ctx.is(CT_CASE))
		{
			ctx.error("Expected ':' after $switch");
			return ctx.ast.error(ctx.current.pos);
		}

		node.cond = parse_constant_expr(scope)!;
	}

	expect(ctx, COLON)!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDSWITCH))
	{
		TokenKind kind = ctx.current.kind;
		diagnostics::log_debug("parse_ct_switch_stmt - kind: %s", kind.description);
		switch (kind)
		{
			case CT_CASE:
				stmts.push(parse_case_stmt(scope.with_only_flags({ .is_comptime = true }))!);
			case CT_DEFAULT:
				stmts.push(parse_default_stmt(scope.with_only_flags({ .is_comptime = true }))!);
			default:
				ctx.error("'$case' or '$default' expected");
				return ctx.ast.error(ctx.current.pos - 1);
		}
	}

	expect(ctx, CT_ENDSWITCH)!;

	node.cases = alloc::clone_slice(ctx.allocator, stmts.array_view());
	return node;
}

<*
 if_stmt ::= IF LABEL? '(' cond_expr ')' compound_stmt (ELSE compound_stmt)?
	| IF LABEL? '(' cond_expr ')' statement
*>
fn Node*? parse_if_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, IF)!;

	IfStmt* node = ctx.ast.alloc_node(IfStmt, start_pos);

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx)!;
		expect(ctx, COLON)!;
	}

	expect(ctx, LPAREN)!;

	node.condition = parse_cond_expr(scope)!;

	expect(ctx, RPAREN)!;

	node.then_body = parse_stmt(scope)!;
	node.offset.end = node.then_body.offset.end;

	if (consume(ctx, ELSE)!)
	{
		node.else_body = parse_stmt(scope)!;
		node.offset.end = node.else_body.offset.end;
	}
	
	return (Node*)node;
}

<*
 ct_if_statement ::= "$if" constant_expression ":" statement* ("$else" statement*)? "$endif"
*>
fn Node*? parse_ct_if_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, CT_IF ; err)
	{
		return err;
	}!;

	CtIfStmt* node = ctx.ast.alloc_node(CtIfStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	node.expr = parse_expr(scope)!;
	@expect_else(ctx, COLON ; err)
	{
		ctx.skip_until({ EOS, EOF, RBRACE })!;
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
	{
		stmts.push(parse_stmt(scope)!);
	}

	node.then_stmts = alloc::clone_slice(ctx.allocator, stmts.array_view());
	if (ctx.is(CT_ELSE))
	{
		advance(ctx)!;
		stmts.clear();
		while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
		{
			stmts.push(parse_stmt(scope)!);
		}
		node.else_stmts = alloc::clone_slice(ctx.allocator, stmts.array_view());
	}

	@expect_else(ctx, CT_ENDIF ; err)
	{
		return err;
	}!;

	return (Node*)node;
}

<*
 for_stmt ::= 'for' LABEL? '(' expression_list? ';' cond? ';' expression_list? ')' statement
*>
fn Node*? parse_for_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, FOR ; err)
	{
		return err;
	}!;

	ForStmt* node = ctx.ast.alloc_node(ForStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF })!;
			return err;
		}!;
	}

	@expect_else(ctx, LPAREN ; err)
	{
		ctx.skip_until({ RPAREN, EOS, EOF })!;
		return err;
	}!;

	if (!consume(ctx, EOS)!)
	{
		node.init.set(parse_expr_list(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, EOS)!)
	{
		node.cond.set(parse_cond_expr(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, RPAREN)!)
	{
		node.incr.set(parse_expr_list(scope))!;
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current.pos);
	node.body = parse_stmt(scope)!;
	Location body_loc = ctx.line_map.resolve((sz)node.body.offset.start);
	if (node.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'for' must be placed on the same line, or be enclosed in {}");
		return ctx.ast.error(ctx.current.pos);
	}

	return (Node*)node;
}

<*
 ct_for_stmt ::= "$for" for_condition ":" statement* "$endfor"
 for_condition ::= init_list? ";" condition? ";" update_list?
*>
fn Node*? parse_ct_for_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, CT_FOR ; err)
	{
		return err;
	}!;
	
	CtForStmt* node = ctx.ast.alloc_node(CtForStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	if (!consume(ctx, EOS)!)
	{
		node.init.set(parse_expr_list(scope.with_only_flags({ .is_comptime = true })))!;
		expect(ctx, EOS)!;
	}

	node.cond = parse_expr(scope.with_only_flags({ .is_comptime = true }))!;
	expect(ctx, EOS)!;
	
	if (!ctx.is(COLON))
	{
		node.incr.set(parse_expr_list(scope.with_only_flags({ .is_comptime = true })))!;
	}
	expect(ctx, COLON)!;

	CompoundStmt* comp_node = ctx.ast.alloc_node(CompoundStmt, ctx.current_pos());
	node.body = comp_node;
	
	List{Node*} stmts; stmts.tinit();
	while (!ctx.eof() && !consume(ctx, CT_ENDFOR)!)
	{
		Node* stmt = parse_stmt(scope)!;
		stmts.push(stmt);
	}

	comp_node.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());

	return (Node*)node;
}

<*
 while_stmt ::= 'while' LABEL? '(' cond_expr ')' statement
*>
fn Node*? parse_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, WHILE)!;

	WhileStmt* node = ctx.ast.alloc_node(WhileStmt, start_pos);
	defer node.offset.end = ctx.previous_end_pos();

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx)!;
		expect(ctx, COLON)!;
	}
	expect(ctx, LPAREN)!;
	node.cond = parse_cond_expr(scope)!;
	expect(ctx, RPAREN)!;

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current.pos);
	node.body = parse_stmt(scope)!;
	Location body_loc = ctx.line_map.resolve((sz)node.body.offset.start);
	if (node.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'while' must be placed on the same line, or be enclosed in {}.");
		return ctx.ast.error(ctx.current.pos);
	}

	return (Node*)node;
}

<*
 do_while_stmt ::= 'do' LABEL? compound_stmt ('while' '(' cond_expr ')')? ';'
*>
fn Node*? parse_do_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, DO ; err)
	{
		return err;
	}!;

	DoWhileStmt* node = ctx.ast.alloc_node(DoWhileStmt, start_pos);

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF })!;
			return err;
		}!;
	}

	node.body = parse_compound_stmt(scope)!;

	if (consume(ctx, WHILE)!)
	{
		@expect_else(ctx, LPAREN ; err)
		{
			return err;
		}!;
		node.cond.set(parse_cond_expr(scope)!);
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return (Node*)node;
}

fn Node*? parse_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos  = ctx.current.pos;
	VarDecl* var_node = ctx.ast.alloc_node(VarDecl, start_pos);
	defer var_node.offset.end = ctx.current.pos;
	var_node.var_kind = VAR_LOCAL;

	// Parse optional type: if not a plain identifier or '&', a type is expected.
	if (!ctx.is(IDENT) && !ctx.is(AMP))
	{
		var_node.type = parse_type_expr(scope)!;
	}

	var_node.flags.is_ref = consume(ctx, AMP)!;

	if (!ctx.is(IDENT))
	{
		if (var_node.type != null)
		{
			ctx.error("Expected an identifier after the type.");
		}
		else
		{
			ctx.error("Expected an identifier or type.");
		}
		ctx.ast.missing(ctx.current.pos);
		ctx.skip_until({ COMMA, COLON, RPAREN })!;
		return var_node;
	}

	var_node.name = ctx.ident(ctx.current);
	advance(ctx)!;

	return (Node*)var_node;
}

<*
 foreach_stmt ::= ("foreach" | "foreach_r") label? "(" foreach_vars ":" expression ")" statement
 foreach_vars ::= foreach_var ("," foreach_var)?
 foreach_var  ::= type? "&"? IDENTIFIER
*>
fn Node*? parse_foreach_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos   = ctx.current.pos;
	bool is_reverse = ctx.is(FOREACH_R);
	advance(ctx)!;

	ForeachStmt* node = ctx.ast.alloc_node(ForeachStmt, start_pos);
	defer node.offset.end = ctx.peek(-1)!!.pos;
	node.is_reverse = is_reverse;

	if (ctx.is(CONST_IDENT))
	{
		node.label = ctx.ident(ctx.current);
		advance(ctx)!;
		@expect_else_skip(ctx, COLON, { EOS, EOF } ; err)
		{
			return err;
		}!;
	}

	@expect_else_skip(ctx, LPAREN, { RPAREN, EOS, EOF } ; err)
	{
		return err;
	}!;


	Node* idx_or_variable = parse_foreach_var(scope)!;
	VarDecl* var_decl     = idx_or_variable.as(VarDecl);

	if (consume(ctx, COMMA)!)
	{
		node.index = idx_or_variable;
		node.index_by_ref = var_decl.flags.is_ref;

		node.variable = parse_foreach_var(scope)!;
		var_decl = node.variable.as(VarDecl);
		node.value_by_ref = var_decl.flags.is_ref;
	}
	else
	{
		node.variable = idx_or_variable;
		node.value_by_ref = var_decl.flags.is_ref;
	}

	@expect_else_skip(ctx, COLON, { RPAREN, EOS, EOF } ; err)
	{
		return err;
	}!;

	node.enumeration = parse_expr(scope)!;

	@expect_else_skip(ctx, RPAREN, { EOS, EOF } ; err)
	{
		return err;
	}!;

	node.body = parse_stmt(scope)!;

	return (Node*)node;
}

<*
 ct_assert_stmt ::= '$assert' constant_expression (":" constant_expression)? ";"
*>
fn Node*? parse_ct_assert_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, CT_ASSERT)!;
	CtAssertStmt* node = ctx.ast.alloc_node(CtAssertStmt, start_pos);

	node.expr = parse_constant_expr(scope)!;
	if (consume(ctx, COLON)!)
	{
		node.msg_expr.set(parse_constant_expr(scope)!);
		
		List{Node*} args; args.tinit();

		while (consume(ctx, COMMA)!)
		{
			args.push(parse_constant_expr(scope)!);
		}

		node.args = alloc::clone_slice(ctx.allocator, args.array_view());
	}

	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 ct_error_stmt ::= '$error' constant_expression ";"
*>
fn Node*? parse_ct_error_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, CT_ERROR ; err)
	{
		return err;
	}!;

	CtErrorStmt* node = ctx.ast.alloc_node(CtErrorStmt, start_pos);
	defer node.offset.end = ctx.peek(-1)!!.pos;

	node.expr = parse_constant_expr(scope)!;

	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 ct_echo_stmt ::= '$echo' constant_expression ";"
*>
fn Node*? parse_ct_echo_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, CT_ECHO ; err)
	{
		return err;
	}!;

	CtEchoStmt* node = ctx.ast.alloc_node(CtEchoStmt, start_pos);
	defer node.offset.end = ctx.peek(-1)!!.pos;

	node.expr = parse_constant_expr(scope)!;

	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 defer_statement ::= "defer" defer_kind? statement
 defer_kind      ::= "try"
				  |  "catch"
				  |  "(" "catch" IDENTIFIER ")"
*>
fn Node*? parse_defer_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, DEFER)!;
	DeferStmt* node = ctx.ast.alloc_node(DeferStmt, start_pos);
	DeferKind kind = NORMAL;

	diagnostics::log_debug("parse_defer");

	if CHECK: (consume(ctx, TRY)!)
	{
		kind = TRY;
	}
	else if (consume(ctx, CATCH)!)
	{
		kind = CATCH;
	}
	else if (ctx.is(LPAREN) && ctx.peek(1).kind == CATCH)
	{
		advance(ctx, 2)!; // ( and catch
		Token ident_token = ctx.current;
		Node* ident       = parse_expr(scope)!;
		if (ident.kind != IDENT_EXPR)
		{
			unexpected_at(ctx, ident_token, "Expected identifier here")!;
		}

		node.ident = ident;
		kind = CATCH_VAR;

		expect(ctx, RPAREN)!;
	}

	node.defer_kind = kind;
	node.body = parse_stmt(scope)!;

	return (Node*)node;
}

<*
 assert_stmt ::= ASSERT '(' assert_expr (',' expr)? ')' ';'
*>
fn Node*? parse_assert_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	expect(ctx, ASSERT)!;
	AssertStmt* node = ctx.ast.alloc_node(AssertStmt, start_pos);

	expect(ctx, LPAREN)!;
	node.expr = parse_expr(scope)!;
	if (consume(ctx, COMMA)!)
	{
		node.message = parse_constant_expr(scope)!;

		@pool()
		{
			List{Node*} args;
			args.tinit();

			while (!ctx.eof() && consume(ctx, COMMA)!)
			{
				args.push(parse_expr(scope)!);
			}

			node.args = alloc::clone_slice(ctx.allocator, args.array_view());
		};
	}
	expect(ctx, RPAREN)!;
	expect(ctx, EOS)!;
	return (Node*)node;
}

<*
 ct_foreach_stmt ::= '$foreach' ct_foreach_vars ':' expression ':' statement* '$endforeach'
 ct_foreach_vars ::= CT_IDENT (',' CT_IDENT)?
*>
fn Node*? parse_ct_foreach_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current.pos;
	@expect_else(ctx, CT_FOREACH ; err)
	{
		return err;
	}!;

	CtForeachStmt* node = ctx.ast.alloc_node(CtForeachStmt, start_pos);
	defer node.offset.end = ctx.peek(-1)!!.pos;

	Node* idx_or_variable = parse_ct_foreach_var(scope)!;
	if (consume(ctx, COMMA)!)
	{
		node.index = idx_or_variable;
		node.value = parse_ct_foreach_var(scope)!;
	}
	else
	{
		node.value = idx_or_variable;
	}

	@expect_else_skip(ctx, COLON, { EOS, EOF, CT_ENDFOREACH } ; err)
	{
		return err;
	}!;

	node.expr = parse_expr(scope)!;

	@expect_else_skip(ctx, COLON, { EOS, EOF, CT_ENDFOREACH } ; err)
	{
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDFOREACH))
	{
		stmts.push(parse_stmt(scope)!);
	}

	CompoundStmt* body = ctx.ast.alloc_node(CompoundStmt, start_pos);
	body.offset.end = ctx.current.pos;
	body.statements = alloc::clone_slice(ctx.allocator, stmts.array_view());
	node.body = (Node*)body;

	@expect_else(ctx, CT_ENDFOREACH ; err)
	{
		return err;
	}!;

	return node;
}

fn Node*? parse_ct_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos  = ctx.current.pos;
	VarDecl* node = ctx.ast.alloc_node(VarDecl, start_pos);
	defer node.offset.end = ctx.current.pos;
	node.var_kind = VAR_LOCAL;

	Token token = @expect_else_skip(ctx, CT_IDENT, { COMMA, COLON, EOS, EOF } ; err)
	{
		return node;
	}!;

	node.name = ctx.ident(token);
	return (Node*)node;
}

<*
 ct_expand_stmt :: CT_EXPAND '(' expr ')'
*>
fn Node*? parse_ct_expand_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	expect(ctx, CT_EXPAND)!;

	int start_pos = ctx.current.pos;
	CtExpandStmt* node = ctx.ast.alloc_node(CtExpandStmt, start_pos);

	expect(ctx, LPAREN)!;
	node.expr = parse_expr(scope)!;
	expect(ctx, RPAREN)!;
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;
	return (Node*)node;
}
