module analyzer::parser;

import std::io;
import std::collections::list;
import analyzer::core;
import analyzer::lexer;

fn bool is_keyword_ident(TokenKind type)
{
	return type >= ALIAS && type <= WHILE;
}

fn bool is_base_type(TokenKind kind)
{
	return kind >= VOID_TYPE && kind <= UNTYPEDLIST_TYPE;
}

fn bool is_some_ident(TokenKind type)
{
	switch (type)
	{
		case TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
			return true;
		default:
			return false;
	}
}

fn bool is_non_type_ident(TokenKind k)
{
	return k == IDENT || k == HASH_IDENT || k == CT_IDENT;
}

fn bool is_type(ParseContext* ctx)
{
	TokenKind kind = ctx.current.kind;

	if (is_type_primitive(kind)) return true;
	if (kind == TYPE_IDENT) return true;

	// if (kind == IDENT && ctx.peek(1).kind == SCOPE)
	// {
	// 	return true;
	// }

	return false;
}

fn bool is_alias_name_kind(TokenKind kind)
{
	switch (kind)
	{
		case TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
			return true;
		default:
			return false;
	}
}

fn bool is_alias_source_name_kind(TokenKind kind)
{
	switch (kind)
	{
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
			return true;
		default:
			return false;
	}
}

<*
 Return whether kind may appear as a path's final segment with options.
 @param kind : "Candidate token kind for the segment."
 @param options : "Final-segment allowances used by the caller."
*>
fn bool is_path_final_kind(TokenKind kind, PathExprOptions options)
{
	if (kind == IDENT) return true;
	if (options.allow_const_final && kind == CONST_IDENT) return true;
	if (options.allow_attr_final && kind == AT_IDENT) return true;
	return false;
}

<*
 Append an arena-owned node slice into a temporary node list.
 @param [&inout] list : "Destination list."
 @param nodes : "Nodes to append."
*>
fn void append_node_array(List{Node*}* list, NodeArray nodes)
{
	foreach (node : nodes)
	{
		list.push(node);
	}
}

<*
 Parse attributes at the current token and append them into an existing list.
 @require(scope.ctx != null) : "Parser context to consume attributes from."
 @param [&inout] parent_node : "Node receiving visibility and has-attributes side effects."
 @param [&inout] list : "Destination list for parsed ATTRIBUTE_DECL nodes."
*>
fn void? parse_attributes_into(ContextScope scope, Node* parent_node, List{Node*}* list)
{
	ParseContext* ctx = scope.ctx;
	if (ctx.is(AT_IDENT))
	{
		append_node_array(list, parse_attributes(scope, parent_node)!);
	}
}

<*
 Parse an optional parenthesized list of interface type expressions.

 interface_type_list ::= '(' type_expr (',' type_expr)* ')' | empty
 @require(scope.ctx != null) : "Parser context positioned at '(' when present."
*>
fn NodeArray? parse_interface_type_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} interfaces;
	interfaces.init(tmem, 4);

	if (!consume(ctx, LPAREN)!)
	{
		return alloc::clone_slice(ctx.allocator, interfaces.array_view());
	}

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		Node* interface_type = parse_type_expr(scope, null)!;
		interfaces.push(interface_type);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(RPAREN))
		{
			interfaces.push(unexpected(ctx, "Expected interface name after ',' in interface type list")!);
			break;
		}
	}

	@expect_else(ctx, RPAREN ; err)
	{
		interfaces.push(err);
	}!;

	return alloc::clone_slice(ctx.allocator, interfaces.array_view());
}

fn bool is_error_or_missing_node(Node* node)
{
	return node.kind == ERROR || node.kind == MISSING;
}

fn void? skip_balanced_group(ParseContext* ctx, TokenKind open, TokenKind close)
{
	expect(ctx, open)!;

	int depth = 1;
	while (!ctx.eof() && depth > 0)
	{
		if (ctx.is(open))
		{
			depth++;
		}
		else if (ctx.is(close))
		{
			depth--;
		}

		advance(ctx)!;
	}
}

fn bool is_type_primitive(TokenKind kind)
{
	switch (kind)
	{
		case BOOL_TYPE:
		case CHAR_TYPE:
		case DOUBLE_TYPE:
		case FLOAT_TYPE:
		case FLOAT16_TYPE:
		case BFLOAT_TYPE:
		case INT128_TYPE:
		case ICHAR_TYPE:
		case INT_TYPE:
		case IPTR_TYPE:
		case LONG_TYPE:
		case SHORT_TYPE:
		case UINT128_TYPE:
		case UINT_TYPE:
		case ULONG_TYPE:
		case UPTR_TYPE:
		case USHORT_TYPE:
		case USZ_TYPE:
		case SZ_TYPE:
		case FLOAT128_TYPE:
		case TYPEID_TYPE:
		case FAULT_TYPE:
		case ANY_TYPE:
		case VOID_TYPE:
		case CT_TYPE_IDENT:
		case CT_TYPEOF:
		case CT_TYPEFROM:
			return true;
		default:
			return false;
	}
}

