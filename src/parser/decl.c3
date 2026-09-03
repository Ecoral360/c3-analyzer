module analyzer::parser;
import analyzer::core;
import analyzer::lexer;
import std::collections::list;
import std::io;

<*
 module_decl ::= module path_expr ';' attributes?
 @require scope.ctx.current.kind == MODULE
*>
fn Node* parse_module_decl(ContextScope scope)
{
	diagnostics::log_debug("parse_mod");

	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;

	advance(ctx);

	ModuleDecl* node = ctx.ast.alloc_node(ModuleDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;
	node.path = parse_path_expr(scope);

	if (!node.path)
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected a valid path");
		node.flags.has_error = true;
		synchronize(ctx, DECLARATION);
		return (Node*)node;
	}

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node);
	}

	(void)expect(ctx, node, EOS);

	PathExpr* path  = node.path.as(PathExpr);
	String mod_name = path.path.text;

	return (Node*)node;
}

<*
 @require scope.ctx.current.kind == DOCS_START
*>
fn Node* parse_contract_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx  = scope.ctx;
	ContractDecl* node = ctx.ast.alloc_node(ContractDecl, ctx.current.range);
	defer node.range.end = ctx.peek(-1).range.end;

	List{Node*} ensures;
	ensures.tinit();
	List{Node*} requires;
	requires.tinit();
	List{Node*} params;
	params.tinit();
	List{Node*} returns;
	returns.tinit();

	advance(ctx); // skip <*

	if (ctx.is(DOCS_TEXT))
	{
		node.comment = ctx.ident(ctx.current);
		advance(ctx);
	}

	while (!ctx.eof() && !ctx.is(DOCS_END))
	{
		String attr = ctx.current.value;
		diagnostics::log_debug("parse_contract - attribute = %s", attr);

		if (consume(ctx, AT_IDENT))
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				diagnostics::log_debug("parse_contract_decl - @require");
				requires.push(parse_contract_expr(scope));
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				diagnostics::log_debug("parse_contract_decl - @ensure");
				ensures.push(parse_contract_expr(scope));
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push(parse_contract_param(scope));
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				diagnostics::log_debug("parse_contract_decl - @deprecated");
				AttributeDecl* n = ctx.ast.alloc_node(AttributeDecl, ctx.current.range);
				node.deprecated = (Node*)n;
				n.name = ctx.ident_string(constants::KW_AT_DEPRECATED);
				n.attribute_kind = DEPRECATED;
				if (ctx.current.kind == EOS && ctx.peek(1).kind == STRING_LITERAL)
				{
					advance(ctx);
				}
				if (ctx.is(STRING_LITERAL))
				{
					List{Node*} exprs;
					exprs.tinit(1);
					exprs.push(parse_expr(scope));
					diagnostics::log_debug("parser @deprecated string");
					n.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
				}
			}
			else if (attr == constants::KW_AT_PURE)
			{
				node.is_pure = true;
			}
			else if (attr == constants::KW_AT_RETURN)
			{
				if (ctx.is(QUESTION))
				{
					advance(ctx);
					while (!ctx.eof())
					{
						returns.push(parse_expr(scope));
						if (!consume(ctx, COMMA))
						{
							break;
						}
					}
				}
				else
				{
					node.return_desc = parse_expr(scope);
				}
			}
			else
			{
				advance(ctx);
			}
		}
		else
		{
			advance(ctx);
		}
	}

	advance(ctx);

	node.ensures = alloc::clone_slice(ctx.allocator, ensures.array_view());
	node.requires = alloc::clone_slice(ctx.allocator, requires.array_view());
	node.params = alloc::clone_slice(ctx.allocator, params.array_view());
	node.returns = alloc::clone_slice(ctx.allocator, returns.array_view());

	return (Node*)node;
}

<*
 import_decl ::= import path_expr (',' path_expr)* ';' attributes?
 @require scope.ctx.current.kind == IMPORT
*>
fn Node* parse_import_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	ImportDecl* node = ctx.ast.alloc_node(ImportDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;
	List{Node*} temp_paths;
	temp_paths.init(tmem, 4);

	do
	{
		Node* path_node = parse_path_expr(scope);
		temp_paths.push(path_node);

		if (path_node.kind == ERROR)
		{
			node.flags.has_error = true;
		}

		// if (!consume(ctx, COMMA)) break;
		// if (ctx.is(EOS))
		// {
		// 	diagnostics::error(ctx.context, ctx.current.range, "Expected another path after ','");
		// 	node.flags.has_error = true;
		// 	break;
		// }
	} while (consume(ctx, COMMA));

	node.paths = alloc::clone_slice(ctx.allocator, temp_paths.array_view());

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node);
	}

	expect(ctx, node, EOS);

	return (Node*)node;
}

<*
 alias_type_decl ::= 'alias' TYPE_IDENT generic_decl? attributes? '=' type_expr ';'
 module_alias_decl ::= 'alias' IDENT attributes? '=' 'module' module_path ';'
 alias_decl ::= 'alias' alias_name generic_decl? attributes? '=' alias_source ';'
 alias_source   ::= (path? IDENTIFIER | path? CONST_IDENT | path? AT_IDENT) generic_parameters?
 @require scope.ctx.current.kind == ALIAS
