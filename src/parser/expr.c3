<*
 Pratt parsing using Binding power

	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module analyzer::parser;

import std::core::ascii;

import std::io;
import std::collections::list;
import std::encoding;
import analyzer::core;
import analyzer::lexer;

<*
 Parse an alias-only C3 function pointer type.

 Function pointer syntax is formed from a function declaration with the name
 omitted, and C3 exposes it through alias declarations.
 @require scope.ctx.current.kind == FN
*>
fn Node* parse_fn_type_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	TypeExpr* node = ctx.ast.alloc_node(TypeExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	node.type_kind = TYPE_FUNCTION;
	node.func.ret_type = parse_type_expr(scope);
	node.func.params = parse_parameter_list(scope);
	node.func.attributes = parse_attributes(scope, node);
	return (Node*)node;
}

<*
 Parse a type target for a TYPE_IDENT alias.

 C3 function pointer types are alias-only, so this helper accepts `fn` syntax
 for aliases without making `fn` a general type-expression start.
 @require(scope.ctx != null) : "Parser context positioned at the alias target."
*>
fn Node* parse_alias_type_target(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	if (ctx.is(FN))
	{
		return parse_fn_type_expr(scope);
	}

	return parse_expr(scope);
}

<*
 Parse a C3 type expression.

 Handles primitive and named type identifiers plus postfix pointer, array,
 slice, vector, and generic type forms.
 @require(scope.ctx != null) : "Parser context positioned at the first type token."
*>
fn Node* parse_type_expr(ContextScope scope, Node* path_expr = null)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	Range start = ctx.current.range;

	diagnostics::log_debug("parse_type_expr");

	TypeExpr* current_type = ctx.ast.alloc_node(TypeExpr, start);
	defer current_type.range.end = ctx.peek(-1).range.end;

	if (consume(ctx, CT_TYPEFROM))
	{
		current_type.type_kind = (ctx.peek(-1).kind == CT_TYPEFROM) ? TYPE_TYPEFROM : TYPE_TYPEOF;
		expect(ctx, current_type, LPAREN);
		current_type.expr = parse_expr(scope);
		expect(ctx, current_type, RPAREN);
	}

	// Check for built-in primitive keywords (int, void, double, etc.)
	else if (is_type_primitive(ctx.current.kind))
	{
		Token t = ctx.current;
		advance(ctx);

		current_type.type_kind = TYPE_IDENTIFIER;
		current_type.unresolved.name = ctx.ident(t);
		current_type.unresolved.path = null;
	}
	else
	{
		Node* path = path_expr ? path_expr : parse_path_expr(scope, { .as_prefix = true });

		if (ctx.is(TYPE_IDENT))
		{
			current_type.type_kind = TYPE_IDENTIFIER;
			current_type.unresolved.name = ctx.ident(ctx.current);
			current_type.unresolved.path = path;
			advance(ctx);
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected type identifier");
			current_type.flags.has_error = true;
			// Synchronize to next possible modifier
			skip_until(ctx, { EOS, ASTERISK, LBRACE, QUESTION, LVEC, LBRACKET });
		}
	}

	while (true)
	{
		Token t = ctx.current;

		if (t.kind == QUESTION)
		{
			if (flags.type_as_expression) break;
			advance(ctx);
			current_type.optional = true;
			continue;
		}

		if (t.kind == ASTERISK)
		{
			advance(ctx);

			TypeExpr* ptr_node = ctx.ast.alloc_node(TypeExpr, { start.start, ctx.current.range.end });

			ptr_node.type_kind = TYPE_POINTER;
			ptr_node.modify.base = current_type; // The previous node becomes the base

			current_type = ptr_node;
			continue;
		}

		if (t.kind == LVEC)
		{
			advance(ctx);

			TypeExpr* vec_node = ctx.ast.alloc_node(TypeExpr, { start.start, ctx.current.range.end });

			vec_node.type_kind = TYPE_VECTOR;
			vec_node.array.base = current_type;

			if (!consume(ctx, ASTERISK))
			{
				vec_node.array.len_expr = parse_expr(scope, ADDITIVE);
			}

			expect(ctx, vec_node, RVEC);

			vec_node.range.end = ctx.peek(-1).range.end;

			current_type = vec_node;
			continue;
		}

		if (t.kind == LBRACKET)
		{
			advance(ctx);

			TypeExpr* arr_node = ctx.ast.alloc_node(TypeExpr, { start.start, ctx.current.range.end });

			if (ctx.is(RBRACKET))
			{
				advance(ctx);
				arr_node.type_kind = TYPE_SLICE;
				arr_node.modify.base = current_type;
			}
			else if (ctx.is(ASTERISK) && ctx.peek(1).kind == RBRACKET)
			{
				advance(ctx); // Consume '*'
				advance(ctx); // Consume ']'

				arr_node.type_kind = TYPE_ARRAY;
				arr_node.array.base = current_type;
				arr_node.array.len_expr = null; // null represents inferred array size [*]
			}
			else
			{
				arr_node.type_kind = TYPE_ARRAY;
				arr_node.array.base = current_type;
				arr_node.array.len_expr = parse_expr(scope);
				expect(ctx, arr_node, RBRACKET);
			}

			arr_node.range.end = ctx.peek(-1).range.end;
			current_type = arr_node;
			continue;
		}

		// Handle Generics: '{' ... '}'
		if (t.kind == LBRACE)
		{
			if (flags.no_generics) break;

			TypeExpr* gen_node = ctx.ast.alloc_node(TypeExpr, { start.start, ctx.current.range.end });

			gen_node.type_kind = TYPE_GENERIC;
			gen_node.generic.base = current_type;
			gen_node.generic.params = parse_generics_list(scope);

			gen_node.range.end = ctx.current.range.end;

			current_type = gen_node;
			continue;
		}

		break;
	}

	return (Node*)current_type;
}