fn bool? is_declaration_followup(ParseContext* ctx)
{
	int i;

	while (ctx.peek(i)!.kind == IDENT && ctx.peek(i + 1)!.kind == SCOPE)
	{
		i += 2;
	}

	i++;

	if (ctx.is(CT_TYPEFROM) || ctx.is(CT_TYPEOF))
	{
		i++;
		int depth = 1;
		do
		{
			if (ctx.peek(i)!.kind == LPAREN) depth++;
			if (ctx.peek(i)!.kind == RPAREN) depth--;

			i++;
		} while (depth != 0 && ctx.peek(i)!.kind != EOF);
	}

	while (true)
	{
		TokenKind k = ctx.peek(i)!.kind;

		// Skip over common type modifiers
		if (k == ASTERISK || k == QUESTION)
		{
			i++;
		}
		else if (k == LBRACKET)
		{
			// Skip the entire [ ... ] block
			i++;
			while (ctx.peek(i)!.kind != RBRACKET && ctx.peek(i)!.kind != EOF) i++;
			i++;
		}
		else if (k == LVEC)
		{
			// Skip the entire <* ... > block
			i++;
			while (ctx.peek(i)!.kind != RVEC && ctx.peek(i)!.kind != EOF) i++;
			i++;
		}
		else if (k == LBRACE)
		{
			i++;
			while (ctx.peek(i)!.kind != RBRACE && ctx.peek(i)!.kind != EOF) i++;
			i++;
		}
		else
		{
			break;
		}
	}

	// After skipping modifiers, do we see a variable name?
	TokenKind final_k = ctx.peek(i)!.kind;
	return final_k == IDENT || final_k == CONST_IDENT || final_k == CT_IDENT;
}

fn bool can_start_expression(TokenKind kind)
{
	diagnostics::log_debug("can_start_expr: %s", kind.description);

	if (is_keyword_ident(kind) || is_base_type(kind))
	{
		return true;
	}

	switch (kind)
	{
		case IDENT:
		case AT_IDENT:
		case TYPE_IDENT:
		case CT_TYPE_IDENT:
		case CT_IDENT:
		case CONST_IDENT:
		case HASH_IDENT:
		case HASH_TYPE_IDENT:
		case BUILTIN:
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
		case INT_DECIMAL_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case INT_BIN_LITERAL:
		case STRING_LITERAL:
		case CHAR_LITERAL:
		case LPAREN:
		case MINUS:
		case BANG:
		case BIT_NOT:
		case AMP:
		case ASTERISK:
		case LBRACE:
			return true;
		default:
			return false;
	}
}

fn bool token_type_ends_case(TokenKind kind)
{
	return kind == CASE || kind == DEFAULT || kind == CT_DEFAULT || kind == RBRACE || kind == CT_CASE
		|| kind == CT_ENDSWITCH;
}

fn bool check_if_typed_parameter(ParseContext* ctx)
{
	TokenKind first  = ctx.current.kind;

	if (is_type(ctx))
	{
		return true;
	}

	if (first == IDENT)
	{
		if (ctx.can_peek(1) && ctx.peek(1)!.kind == SCOPE)
		{
			return true;
		}
	}

	return false;
}

fn Node* alloc_any_type_expr(ParseContext* ctx)
{
	int pos = ctx.current.pos;

	TypeExpr* type_node = ctx.ast.alloc_node(TypeExpr, pos, pos);

	type_node.type_kind = TYPE_IDENTIFIER;
	type_node.unresolved.name = ctx.ident_string("any");
	type_node.unresolved.name.range = { pos, pos + 3 };

	return type_node;
}

<*
 @return? OVERFLOW_PARSING : "if at top-level token"
*>
fn void? check_top_level_boundary(TokenKind kind)
{
	switch (kind)
	{
		case FN:
		case MACRO:
		case MODULE:
		case IMPORT:
		case ATTRDEF:
		case TYPEDEF:
		case ALIAS:
		case CONSTDEF:
		case ENUM:
		case EXTERN:
			return OVERFLOW_PARSING~;
		default: 
			break;
	}
}