*>
fn Node* parse_alias_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	AliasDecl* node = ctx.ast.alloc_node(AliasDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	Token t = ctx.current;
	switch (t.kind)
	{
		case IDENT:
		case TYPE_IDENT:
		case CONST_IDENT:
		case AT_IDENT:
			node.name = ctx.ident(t);
			node.name_kind = t.kind;
			advance(ctx);
			break;
		default:
			diagnostics::error(ctx.context, ctx.current.range, "Expected alias name");
			node.flags.has_error = true;
			synchronize(ctx, STATEMENT); // Skip to semicolon
			break;
	}

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}
	if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		node.attributes = parse_attributes(scope, node, { .allow_type_ident = true });
	}

	if (!consume(ctx, EQ))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '=' in alias declaration");
		node.flags.has_error = true;
		synchronize(ctx, STATEMENT);
	}

	if (ctx.is(MODULE))
	{
		node.alias_kind = MODULE_ALIAS;
		advance(ctx);
		node.target = parse_path_expr(scope);
	}
	else if (node.name_kind == TYPE_IDENT)
	{
		node.alias_kind = TYPE_ALIAS;
		node.target = parse_alias_type_target(scope);
	}
	else
	{
		node.alias_kind = IDENT_ALIAS;
		node.target = parse_expr(scope);
	}

	(void)expect(ctx, node, EOS);

	return node;
}

<*
 typedef_decl ::= 'typedef' TYPE_IDENT interface_list? attributes? '=' 'inline'? type_expr attributes? ';'
 @require scope.ctx.current.kind == TYPEDEF
*>
fn Node* parse_typedef_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags  = scope.flags;
	Range start       = ctx.current.range;
	advance(ctx);
	TypedefDecl* node = ctx.ast.alloc_node(TypedefDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	Token name = ctx.current;
	if (name.kind != TYPE_IDENT)
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected 'TYPE_IDENT' for typedef name");
		node.flags.has_error = true;
		if (!ctx.is(LESS) && !ctx.is(LPAREN) && !ctx.is(EQ))
		{
			advance(ctx);
		}
	}
	else
	{
		node.name = ctx.ident(name);
		advance(ctx);
	}

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}
	if (ctx.is(LPAREN))
	{
		node.interfaces = parse_interface_type_list(scope);
	}

	List{Node*} attributes;
	attributes.init(tmem, 4);
	parse_attributes_into(scope, (Node*)node, &attributes);

	if (!consume(ctx, EQ))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '='");
		node.flags.has_error = true;
		synchronize(ctx, STATEMENT);
	}
	else
	{
		if (consume(ctx, INLINE))
		{
			node.is_inline = true;
		}

		if (ctx.is(FN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Cannot define a new function type in typedef");
			node.flags.has_error = true;
			advance(ctx);
		}
		else
		{
			node.base_type = parse_type_expr(scope);
			if (!node.base_type) node.flags.has_error = true;
		}

		parse_attributes_into(scope, (Node*)node, &attributes);
	}

	node.attributes = alloc::clone_slice(ctx.allocator, attributes.array_view());
	expect(ctx, node, EOS);
	return node;
}

<*
 macro_decl ::= macro type_expr? (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
 @require scope.ctx.current.kind == MACRO
*>
fn Node* parse_macro_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags  = scope.flags;
	Range start       = ctx.current.range;

	advance(ctx);

	diagnostics::log_debug("parse_macro");

	MacroDecl* node = ctx.ast.alloc_node(MacroDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (is_type(ctx))
	{
		Node* first_type = parse_type_expr(scope);

		if (consume(ctx, DOT))
		{
			node.associated_type.set(first_type);
		}
		else
		{
			node.ret_type.set(first_type);

			if (is_type(ctx))
			{
				node.associated_type.set(parse_type_expr(scope));
				if (!consume(ctx, DOT))
				{
					diagnostics::error(ctx.context, ctx.current.range, "Expected '.' after associated type");
					node.flags.has_error = true;
				}
			}
		}
	}

	if (ctx.is(AT_IDENT) || ctx.is(IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected macro name identifier");
		node.flags.has_error = true;
	}

	parse_macro_params(scope, node);

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node);
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Extern macros cannot have a structural block body");
			node.flags.has_error = true;
			return (Node*)node;
		}
		node.body = parse_compound_stmt(scope);
	}
	else if (consume(ctx, IMPLIES))
	{
		if (flags.is_extern)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Extern macros cannot have an expression body");
			node.flags.has_error = true;
			return (Node*)node;
		}

		node.body = parse_short_body(scope, true);
	}
	else
	{
		(void)expect(ctx, node, EOS);
	}

	return node;
}