fn Node* parse_ident_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	Node* path_prefix;

	diagnostics::log_debug("parse_ident: %s", ctx.current.value);

	if (ctx.peek(1).kind == SCOPE)
	{
		path_prefix = parse_path_expr(scope, { .as_prefix = true });
	}
	Token t = ctx.current;
	switch (t.kind)
	{
		case TYPE_IDENT:
			return parse_type_expr(scope, path_prefix);
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
		case CT_IDENT:
		case HASH_IDENT:
			{
				IdentExpr* ident = ctx.ast.alloc_node(IdentExpr, start);
				ident.ident = ctx.ident(t);
				ident.path_expr = path_prefix;

				advance(ctx);
				return (Node*)ident;
			}
		default:
			advance(ctx);
			diagnostics::error(ctx.context, t.range, "Expected type or identifier after path - got: %s", t.kind.description);
			return ctx.ast.error(t.range);
	}
}

<*
 @param [&inout] list
*>
fn void parse_join_strings(ContextScope scope, String* list)
{
	ParseContext* ctx = scope.ctx;

	if (ctx.eof() || !ctx.is(STRING_LITERAL)) return;

	Token first_tok = ctx.current;
	String current_str = first_tok.value[1:^2];
	advance(ctx);

	while (!ctx.eof() && ctx.is(STRING_LITERAL))
	{
		Token next_tok = ctx.current;
		String next_str = next_tok.value[1:^2];

		current_str = current_str.tconcat(next_str);

		advance(ctx);
	}

	*list = current_str.copy(ctx.allocator);
}