<*
 parameter_decl ::= parameter (("=" "...") | ("=" expression))?
 parameter      ::= type_expr ("..."? IDENTIFIER attributes?
 | "..."? CT_IDENT
 | (HASH_IDENT | "&" IDENTIFIER) attributes?
 | attributes?)
 | "..."
 | HASH_IDENT attributes?
 | "&" IDENTIFIER attributes?
 | IDENTIFIER "..."? attributes?
 | CT_IDENT
 | CT_IDENT "..."
*>
fn Node* parse_param_decl(ContextScope scope, ParamParseFlags flags = { })
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;

	VarDecl* node = ctx.ast.alloc_node(VarDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (consume(ctx, ELLIPSIS))
	{
		node.var_kind = VAR_PARAM;
		node.var_flags.is_variadic = true;
		return node;
	}

	bool is_ref                  = consume(ctx, AMP);
	Node* parsed_type            = null;
	bool has_ellipsis_after_type = false;

	if (!is_ref && check_if_typed_parameter(ctx))
	{
		parsed_type = parse_type_expr(scope);
		if (parsed_type && parsed_type.kind == ERROR)
		{
			node.flags.has_error = true;
		}
		if (parsed_type.as(TypeExpr).optional)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Parameters may not be optional");
			node.flags.has_error = true;
		}
		if (consume(ctx, ELLIPSIS))
		{
			has_ellipsis_after_type = true;
			node.var_flags.is_variadic = true;
		}
	}

	// allowed in @body(...) params, but not in regular macro param list
	if (!scope.flags.is_body_param && is_untypedlist_type(parsed_type))
	{
		diagnostics::error(
			ctx.context,
			parsed_type.range,
			"The type of a parameter cannot be an 'untypedlist', which is a compile time type"
		);
		node.flags.has_error = true;
	}

	node.type = parsed_type;

	Token t = ctx.current;
	switch (t.kind)
	{
		case CT_CONST_IDENT:
			diagnostics::error(ctx.context, ctx.current.range, "Parameter names may not be all uppercase.");
			node.flags.has_error = true;
			skip_until(ctx, { COMMA, RPAREN });
			break;
		case CT_IDENT:
			node.name = ctx.ident(t);
			node.var_kind = VAR_PARAM_CT;
			advance(ctx);
			if (consume(ctx, ELLIPSIS))
			{
				diagnostics::error(ctx.context, ctx.current.range, "Untyped constant vaargs are not supported.");
				node.flags.has_error = true;
			}
			break;
		case IDENT:
			String token_text = ctx.current.value;
			node.name = ctx.ident(t);
			node.var_kind = VAR_PARAM;
			node.var_flags.is_ref = is_ref;
			advance(ctx);

			if (token_text == "self")
			{
				node.var_flags.is_self = true;
				node.var_flags.is_self_by_ref = is_ref;
			}

			if (consume(ctx, ELLIPSIS))
			{
				if (has_ellipsis_after_type || parsed_type)
				{
					diagnostics::error(ctx.context, ctx.current.range, "Invalid variadic usage.");
					node.flags.has_error = true;
				}
				node.var_flags.is_variadic = true;
				node.type = alloc_any_type_expr(ctx);
			}
			break;
		case HASH_IDENT:
			node.name = ctx.ident(t);
			node.var_kind = VAR_PARAM_EXPR;
			advance(ctx);
			break;
		case CT_TYPE_IDENT:
			node.name = ctx.ident(t);
			node.var_kind = (parsed_type && parsed_type.kind != ERROR) ? VAR_PARAM : VAR_PARAM_CT_TYPE;
			advance(ctx);
			break;
		default:
			if (!parsed_type)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected parameter name or type.");
				node.flags.has_error = true;
				skip_until(ctx, { COMMA, RPAREN });
			}
	}

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node);
	}

	if (consume(ctx, EQ))
	{
		if (consume(ctx, ELLIPSIS))
		{
			node.var_flags.is_macro_optional_ellipsis = true;
		}
		else
		{
			// The initializer is its own expression: the modifiers of the
			// declaration around it ('var', 'const', 'static', ...) must not
			// reach the statements of a lambda written inside it.
			node.init_expr = parse_expr(scope.with_only_flags({ }));
		}
	}

	return node;
}

<*
 Whether the type written in front of a declaration is the bare 'untypedlist'
 keyword. A derived type - 'untypedlist*', 'untypedlist[2]' - is a different
 type and is left alone here.
*>
fn bool is_untypedlist_type(Node* type) @local
{
	if (!type || type.kind != TYPE_EXPR) return false;

	TypeExpr* type_expr = type.as(TypeExpr);

	if (type_expr.type_kind != TYPE_IDENTIFIER) return false;
	if (type_expr.unresolved.path || !type_expr.unresolved.name) return false;

	return type_expr.unresolved.name.text == "untypedlist";
}

<*
 var_decl ::= ('var' | type_expr) decl_element (',' decl_element)* ';'
 @todo "Split into -> parse_local, parse_global"
*>
fn Node* parse_var_decl(ContextScope scope, Node* type = null)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags  = scope.flags;
	Range start       = (type != null) ? type.range : ctx.current.range;

	Node* contract;
	if (ctx.is(DOCS_START))
	{
		contract = parse_contract_decl(scope);

		if (consume(ctx, INLINE))
		{
			flags.is_inline = true;
		}
	}

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Local variable cannot be 'extern'");
		}
		if (flags.is_inline)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Local variable cannot be 'inline'");
		}
	}

	Node* type_node = type;

	if (!type_node)
	{
		if (flags.is_var)
		{
			advance(ctx); // Consume 'var'
			flags.is_comptime = true;
		}
		else if (is_type_primitive(ctx.current.kind) || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
		{
			type_node = parse_type_expr(scope.with_only_flags(flags), null);
			if (type_node && type_node.kind == ERROR)
			{
				type_node = null; // Treat as untyped to recover
			}
		}
		else if (!flags.is_const)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected type or 'var'");
		}
	}

	VarDecl* head_node;
	VarDecl* tail_node;

	while (true)
	{
		Token t = ctx.current;

		if (t.kind != IDENT && t.kind != CONST_IDENT && t.kind != CT_IDENT)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected variable name");
			skip_until(ctx, { COMMA, EOS });
			if (!consume(ctx, COMMA)) break;
			continue;
		}

		Ident* name = ctx.ident(t);
		diagnostics::log_debug("var name: %s", t.value);
		advance(ctx);

		Range var_start   = (head_node == null) ? start : t.range;
		VarDecl* var_node = ctx.ast.alloc_node(VarDecl, var_start);

		if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
		{
			var_node.attributes = parse_attributes(scope, (Node*)var_node, { .allow_type_ident = true });
		}

		if (consume(ctx, EQ))
		{
			if (head_node != null)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Initializers not allowed in multi-decl");
			}
			if (flags.is_extern)
			{
				diagnostics::error(ctx.context, ctx.current.range, "Extern cannot have initializer");
			}

			var_node.init_expr = parse_expr(scope.with_only_flags({ }));
		}
		else if (flags.is_const && !flags.is_extern)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Constants must be initialized");
			var_node.flags.has_error = true;
		}

		var_node.name = name;
		var_node.type = type_node; // Reused across the entire chain segment
		var_node.next = null;

		var_node.var_flags.is_extern = flags.is_extern;
		var_node.var_flags.is_const = flags.is_const;
		var_node.var_flags.is_inline = flags.is_inline;
		var_node.var_flags.is_local = flags.is_local;
		var_node.var_flags.is_thread_local = flags.is_thread_local;
		var_node.var_flags.is_static = flags.is_static;
		var_node.var_flags.is_comptime = name.text.starts_with("$");

		// 'untypedlist' only exists at compile time, so it can only be the type
		// of a compile time variable `$name`, i.e never a struct member
		if (is_untypedlist_type(type_node))
		{
			if (flags.is_struct)
			{
				diagnostics::error(
					ctx.context,
					type_node.range,
					"Member '%s' cannot be an 'untypedlist', which is a compile time type",
					name.text
				);
				var_node.flags.has_error = true;
			}
			else if (!var_node.var_flags.is_comptime)
			{
				diagnostics::error(
					ctx.context,
					type_node.range,
					"Variable '%s' cannot be an 'untypedlist', which is a compile time type. Only a compile time variable ('$%s') can hold one",
					name.text,
					name.text
				);
				var_node.flags.has_error = true;
			}
		}

		if (flags.is_local)
		{
			var_node.var_kind = VAR_LOCAL;
		}
		else if (flags.is_struct)
		{
			var_node.var_kind = VAR_FIELD;
		}
		else
		{
			var_node.var_kind = VAR_GLOBAL;
		}

		if (head_node == null)
		{
			head_node = var_node;
			if (contract)
			{
				head_node.contract.set(contract);
			}
		}
		else
		{
			tail_node.next = var_node;
		}
		tail_node = var_node;

		tail_node.range.end = ctx.peek(-1).range.end;

		if (flags.is_expr) break;
		if (!consume(ctx, COMMA)) break;
	}

	if (head_node == null)
	{
		// Every name in the chain was rejected, so there is no VarDecl to
		// return or to flag. Hand back an error node instead of null:
		// callers push the result straight into ast.statements and expect
		// a valid Node there.
		Node* recovery = ctx.ast.error({ start.start, ctx.peek(-1).range.end });

		if (!flags.skip_eos)
		{
			expect(ctx, recovery, EOS);
		}

		return recovery;
	}

	if (!flags.skip_eos)
	{
		expect(ctx, head_node, EOS);
	}

	return head_node;
}

fn Node* make_overload(ParseContext* ctx, Token t)
{
	OverloadExpr* expr = ctx.ast.alloc_node(OverloadExpr, t.range);
	expr.overload_kind = core::get_overload_kind(t.kind);
	advance(ctx);
	return expr;
}

<*
 attributes ::= attribute attribute*
 attribute  ::= (AT_IDENT | path? AT_TYPE_IDENT) ("(" expression_list? ")")?