fn Node* parse_literal_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Token token = ctx.current;
	Range start   = token.range;

	LiteralExpr* literal = ctx.ast.alloc_node(LiteralExpr, start);
	defer literal.range.end = ctx.peek(-1).range.end;
	String token_text    = token.value;

	diagnostics::log_debug("literal_expr: %s", token.kind.description);

	switch (token.kind)
	{
		case NULL:
			literal.literal_kind = NULL_LITERAL;
			advance(ctx);
			break;
		case TRUE:
			literal.literal_kind = BOOL_LITERAL;
			literal.boolean = true;
			advance(ctx);
			break;
		case FALSE:
			literal.literal_kind = BOOL_LITERAL;
			literal.boolean = false;
			advance(ctx);
			break;
		case INT_DECIMAL_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case INT_BIN_LITERAL:
			literal.literal_kind = INT_LITERAL;
			String clean_string = token_text.treplace("_", "");
			int base = 10;
			usz start_idx = 0;
			if (token.kind == INT_HEX_LITERAL)
			{
				base = 16;
				start_idx = 2;
			}
			else if (token.kind == INT_BIN_LITERAL)
			{
				base = 2;
				start_idx = 2;
			}
			else if (token.kind == INT_OCTAL_LITERAL)
			{
				base = 8;
				start_idx = 2;
			}
			else
			{
				base = 10;
				start_idx = 0;
			}

			String body = clean_string[start_idx..];
			sz end_idx = body.len;
			while (end_idx > 0)
			{
				char last_char = body[end_idx - 1];
				if (ascii::is_alpha(last_char))
				{
					if (base == 16 && ascii::is_xdigit(last_char)) break;
					if (base == 10 && ascii::is_digit(last_char)) break;
					if (base == 8 && ascii::is_odigit(last_char)) break;
					if (base == 2 && ascii::is_bdigit(last_char)) break;

					end_idx--;
				}
				else
				{
					break;
				}
			}

			String pure_digits = body[0:end_idx];
			uint128? value = pure_digits.to_uint128(base);
			if (catch err = value)
			{
				diagnostics::error(ctx.context, token.range, "Failed to parse int literal (%s)", err);
				advance(ctx);
				return ctx.ast.error(start);
			}
			literal.integer = value;
			advance(ctx);
			break;
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
			{
				literal.literal_kind = REAL_LITERAL;
				String clean_string = token_text.treplace("_", "");
				sz len              = clean_string.len;
				if (len > 0)
				{
					if (clean_string.ends_with("f32") || clean_string.ends_with("f64"))
					{
						clean_string = clean_string[:^3];
					}
					if (clean_string.ends_with("f") || clean_string.ends_with("d"))
					{
						if (token.kind == FLOAT_HEX_LITERAL)
						{
							if (clean_string.contains("p") || clean_string.contains("P"))
							{
								clean_string = clean_string[:^1];
							}
						}
						else
						{
							clean_string = clean_string[:^1];
						}
					}
				}
				double? real = clean_string.to_double();
				if (catch err = real)
				{
					diagnostics::error(ctx.context, token.range, "Failed to decode float literal (%s)", err);
					advance(ctx);
					return ctx.ast.error(start);
				}
				literal.real = real;
				advance(ctx);
				break;
			}
		case STRING_LITERAL:
			literal.literal_kind = STRING_LITERAL;
			literal.string = "";
			parse_join_strings(scope, &literal.string);
			break;
		case BYTES_LITERAL:
			literal.literal_kind = BYTES_LITERAL;
			if (token_text.starts_with("b64"))
			{
				String payload = token_text[4:^5];
				String clean = payload.treplace(" ", "")
						.treplace("\t", "")
						.treplace("\n", "")
						.treplace("\r", "");
				diagnostics::log_debug(clean);
				char[]? b64 = base64::decode(tmem, clean);
				if (catch err = b64)
				{
					diagnostics::error(ctx.context, token.range, "Failed to decode Base64(%s)", err);
					advance(ctx);
					return ctx.ast.error(start);
				}
				literal.bytes = alloc::clone_slice(ctx.allocator, b64);
				advance(ctx);
			}
			else if (token_text.starts_with("x"))
			{
				String payload = token_text[2:^3];
				String clean = payload.treplace(" ", "")
						.treplace("\t", "")
						.treplace("\n", "")
						.treplace("\r", "");
				diagnostics::log_debug("%s", clean);
				if (clean.len % 2 != 0)
				{
					diagnostics::error(ctx.context, token.range,
						"Hex literal payload must have an even number of digits (got %s chars in '%s')",
						clean.len,
						clean);
					advance(ctx);
					return ctx.ast.error(start);
				}
				char[]? hex = hex::decode(tmem, clean);
				if (catch err = hex)
				{
					diagnostics::error(ctx.context, token.range, "Failed to decode hex(%s): %s", clean, err);
					advance(ctx);
					return ctx.ast.error(start);
				}
				literal.bytes = alloc::clone_slice(ctx.allocator, hex);
				advance(ctx);
			}
			break;
		case CHAR_LITERAL:
			literal.literal_kind = INT_LITERAL;

			// Slice off the enclosing single quotes: 'c' -> c
			String clean_char = token_text[1:^2];

			if (clean_char.len == 0)
			{
				diagnostics::error(ctx.context, token.range, "Empty character literal encountered");
				advance(ctx);
				return ctx.ast.error(start);
			}

			// Handle escapes vs plain characters
			if (clean_char[0] == '\\')
			{
				if (clean_char.len < 2)
				{
					diagnostics::error(ctx.context, token.range, "Malformed escape sequence in character literal");
					advance(ctx);
					return ctx.ast.error(start);
				}

				switch (clean_char[1])
				{
					case 'n': literal.integer = (uint128)'\n'; break;
					case 'r': literal.integer = (uint128)'\r'; break;
					case 't': literal.integer = (uint128)'\t'; break;
					case '\\': literal.integer = (uint128)'\\'; break;
					case '\'': literal.integer = (uint128)'\''; break;
					case '"': literal.integer = (uint128)'"'; break;
					case '0': literal.integer = (uint128)'\0'; break;
					case 'a':  literal.integer = (uint128)0x07; break; // Alert
					case 'b':  literal.integer = (uint128)0x08; break; // Backspace
					case 'f':  literal.integer = (uint128)0x0C; break; // Form feed
					case 'v':  literal.integer = (uint128)0x0B; break; // Vertical tab
					case 'x':
						if (clean_char.len < 4)
						{
							diagnostics::error(ctx.context, token.range, "Malformed hex escape sequence");
							return ctx.ast.error(start);
						}

						char hi = clean_char[2];
						char lo = clean_char[3];

						// Combine them into a single byte/integer value
						// (hi << 4) | lo
						literal.integer = (uint128)((char.from_hex(hi) << 4) | char.from_hex(lo));
						break;
					default:
						diagnostics::error(ctx.context, token.range, "Unsupported escape sequence '\\%c'", clean_char[1]);
						advance(ctx);
						return ctx.ast.error(start);
				}
			}
			else
			{
				// Just grab the direct byte values
				literal.integer = (uint128)clean_char[0];
			}
			advance(ctx);
			break;
		default:
			unreachable("Not implemented! (%s)", token.kind.description);
	}

	return (Node*)literal;
}

<*
 Parse a full path e.g. foo::bar::baz;
*>
fn Node* parse_path_expr(ContextScope scope, PathExprOptions options = { }) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	diagnostics::log_debug("parse_path_expr");

	if (!ctx.is(IDENT))
	{
		if (options.as_prefix) return null;
		diagnostics::error(ctx.context, ctx.current.range, "Expected a path identifier");
		return ctx.ast.error(start);
	}

	PathExpr* node = ctx.ast.alloc_node(PathExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	DString sb; sb.tinit();

	while (true)
	{
		sb.append(ctx.current.value);
		advance(ctx);

		if (consume(ctx, SCOPE))
		{
			sb.append("::");

			// Check if another identifier follows
			if (is_some_ident(ctx.current.kind))
			{
				continue;
			}
			else if (options.as_prefix)
			{
				break;
			}
			else
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected an identifier after '::'");
				node.flags.has_error = true;
				break;
			}
		}

		break;
	}

	node.path = ctx.ident_string(sb.str_view());
	return (Node*)node;
}