*>
fn NodeArray parse_attributes(ContextScope scope, Node* parent_node, AttributeParseFlags flags = { }) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} nodes;
	nodes.init(tmem, 4);

	while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		if (ctx.is(AT_TYPE_IDENT) && !flags.allow_type_ident)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Attribute '@TypeIdent' not allowed here");
			advance(ctx);
			continue; // Skip this attribute and try to find the next one
		}

		Token t = ctx.current;
		advance(ctx);

		AttributeDecl* attr_node = ctx.ast.alloc_node(AttributeDecl, t.range);
		defer attr_node.range.end = ctx.peek(-1).range.end;
		attr_node.name = ctx.ident(t);
		attr_node.attribute_kind = core::get_attribute_from_string(t.value);

		if (parent_node && attr_node.attribute_kind == AttributeKind.PRIVATE)
		{
			parent_node.visibility = Visibility.PRIVATE;
		}

		if (consume(ctx, LPAREN))
		{
			List{Node*} exprs;
			exprs.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				Node* expr;
				bool next_is_rparen = ctx.peek(1).kind == RPAREN;

				switch (ctx.current.kind)
				{
					case PLUS:
					case MINUS:
					case ASTERISK:
					case DIV:
					case MOD:
					case BIT_NOT:
					case BIT_OR:
					case BIT_XOR:
					case LSHIFT:
					case RSHIFT:
					case EQEQ:
					case LESS:
					case BIT_AND_ASSIGN:
					case BIT_OR_ASSIGN:
					case BIT_XOR_ASSIGN:
					case PLUS_ASSIGN:
					case MINUS_ASSIGN:
					case MULT_ASSIGN:
					case DIV_ASSIGN:
					case MOD_ASSIGN:
					case RSHIFT_ASSIGN:
					case LSHIFT_ASSIGN:
						if (!next_is_rparen) nextcase default;
						expr = make_overload(ctx, ctx.current);
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						diagnostics::log_debug("parse_attributes - found op overload: %s", ov_expr.kind.description);
						break;
					case AMP:
						if (next_is_rparen)
						{
							expr = make_overload(ctx, ctx.current);
							break;
						}
						expr = (Node*)ctx.ast.alloc_node(OverloadExpr, t.range);
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						advance(ctx);
						(void)expect(ctx, expr, LBRACKET);
						expr.range.end = ctx.current.range.end;
						(void)expect(ctx, expr, RBRACKET);
						ov_expr.overload_kind = OV_ELEMENT_REF;
						break;
					case LBRACKET:
						expr = (Node*)ctx.ast.alloc_node(OverloadExpr, t.range);
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						advance(ctx);
						(void)expect(ctx, expr, RBRACKET);
						ov_expr.overload_kind = consume(ctx, EQ) ? OV_ELEMENT_SET : OV_ELEMENT_AT;
						expr.range.end = ctx.peek(-1).range.end;
						break;
					case NOT_EQUAL:
					case LESS_EQ:
					case GREATER:
					case GREATER_EQ:
						diagnostics::error(
							ctx.context,
							ctx.current.range,
							"use '<' and '==', other comparison operations will be derived from those"
						);
						attr_node.flags.has_error = true;
					case PLUSPLUS:
					case MINUSMINUS:
						diagnostics::error(
							ctx.context,
							ctx.current.range,
							"Increment and decrement operators '++' and '--' cannot be directly overloaded, use '+=' and '-=' instead"
						);
						attr_node.flags.has_error = true;
					case DOT:
						diagnostics::error(ctx.context, ctx.current.range, "Cannot overload '.'");
						attr_node.flags.has_error = true;
					default:
						expr = parse_constant_expr(scope);
						break;
				}

				exprs.push(expr);
				if (!consume(ctx, COMMA)) break;
			}
			expect(ctx, attr_node, RPAREN);
			attr_node.exprs = alloc::clone_slice(ctx.allocator, exprs.array_view());
		}

		nodes.push(attr_node);

		if (flags.use_comma)
		{
			consume(ctx, COMMA);
		}
	}

	if (parent_node) parent_node.flags.has_attributes = nodes.len() > 0;

	return alloc::clone_slice(ctx.allocator, nodes.array_view());
}

<*
 ct_expand_decl ::= $expand '(' expr ')' attributes? ';'
 @require scope.ctx.current.kind == CT_EXPAND
*>
fn Node* parse_expand_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	CtExpandDecl* node = ctx.ast.alloc_node(CtExpandDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;
	if (!consume(ctx, LPAREN))
	{
		node.flags.has_error = true;
		diagnostics::error(
			ctx.context,
			ctx.current.range,
			"Expected '%s' got '%s'",
			ctx.current.kind.description,
			ctx.current.kind.description
		);

		skip_until(ctx, { RPAREN, EOS });
	}

	node.expr = parse_constant_expr(scope);
	if (!node.expr)
	{
		node.flags.has_error = true;
		skip_until(ctx, { RPAREN, EOS });
	}

	expect(ctx, (Node*)node, RPAREN);

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, (Node*)node);
	}

	expect(ctx, (Node*)node, EOS);

	return node;
}

<*
 struct_decl ::= "struct | union" TYPE_IDENT ("(" type ("," type)* ")")? attributes? "{" struct_body "}"
 @require (scope.ctx.current.kind == STRUCT || scope.ctx.current.kind == UNION)
*>
fn Node* parse_struct_union_decl(ContextScope scope, bool is_sub = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags  = scope.flags;

	Range start    = ctx.current.range;
	bool is_struct = ctx.is(STRUCT);
	advance(ctx);
	StructDecl* node = ctx.ast.alloc_node(StructDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;
	node.is_union = !is_struct;

	if (!is_sub)
	{
		if (ctx.is(TYPE_IDENT))
		{
			node.name = ctx.ident(ctx.current);
			advance(ctx);
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Structs must have a 'Type' identifier");
			node.flags.has_error = true;
		}
	}
	else if (ctx.is(IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}

	if (ctx.is(LPAREN))
	{
		node.interfaces = parse_interface_type_list(scope);
	}
	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope);
	}
	if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		node.attributes = parse_attributes(scope, node, { .allow_type_ident = true });
	}

	if (!consume(ctx, LBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '{' to start struct body");
		node.flags.has_error = true;
		return (Node*)node;
	}

	List{Node*} fields;
	fields.tinit();

	Node* tail_node = node;

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		if (ctx.is(STRUCT) || ctx.is(UNION) || ctx.is(BITSTRUCT))
		{
			Node* sub_decl;

			if (ctx.is(BITSTRUCT))
			{
				sub_decl = parse_bitstruct_decl(scope, true);
			}
			else
			{
				sub_decl = parse_struct_union_decl(scope, true);
			}

			if (sub_decl && sub_decl.kind != ERROR)
			{
				tail_node.as(StructDecl).next = sub_decl;
				// Unroll the sub-decl chain if it has multiple items to find the true new tail
				while (tail_node.as(StructDecl).next != null)
				{
					tail_node = tail_node.as(StructDecl).next;
				}
			}
		}
		else
		{
			ParseFlags struct_flags;
			struct_flags.is_struct = true;
			struct_flags.is_inline = consume(ctx, INLINE);
			Node* field = parse_var_decl(scope.with_only_flags(struct_flags), null);
			fields.push(field);
		}
	}

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '}' to terminate struct");
		node.flags.has_error = true;
	}

	node.fields = alloc::clone_slice(ctx.allocator, fields.array_view());
	return (Node*)node;
}

<*
 bitstruct_decl ::= "bitstruct" TYPE_IDENT ("(" type ("," type)* ")")? ":" type attributes? "{" bitstruct_body "}"
 @require scope.ctx.current.kind == BITSTRUCT
*>
fn Node* parse_bitstruct_decl(ContextScope scope, bool is_nested = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	StructDecl* node  = ctx.ast.alloc_node(StructDecl, ctx.current.range);
	advance(ctx);
	defer node.range.end = ctx.peek(-1).range.end;

	if (!is_nested || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
	{
		if (ctx.is(IDENT) || ctx.is(TYPE_IDENT))
		{
			node.name = ctx.ident(ctx.current);
			advance(ctx);
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Bitstructs must have a name");
			node.flags.has_error = true;
		}
	}

	if (ctx.is(LPAREN))
	{
		node.interfaces = parse_interface_type_list(scope.with_only_flags({ .no_generics = true }));
	}

	if (consume(ctx, COLON))
	{
		node.type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null);
		node.attributes = parse_attributes(scope, node);
	}

	if (!consume(ctx, LBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '{'");
		node.flags.has_error = true;
		return (Node*)node;
	}

	List{Node*} fields;
	fields.tinit();

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		if (!ctx.is(DOCS_START) && !is_type_primitive(ctx.current.kind) && !ctx.is(IDENT) && !ctx.is(TYPE_IDENT))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in bitstruct");
			skip_until(ctx, { EOS, RBRACE });
			if (consume(ctx, EOS)) continue;
			break;
		}

		VarDecl* field_node = ctx.ast.alloc_node(VarDecl, ctx.current.range);
		defer field_node.range.end = ctx.peek(-1).range.end;
		field_node.var_kind = VAR_BITFIELD;

		if (ctx.is(DOCS_START)) field_node.contract.set(parse_contract_decl(scope));

		field_node.type = parse_type_expr(scope);

		if (is_untypedlist_type(field_node.type))
		{
			diagnostics::error(
				ctx.context,
				field_node.type.range,
				"'untypedlist' is not supported in a bitstruct, only enums, integer and boolean values may be used"
			);
			field_node.flags.has_error = true;
		}

		field_node.attributes = parse_attributes(scope, field_node);

		if (ctx.is(IDENT))
		{
			field_node.name = ctx.ident(ctx.current);
			advance(ctx);
		}
		else
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected field name");
			field_node.flags.has_error = true;
		}

		if (consume(ctx, COLON))
		{
			field_node.init_expr = parse_constant_expr(scope);
			if (consume(ctx, DOTDOT))
			{
				field_node.bit_end = parse_constant_expr(scope);
			}
		}

		if (!consume(ctx, EOS))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected ';'");
			skip_until(ctx, { EOS, RBRACE });
			consume(ctx, EOS);
		}

		fields.push((Node*)field_node);
	}

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '}'");
		node.flags.has_error = true;
	}

	node.fields = alloc::clone_slice(ctx.allocator, fields.array_view());

	return (Node*)node;
}