fn Node* parse_binary_expr(ContextScope scope, Node* left, Precedence prec)
{
	ParseContext* ctx = scope.ctx;
	Range start  = ctx.current.range;
	TokenKind kind = ctx.current.kind;
	advance(ctx);
	Node* right = parse_expr(scope.with_flags({ .type_as_expression = true }), prec);

	BinaryExpr* node = ctx.ast.alloc_node(BinaryExpr, { start.start, right.range.end });
	node.left = left;
	node.right = right;
	node.op = core::binaryop_from_token(kind);
	return (Node*)node;
}

<*
 unary_expr ::= unary_op expr
*>
fn Node* parse_unary_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	diagnostics::log_debug("parse_unary_expr");
	Range start = ctx.current.range;
	if (ctx.is(MINUS))
	{
		if (ctx.peek(1).kind.is_int_literal())
		{
			advance(ctx);
			return parse_expr(scope);
		}
	}
	bool is_bang_bang = ctx.is(BANGBANG);
	UnaryExpr* node = ctx.ast.alloc_node(UnaryExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	UnaryOpKind? op  = core::unaryop_from_token(ctx.current.kind);
	if (catch op)
	{
		diagnostics::error(ctx.context, ctx.current.range,"Not a unary operator (%s)", ctx.current.kind);
		error_node(ctx, node);
	}
	else
	{
		node.operator = op;
	}
	advance(ctx);
	node.expr = parse_expr(scope, UNARY);
	if (is_bang_bang)
	{
		UnaryExpr* outer = ctx.ast.alloc_node(UnaryExpr, { start.start, ctx.current.range.end });
		outer.expr = node;
		outer.operator = UNARYOP_NOT;
		return (Node*)outer;
	}
	return (Node*)node;
}

fn Node* parse_post_unary_expr(ContextScope scope, Node* left, Precedence bp)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	PostUnaryExpr* node = ctx.ast.alloc_node(PostUnaryExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	UnaryOpKind? op = core::unaryop_from_token(ctx.current.kind);
	if (catch op)
	{
		diagnostics::error(ctx.context, ctx.current.range,"Not a unary operator (%s)", ctx.current.kind);
		error_node(ctx, node);
	}
	else
	{
		node.operator = op;
	}
	node.expr = left;
	advance(ctx);
	return (Node*)node;
}

<*
 expr_list ::= decl_or_expr*

*>
fn Node* parse_expr_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ExprList* node = ctx.ast.alloc_node(ExprList, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;
	List{Node*} exprs;
	exprs.tinit();
	while (!ctx.eof())
	{
		exprs.push(parse_decl_or_expr(scope));
		if (ctx.eof() || !consume(ctx, COMMA)) break;
	}

	node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
	return (Node*)node;
}

<*
 contract_expr ::= expr_list (':'? STRING)?
*>
fn Node* parse_contract_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	ContractExpr* node = ctx.ast.alloc_node(ContractExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	node.exprs = parse_expr_list(scope.with_only_flags({ .is_contract = true }));

	if (!ctx.eof() && consume(ctx, COLON))
	{
		if (!ctx.is(STRING_LITERAL))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected a string after ':'");
			error_node(ctx, node);
		}

		node.expr_string = parse_expr(scope);
	}

	return (Node*)node;
}

fn Node* parse_call_expr(ContextScope scope, Node* callee)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	CallExpr* node = ctx.ast.alloc_node(CallExpr, callee.range);
	defer node.range.end = ctx.peek(-1).range.end;
	expect(ctx, node, LPAREN);
	node.callee = callee;

	diagnostics::log_debug("call_expr: %s", ctx.current.value);

	if (!ctx.is(RPAREN) && !ctx.is(EOS) && !ctx.eof())
	{
		diagnostics::log_debug("call_expr - args");
		node.args = parse_arg_list(scope);
	}

	NodeArray body_args;
	if (consume(ctx, EOS))
	{
		body_args = parse_parameter_list(scope.with_only_flags({ .is_call = true }));
	}

	expect(ctx, node, RPAREN);

	if (ctx.is(AT_IDENT) && !scope.flags.is_contract)
	{
		Token t = ctx.current;
		node.attributes = parse_attributes(scope, node);

		foreach (attr : node.attributes)
		{
			AttributeDecl* attr_decl = attr.as(AttributeDecl);
			switch (attr_decl.attribute_kind)
			{
				case AttributeKind.INLINE:
				case AttributeKind.PURE:
				case AttributeKind.NOINLINE:
					// Set flags?
					break;
				default:
					diagnostics::error(ctx.context, t.range, "Only '@pure', '@inline' and '@noinline' are valid attributes for calls");
					error_node(ctx, attr);
			}
		}
	}
	Node* body;
	if (ctx.is(LBRACE))
	{
		body = parse_compound_stmt(scope);
	}

	if (body || body_args)
	{
		MacroBodyExpr* body_node = ctx.ast.alloc_node(MacroBodyExpr, start);
		body_node.args = body_args;
		body_node.body = body;
		node.macro_body_expr = body_node;
	}

	return (Node*)node;
}