<*
 faultdef_decl ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
 @require scope.ctx.current.kind == FAULTDEF
*>
fn Node* parse_faultdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	FaultdefDecl* node = ctx.ast.alloc_node(FaultdefDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	List{Node*} faults;
	faults.tinit();

	while (!ctx.eof() && !ctx.is(EOS))
	{
		if (!ctx.is(CONST_IDENT))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected constant identifier for fault");
			node.flags.has_error = true;
			skip_until(ctx, { COMMA, EOS });

			if (consume(ctx, COMMA)) continue;
			break;
		}

		FaultDecl* fault_node = ctx.ast.alloc_node(FaultDecl, ctx.current.range);
		defer fault_node.range.end = ctx.peek(-1).range.end;

		if (ctx.is(AT_IDENT))
		{
			fault_node.contract.set(parse_contract_decl(scope));
		}

		fault_node.name = ctx.ident(ctx.current);

		advance(ctx);

		fault_node.attributes = parse_attributes(scope, node);

		faults.push((Node*)fault_node);

		if (!consume(ctx, COMMA)) break;
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' to terminate faultdef");
		node.flags.has_error = true;
	}

	node.faults = alloc::clone_slice(ctx.allocator, faults.array_view());

	return (Node*)node;
}

<*
 interface_decl ::= 'interface' TYPE_IDENT ':' (TYPE_IDENT (',' TYPE_IDENT) interface_body
 @require scope.ctx.current.kind == INTERFACE
*>
fn Node* parse_interface_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	InterfaceDecl* node = ctx.ast.alloc_node(InterfaceDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (ctx.is(TYPE_IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "Interfaces must have a 'Type' identifier");
		node.flags.has_error = true;
	}

	List{Node*} list;
	list.tinit();

	if (consume(ctx, COLON))
	{
		while (true)
		{
			list.push(parse_type_expr(scope.with_only_flags({ .no_generics = true }), null));
			if (!consume(ctx, COMMA)) break;
		}
	}

	node.interfaces = alloc::clone_slice(ctx.allocator, list.array_view());
	node.attributes = parse_attributes(scope, node);

	if (!consume(ctx, LBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '{' to start interface body");
		node.flags.has_error = true;
		return (Node*)node;
	}

	List{Node*} methods;
	methods.tinit();

	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		if (!ctx.is(DOCS_START) && !ctx.is(FN))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Unexpected token in interface body");
			skip_until(ctx, { FN, RBRACE });
			if (ctx.is(RBRACE)) break;
		}

		Node* contract;
		if (ctx.is(DOCS_START))
		{
			contract = parse_contract_decl(scope);
		}
		Node* func_node = parse_fn_decl(scope.with_only_flags({ .is_interface = true }));
		if (func_node && func_node.kind != ERROR)
		{
			FnDecl* func = func_node.as(FnDecl);
			if (contract) func.contract.set(contract);
			methods.push(func_node);
		}
	}

	node.methods = alloc::clone_slice(ctx.allocator, list.array_view());

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '}' to terminate interface");
		node.flags.has_error = true;
	}

	return (Node*)node;
}

<*
 attrdef_decl ::= "attrdef" AT_IDENT ("(" parameter_list? ")")? ("=" attribute_list)? ";"
 @require scope.ctx.current.kind == ATTRDEF
*>
fn Node* parse_attrdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	AttrdefDecl* node = ctx.ast.alloc_node(AttrdefDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (ctx.is(AT_TYPE_IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "Attrdef must have a '@Type' identifier");
		node.flags.has_error = true;
		skip_until(ctx, { LPAREN, EQ, EOS });
	}

	if (ctx.is(LPAREN))
	{
		node.params = parse_parameter_list(scope); // , { .is_attrdef = true });
	}

	if (ctx.is(AT_IDENT))
	{
		node.defined_attributes = parse_attributes(scope, node);
	}

	if (consume(ctx, EQ))
	{
		node.defined_attributes = parse_attributes(scope, (Node*)node, { .use_comma = true });
	}

	if (!consume(ctx, EOS))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected ';' to terminate attrdef declaration");
		node.flags.has_error = true;
		skip_until(ctx, { EOS });
		consume(ctx, EOS);
	}

	return (Node*)node;
}

<*
 enum_decl ::= "enum" TYPE_IDENT ("(" type ("," type)* ")")? (":" type? enum_param_list?)? attributes? "{" enum_body "}"

 constdef_decl ::= "constdef" TYPE_IDENT ("(" type ("," type)* ")")? (":" "inline"? type)? attributes? "{" constdef_body
 "}"
 @require scope.ctx.current.kind == ENUM || scope.ctx.current.kind == CONSTDEF