<*
 catch_unwrap ::= 'catch' (IDENT | type_expr? IDENT '=' catch_chain) | catch_chain
	catch_chain ::= parse_try_chain_expr (',' parse_try_chain_expr)*
 @require scope.ctx.current.kind == CATCH
*>
fn Node* parse_catch_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	CatchExpr* node = ctx.ast.alloc_node(CatchExpr, ctx.current.range);
	advance(ctx);
	defer node.range.end = ctx.current.range.end;

	Node* sub_expr = parse_try_chain_expr(scope);

	List{Node*} exprs;
	exprs.tinit();

	if (consume(ctx, COMMA))
	{
		exprs.push(sub_expr);
		do
		{
			int pos_start = ctx.pos;
			sub_expr = parse_try_chain_expr(scope);

			if (ctx.pos == pos_start)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Parser failed to advance");
				skip_until(ctx, { COMMA });
			}

			exprs.push(sub_expr);
		}
		while (consume(ctx, COMMA));

		node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
		return node;
	}

	if (sub_expr.kind == TYPE_EXPR)
	{
		node.type = sub_expr;
		node.variable = parse_try_chain_expr(scope);

		if (node.variable.kind != IDENT_EXPR)
		{
			diagnostics::error(ctx.context, node.variable.range, "Expected variable name");
			node.flags.has_error = true;
		}

		if (!consume(ctx, EQ))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '=' in catch-unwrap");
			node.flags.has_error = true;
		}
		else
		{
			while (!ctx.eof())
			{
				exprs.push(parse_try_chain_expr(scope));
				if (!consume(ctx, COMMA)) break;
			}
			node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
		}
	}
	else
	{
		node.variable = sub_expr;
	}

	node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());

	return (Node*)node;
}

<*
 cond_list ::= ((expr | decl-expr) COMMA)* (expr | decl-expr | try_unwrap_chain | catch_unwrap )
*>
fn Node* parse_cond_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	CondExpr* node = ctx.ast.alloc_node(CondExpr, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;

	List{Node*} exprs;
	exprs.tinit();

	while (!ctx.eof())
	{
		if (ctx.is(TRY))
		{
			exprs.push(parse_try_unwrap_chain_expr(scope));
			if (ctx.is(COMMA))
			{
				diagnostics::error(ctx.context, ctx.current.range, "'catch' must be placed last");
				error_node(ctx, node);
			}
			break;
		}
		if (ctx.is(CATCH))
		{
			exprs.push(parse_catch_expr(scope));
			if (ctx.is(COMMA))
			{
				diagnostics::error(ctx.context, ctx.current.range, "'catch' must be placed last");
				error_node(ctx, node);
			}
			break;
		}

		exprs.push(parse_decl_or_expr(scope));
		if (!consume(ctx, COMMA)) break;
	}

	node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
	return (Node*)node;
}

<*
 @require scope.ctx.current.kind == TRY
*>
fn Node* parse_try_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	TryExpr* node = ctx.ast.alloc_node(TryExpr, ctx.current.range);
	advance(ctx);
	defer node.range.end = ctx.peek(-1).range.end;

	Node* lhs = parse_try_chain_expr(scope);

	if (lhs.kind == TYPE_EXPR)
	{
		node.type = lhs;
		node.variable = parse_try_chain_expr(scope);

		if (node.variable.kind != IDENT_EXPR)
		{
			diagnostics::error(ctx.context, node.variable.range, "Expected identifier after type in try-expression");
			node.flags.has_error = true;
		}
	}
	else
	{
		node.variable = lhs;
	}

	if (consume(ctx, EQ))
	{
		node.init = parse_try_chain_expr(scope);
	}

	return (Node*)node;
}

<*
 try_unwrap_chain ::= try ('&&' (try_unwrap | try_chain_expr))*

*>
fn Node* parse_try_unwrap_chain_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Node* first_try      = parse_try_expr(scope);
	Node* current        = first_try;
	TryExpr* current_try = current.as(TryExpr);

	while (consume(ctx, AND))
	{
		Node* next_expr = null;

		if (ctx.is(TRY))
		{
			next_expr = parse_try_expr(scope);
		}
		else
		{
			next_expr = parse_try_chain_expr(scope);
		}

		if (current.kind == TRY_EXPR)
		{
			current.as(TryExpr).next = next_expr;
		}
		else
		{
			Node* walker = first_try;
			while (walker.kind == TRY_EXPR && walker.as(TryExpr).next != null)
			{
				walker = walker.as(TryExpr).next;
			}
			if (walker.kind == TRY_EXPR)
			{
				walker.as(TryExpr).next = next_expr;
			}
		}

		current = next_expr;
	}

	return first_try;
}

<*
 ternary_optional_expr ::= expr? | ternary_expr
 optional_expr ::= <left> '?' '!'?
 ternary_expr ::= <left> '?' expr ':' ternary_prec_expr
*>
fn Node* parse_ternary_expr(ContextScope scope, Node* left)
{
	ParseContext* ctx = scope.ctx;
	TernaryExpr* node = ctx.ast.alloc_node(TernaryExpr, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;

	node.is_const = ctx.is(CT_TERNARY);
	advance(ctx);
	node.cond = left;

	node.then_expr = parse_expr(scope);

	expect(ctx, node, COLON);

	node.else_expr = parse_expr(scope, TERNARY);

	return (Node*)node;
}

<*
 builtin_expr ::= '$$' IDENT
 compiler_const_expr ::= '$$' CONST_IDENT
 @require scope.ctx.current.kind == BUILTIN
*>
fn Node* parse_builtin_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	BuiltinFunction builtin;
	bool had_error;

	diagnostics::log_debug("builtin");

	Token t = ctx.current;
	if (t.kind != IDENT && t.kind != CONST_IDENT && t.kind != TYPE_IDENT)
	{
		diagnostics::error(ctx.context, t.range, "Expected identifier after '$$'");
		had_error = true;
	}
	advance(ctx);
	Ident* name = ctx.ident(t);

	if (t.kind == CONST_IDENT)
	{
		CompilerConstExpr* node = ctx.ast.alloc_node(CompilerConstExpr, ctx.current.range);
		if (had_error) error_node(ctx, node);
		node.name = name;
		return (Node*)node;
	}

	BuiltinExpr* node = ctx.ast.alloc_node(BuiltinExpr, ctx.current.range);
	if (had_error) error_node(ctx, node);
	node.name = name;
	return (Node*)node;
}

<*
 splat_expr ::= '...' expr
*>
fn Node* parse_splat_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	SplatExpr* node = ctx.ast.alloc_node(SplatExpr, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, ELLIPSIS);

	node.inner = parse_expr(scope);

	return (Node*)node;
}

fn Node* parse_vasplat_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	VasplatExpr* node = ctx.ast.alloc_node(VasplatExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, ELLIPSIS);
	expect(ctx, node, CT_VAARG);

	if (consume(ctx, LBRACKET))
	{
		diagnostics::log_warn("This is not implemented!");
		advance(ctx);
	}

	return (Node*)node;
}

fn Node* parse_ct_eval_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	CtEvalExpr* node = ctx.ast.alloc_node(CtEvalExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, CT_EVAL);
	expect(ctx, node, LPAREN);
	node.inner_expr = parse_expr(scope);
	expect(ctx, node, RPAREN);

	return (Node*)node;
}

<*
 lambda_expr ::= "fn" return_type? fn_parameter_list attributes? lambda_body
 lambda_body ::= "{" statement* "}"
				| "=>" expression
 @require scope.ctx.current.kind == FN
*>
fn Node* parse_lambda_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	LambdaExpr* node = ctx.ast.alloc_node(LambdaExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	node.visibility = LOCAL;
	advance(ctx);
	if (!ctx.is(LPAREN))
	{
		node.return_type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null);
	}
	node.params = parse_parameter_list(scope);
	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node);
	}

	if (consume(ctx, IMPLIES))
	{
		node.body = parse_expr(scope);

		// Clean statement ending validation
		// if (!node_ends_with_block(ctx, lambda.body))
		// {
		// 	expect(ctx, EOS);
		// }
	}
	else if (ctx.is(LBRACE))
	{
		node.body = parse_compound_stmt(scope);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected the beginning of a block or a shortbody");
		error_node(ctx, node);
	}

	return (Node*)node;
}

fn Node* parse_generic_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	GenericIdentExpr* node = ctx.ast.alloc_node(GenericIdentExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	expect(ctx, node, LBRACE);
	List{Node*} exprs;
	exprs.tinit();
	do
	{
		exprs.push(parse_expr(scope));
		if (!consume(ctx, COMMA))
		{
			expect(ctx, node, RBRACE);
			break;
		}
	}
	while (!ctx.eof() && !consume(ctx, RBRACE));

	node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
	return (Node*)node;
}

fn Node* parse_group_expr(ContextScope scope)
{
	diagnostics::log_debug("parse_group_expr");
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;

	bool had_error;
	if (!consume(ctx, LPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '%s' got '%s'", ctx.current.kind.description, ctx.current.kind.description);
		had_error = true;
	}
	Node* inner = parse_expr(scope);
	if (!consume(ctx, RPAREN))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '%s' got '%s'", ctx.current.kind.description, ctx.current.kind.description);
		had_error = true;
	}

	// can_start_expression might miss some cases
	if ((inner.kind == TYPE_EXPR || inner.kind == COMPOUND_LITERAL_EXPR) && can_start_expression(ctx.current.kind))
	{
		diagnostics::log_debug("parse_cast_expr");
		Node* operand = parse_expr(scope, UNARY);

		CastExpr* cast = ctx.ast.alloc_node(CastExpr, { start.start, ctx.peek(-1).range.end });
		cast.inner = inner;
		cast.operand = operand;
		if (had_error) error_node(ctx, cast);
		return (Node*)cast;
	}

	GroupExpr* group = ctx.ast.alloc_node(GroupExpr, { start.start, ctx.peek(-1).range.end });
	if (had_error) error_node(ctx, group);
	group.inner = inner;
	return (Node*)group;
}

<*
 designator_expr ::= ('[' expr ']' | '.' IDENT)*