*>
fn Node* parse_enum_constdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags  = scope.flags;
	Range start       = ctx.current.range;

	advance(ctx);

	EnumDecl* node = ctx.ast.alloc_node(EnumDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	if (ctx.is(TYPE_IDENT))
	{
		node.name = ctx.ident(ctx.current);
		advance(ctx);
	}
	else
	{
		diagnostics::error(ctx.context, ctx.current.range, "constdef & enum must have a 'Type' identifier");
		node.flags.has_error = true;
		skip_until(ctx, { LPAREN, EQ, LBRACE, EOS });
	}

	if (ctx.is(LPAREN))
	{
		node.interfaces = parse_interface_type_list(scope);
	}

	// Optional backing type and/or associated value parameters: ":" "inline"? type? enum_param_list?
	if (consume(ctx, COLON))
	{
		node.is_inline_backing = consume(ctx, INLINE);

		if (!ctx.is(LPAREN))
		{
			node.backing_type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null);
		}

		if (consume(ctx, LPAREN))
		{
			List{Node*} assoc;
			assoc.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				VarDecl* param = ctx.ast.alloc_node(VarDecl, ctx.current.range);

				param.type = parse_type_expr(scope);
				if (is_non_type_ident(ctx.current.kind))
				{
					param.name = ctx.ident(ctx.current);
					advance(ctx);
				}
				if (ctx.is(AT_IDENT))
				{
					parse_attributes(scope, param);
				}

				param.range.end = ctx.current.range.end;

				assoc.push((Node*)param);
				if (!consume(ctx, COMMA)) break;
			}

			if (!consume(ctx, RPAREN))
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected ')' in parameter list");
			}

			node.assoc_params = alloc::clone_slice(ctx.allocator, assoc.array_view());
		}
	}

	if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		node.attributes = parse_attributes(scope, node, { .allow_type_ident = true });
	}

	if (!consume(ctx, LBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '{'");
		node.flags.has_error = true;
		return (Node*)node;
	}

	List{Node*} variants;
	variants.init(tmem, 4);
	while ENUM_VARIANT: (!ctx.is(RBRACE) && !ctx.eof())
	{
		if (!ctx.is(DOCS_START) && !ctx.is(CONST_IDENT))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected enum variant or contract");
			skip_until(ctx, { COMMA, RBRACE });
			consume(ctx, COMMA); // Try to jump to next
			continue;
		}

		Node* contract;
		if (ctx.is(DOCS_START))
		{
			contract = parse_contract_decl(scope);
		}

		VarDecl* variant = ctx.ast.alloc_node(VarDecl, ctx.current.range);
		variant.var_kind = VAR_GLOBAL;
		variant.contract.set(contract);
		variant.var_flags.is_const = true;
		variant.name = ctx.ident(ctx.current);
		advance(ctx);

		// Optional per-variant attributes: @attr ...  (come before = and {})
		if (ctx.is(AT_IDENT))
		{
			variant.attributes = parse_attributes(scope, variant);
		}

		// Optional ordinal: "=" expr
		if (consume(ctx, EQ))
		{
			variant.init_expr = parse_expr(scope);
		}

		// Optional associated values: "{" expr ("," expr)* "}"
		if (ctx.is(LBRACE))
		{
			variant.assoc_values = parse_expr(scope);
		}

		variants.push(variant);

		if (!consume(ctx, COMMA)) break;
	}

	if (!consume(ctx, RBRACE))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '}'");
		node.flags.has_error = true;
	}

	node.variants = alloc::clone_slice(ctx.allocator, variants.array_view());

	return (Node*)node;
}

<*
 generic_decl ::= '<' (type_expr | ident_expr)* '>'
 @return "null if no generics are present"
 @require scope.ctx.current.kind == LESS
*>
fn Node* parse_generic_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	Range start       = ctx.current.range;
	advance(ctx);
	if (ctx.is(GREATER))
	{
		diagnostics::error(ctx.context, ctx.current.range, "At least one parameter is required");
		return ctx.ast.error(ctx.current.range);
	}

	GenericDecl* node = ctx.ast.alloc_node(GenericDecl, start);
	defer node.range.end = ctx.peek(-1).range.end;

	List{Node*} params;
	params.tinit();
	while (!ctx.eof())
	{
		if (!ctx.is(TYPE_IDENT) && !ctx.is(CONST_IDENT))
		{
			diagnostics::error(ctx.context, ctx.current.range, "Expected type or constant identifier in generic list");
			node.flags.has_error = true;

			skip_until(ctx, { COMMA, GREATER });

			if (consume(ctx, COMMA)) continue;
			break;
		}

		// so it only parses the prefix
		params.push(parse_expr(scope, HIGHEST));

		if (!consume(ctx, COMMA))
		{
			if (!ctx.is(GREATER))
			{
				diagnostics::error(ctx.context, ctx.current.range, "Expected ',' or '>'");
				node.flags.has_error = true;
				skip_until(ctx, { GREATER });
			}
			break;
		}
	}

	if (!consume(ctx, GREATER))
	{
		diagnostics::error(ctx.context, ctx.current.range, "Expected '>' to close generic list");
		node.flags.has_error = true;
	}

	node.params = alloc::clone_slice(ctx.allocator, params.array_view());
	return (Node*)node;
}