*>
fn Node* parse_designator_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Node* path;

	while (true)
	{
		if (ctx.is(DOT))
		{
			Range start = ctx.current.range;
			advance(ctx); // consume '.'

			Node* field = parse_expr(scope, HIGHEST);

			DesignatorExpr* node = ctx.ast.alloc_node(DesignatorExpr, start);
			node.range.end = ctx.current.range.end;

			node.designator_kind = DesignatorKind.PERIOD;
			node.path = path; // will be null if this is the very first component
			node.data.field = field;

			path = (Node*)node;
			continue;
		}

		if (ctx.is(LBRACKET))
		{
			Range start = ctx.current.range;
			advance(ctx); // consume '['
			Node* designator_node = parse_range_expr(scope, path, start);
			path = designator_node;
			continue;
		}

		break;
	}

	return path;
}

<*
 initializer_list_expr ::= '{' ('...' expr | expr (',' expr)*)? '}'
*>
fn Node* parse_initializer_list_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	InitializerListExpr* node = ctx.ast.alloc_node(InitializerListExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LBRACE);

	// Handle empty initializer {}
	if (consume(ctx, RBRACE))
	{
		return node;
	}

	List{Node*} exprs;
	exprs.tinit();

	while (!ctx.eof())
	{
		Node* expr;

		if (ctx.is(ELLIPSIS))
		{
			if (ctx.peek(1).kind == CT_VAARG)
			{
				expr = parse_vasplat_expr(scope);
			}
			else
			{
				expr = parse_prefix_expr_only(scope);
			}
		}
		else if (ctx.is(DOT) || ctx.is(LBRACKET))
		{
			Token path_token = ctx.current;
			Node* des_expr   = parse_designator_expr(scope);

			if (consume(ctx, EQ))
			{
				Node* val           = parse_expr(scope);
				DesignatedInitializerExpr* des_init_node = ctx.ast.alloc_node(DesignatedInitializerExpr, path_token.range);
				des_init_node.range.end = ctx.current.range.end;

				des_init_node.path = des_expr;
				des_init_node.value = val;

				expr = (Node*)des_init_node;
			}
			else
			{
				// Implicit assignment shortcut: .member
				expr = des_expr;
			}
		}
		else if (ctx.is(LBRACE))
		{
			// Nested initializers like { {1, 2}, {3, 4} }
			expr = parse_initializer_list_expr(scope);
		}
		else
		{
			expr = parse_expr(scope);
		}

		exprs.push(expr);

		if (consume(ctx, RBRACE)) break;
		expect(ctx, node, COMMA);
		if (ctx.is(RBRACE))
		{
			advance(ctx);
			break;
		}
	}

	node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());

	return (Node*)node;
}

fn Node* parse_access_expr(ContextScope scope, Node* left)
{
	ParseContext* ctx = scope.ctx;
	Range start = left.range;
	TokenKind op_kind      = ctx.current.kind;
	AccessKind access_kind = (op_kind == TokenKind.SCOPE) ? AccessKind.STATIC : AccessKind.INSTANCE;
	advance(ctx);
	Token member_token = ctx.current;

	diagnostics::log_debug("parse_access_expr");

	if (member_token.kind == LBRACKET)
	{
		advance(ctx);
		MaybeDerefExpr* deref_node = ctx.ast.alloc_node(MaybeDerefExpr, { start.start, ctx.current.range.end });
		deref_node.left = left;
		return parse_range_expr(scope, (Node*)deref_node, deref_node.range);
	}

	AccessExpr* node = ctx.ast.alloc_node(AccessExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	node.access_kind = access_kind;
	node.left = left;

	if (member_token.kind == CT_EVAL)
	{
		advance(ctx);
		expect(ctx, (Node*)node, LPAREN);
		node.member = parse_expr(scope.with_only_flags({ .type_as_expression = true }));
		expect(ctx, (Node*)node, RPAREN);
	}
	else
	{
		// HIGHEST bp to avoid consuming downstream infix operators.
		node.member = parse_expr(scope, HIGHEST);
	}

	return (Node*)node;
}

<*
 maybe_range ::= range | ('^'? INTEGER)
 range ::= dot_range | colon_range
 dot_range ::= ('^'? INTEGER)? .. ('^'? INTEGER)?
 colon_range ::= ('^'? INTEGER)? : ('^'? INTEGER)?
*>
fn Node* parse_range_expr(ContextScope scope, Node* left, Range start)
{
	ParseContext* ctx = scope.ctx;

	DesignatorExpr* designator_node = ctx.ast.alloc_node(DesignatorExpr, start);
	defer designator_node.range.end = ctx.peek(-1).range.end;

	RangeExpr* range_node = ctx.ast.alloc_node(RangeExpr, start);

	designator_node.path = left;
	designator_node.data.range = range_node;

	bool is_slice = false;
	TokenKind op_kind = TokenKind.EOS;

	// Check if the start of the range is omitted (e.g., `[:5]` or `[..5]`)
	if (ctx.is(COLON) || ctx.is(DOTDOT))
	{
		is_slice = true;
		op_kind = ctx.current.kind;
		advance(ctx);
	}
	else
	{
		// Parse the optional leading index modifier caret '^' (BIT_XOR)
		if (consume(ctx, BIT_XOR))
		{
			range_node.start_from_end = true;
		}

		range_node.start = parse_expr(scope, LOWEST);

		// Check if an operator separates this from a secondary range bound
		if (ctx.is(COLON) || ctx.is(DOTDOT))
		{
			is_slice = true;
			op_kind = ctx.current.kind;
			advance(ctx);
		}
	}

	// If it is a full range slice, parse the trailing bound component
	if (is_slice && !ctx.is(RBRACKET))
	{
		if (consume(ctx, BIT_XOR))
		{
			range_node.end_from_end = true;
		}

		range_node.end = parse_expr(scope, LOWEST);
	}

	expect(ctx, designator_node, RBRACKET);
	range_node.range.end = ctx.peek(-1).range.end;

	if (is_slice)
	{
		designator_node.designator_kind = DesignatorKind.RANGE;

		if (op_kind == COLON)
		{
			// Syntax: [start : len]
			range_node.range_kind = RangeKind.CONST_LEN;
		}
		else
		{
			// Syntax: [start .. end]
			if (range_node.start && range_node.end)
			{
				range_node.range_kind = RangeKind.CONST_RANGE;
			}
			else if (range_node.end)
			{
				range_node.range_kind = RangeKind.CONST_END;
			}
			else
			{
				range_node.range_kind = RangeKind.DYNAMIC;
			}
		}
	}
	else
	{
		// Syntax: [index] (Single lookup access format)
		designator_node.designator_kind = DesignatorKind.INDEX;
		range_node.range_kind = RangeKind.SINGLE_ELEMENT;
	}

	return (Node*)designator_node;
}

<*
 @param [&in] left
*>
fn Node* parse_raise_suffix_expr(ContextScope scope, Node* left, Token left_token)
{
	ParseContext* ctx = scope.ctx;
	if (left.kind == TYPE_EXPR)
	{
		advance(ctx);
		diagnostics::error(ctx.context, left_token.range, "Expected a fault before '~'");
		return ctx.ast.error(ctx.current.range);
	}
	Range start = ctx.current.range;
	OptionalExpr* node = ctx.ast.alloc_node(OptionalExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;
	expect(ctx, node, BIT_NOT);
	node.inner_expr = left;
	return (Node*)node;
}

<*
 @require scope.ctx.current.kind == CT_DEFINED
*>
fn Node* parse_ct_defined_expr(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtDefinedExpr* node = ctx.ast.alloc_node(CtDefinedExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LPAREN);

	List{Node*} exprs;
	exprs.tinit();
	while (!ctx.eof() && !consume(ctx, RPAREN))
	{
		exprs.push(parse_decl_or_expr(scope));
		if (!consume(ctx, COMMA))
		{
			expect(ctx, node, RPAREN);
			break;
		}
	}

	node.expr_list = alloc::clone_slice(ctx.allocator, exprs.array_view());

	return (Node*)node;
}

<*
 @require scope.ctx.current.kind == CT_FEATURE
*>
fn Node* parse_ct_feature(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtFeatureExpr* node = ctx.ast.alloc_node(CtFeatureExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LPAREN);
	node.inner_expr = parse_expr(scope);
	expect(ctx, node, RPAREN);

	return (Node*)node;
}

<*
 lengthof ::= LENGTHOF '(' expr ')'
 @require scope.ctx.current.kind == LENGTHOF
*>
fn Node* parse_lengthof_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	LengthofExpr* node = ctx.ast.alloc_node(LengthofExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LPAREN);
	node.inner_expr = parse_expr(scope);
	expect(ctx, node, RPAREN);

	return (Node*)node;
}

<*
 ct_stringify ::= $stringify '(' expr ')'
 @require scope.ctx.current.kind == CT_STRINGIFY
*>
fn Node* parse_ct_stringify_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtStringifyExpr* node = ctx.ast.alloc_node(CtStringifyExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LPAREN);
	node.inner_expr = parse_expr(scope);
	expect(ctx, node, RPAREN);
	return (Node*)node;
}

<*
 vaarg ::= '$vaarg' ('.' len) | ('[' '^'? expr ']')
 @require scope.ctx.current.kind == CT_VAARG
*>
fn Node* parse_vaarg_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	VaargExpr* node = ctx.ast.alloc_node(VaargExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (consume(ctx, DOT))
	{
		String token_text = ctx.current.value;
		if (!ctx.is(IDENT) || token_text != constants::KW_LEN)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected '.%s' after '$vaarg'", constants::KW_LEN);
			error_node(ctx, node);
		}
		advance(ctx);
		node.vaarg_kind = VACOUNT;
		return node;
	}

	expect(ctx, node, LBRACKET);
	node.start_from_end = consume(ctx, BIT_XOR);
	node.expr = parse_expr(scope);
	expect(ctx, node, RBRACKET);
	return (Node*)node;
}

<*
 ct_refect ::= CT_REFLECT '(' expr ')'
 @require scope.ctx.current.kind == CT_REFLECT
*>
fn Node* parse_ct_reflect_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start = ctx.current.range;
	advance(ctx);
	CtReflectExpr* node = ctx.ast.alloc_node(CtReflectExpr, start);
	defer node.range.end = ctx.peek(-1).range.end;

	expect(ctx, node, LPAREN);
	node.inner_expr = parse_expr(scope);
	expect(ctx, node, RPAREN);
	return node;
}
