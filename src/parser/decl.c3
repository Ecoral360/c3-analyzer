module analyzer::parser;
import analyzer::core;
import std::collections::list;
import std::io;

<*
 module_decl ::= module path_expr ';' attributes?
*>
fn Node*? parse_module_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, MODULE)!;
	plog::debug("parse_mod");
	ModuleDecl* node = ctx.ast.alloc_node(ModuleDecl, start_pos);
	node.path = parse_path_expr(scope)!;
	node.generics = parse_generic_decl(scope)!;

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node)!;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;

	PathExpr* path = node.path.as(PathExpr);
    String mod_name = path.path.text;

    if (ctx.on_new_module != null)
    {
        ctx.section = ctx.on_new_module(ctx.user_data, mod_name);
    }

	return (Node*)node;
}

<*
 
*>
fn Node*? parse_contract_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	if (!ctx.is(CONTRACT))
	{
		ctx.error("Expected contract here");
		return ctx.ast.error(start_pos);
	}
	Token contract_token = ctx.current();
	if (contract_token.len <= 4)
	{
		advance(ctx)!;
		return ctx.ast.missing(contract_token.pos);
	}
	int global_offset = contract_token.pos;
	String slice      = ctx.token_text(contract_token);
	advance(ctx)!; // skip over contract

	// store the "normal" tokens and index temporarly since
	// we need to swap them
	Token[] main_tokens = ctx.tokens;
	int main_index      = ctx.pos;
	defer
	{
		ctx.tokens = main_tokens;
		ctx.pos = main_index;
	}

	List{Token} contract_tokens;
	contract_tokens.tinit();
	ContractLexer cl;
	cl.init(slice);

	// calculate the offset for 'ContractLexer' contract[2:^4];
	int open_marker_len = 2;
	int total_inner_len = slice.len - 4;
	int first_at_index  = total_inner_len - cl.lexer.buffer.len;
	int offset          = contract_token.pos + open_marker_len + first_at_index;

	while (try next = cl.next())
	{
		// make return a identifier so the it can be parsed as expr
		if (next.kind == RETURN)
		{
			next.kind = IDENT;
		}

		next.pos += offset;
		contract_tokens.push(next);

		plog::debug("ContractLexer - added: %s", next.kind);
	}
	contract_tokens.push({ .kind = EOF, .pos = (contract_tokens.last()
		.pos + contract_tokens.last().len) ?? 0, .len = 0 });

	ctx.tokens = contract_tokens.array_view();
	ctx.pos = 0;

	ContractDecl* node             = ctx.ast.alloc_node(ContractDecl, ctx.current().pos);
	plog::debug("comment : %s", cl.description);
	node.comment = ctx.ident({
		.kind = IDENT,
		.pos = contract_token.pos + 2,
		.len = cl.desc_len
	});

	List{Node*} ensures;
	ensures.tinit();
	List{Node*} requires;
	requires.tinit();
	List{Node*} params;
	params.tinit();
	List{Node*} returns;
	returns.tinit();

	while (!ctx.eof())
	{
		String attr = ctx.token_text(ctx.current());
		plog::debug("parse_contract - attribute = %s", attr);

		if (consume(ctx, AT_IDENT)!)
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				plog::debug("parse_contract_decl - @require");
				requires.push(parse_contract_expr(scope)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				plog::debug("parse_contract_decl - @ensure");
				ensures.push(parse_contract_expr(scope)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push(parse_contract_param(scope))!;
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				plog::debug("parse_contract_decl - @deprecated");
				AttributeDecl* n = ctx.ast.alloc_node(AttributeDecl, ctx.current().pos);
				node.deprecated = (Node*)n;
				n.name = ctx.ident_string(constants::KW_AT_DEPRECATED);
				n.attribute_kind = DEPRECATED;
				if (ctx.current().kind == EOS && ctx.peek(1)!.kind == STRING_LITERAL)
				{
					advance(ctx)!;
				}
				int start = ctx.current().pos;
				if (ctx.is(STRING_LITERAL))
				{
					List{Node*} exprs;
					exprs.tinit(1);
					exprs.push(parse_expr(scope)!);
					plog::debug("parser @deprecated string");
					n.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
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
					advance(ctx)!;
					while (!ctx.eof())
					{
						returns.push(parse_expr(scope)!);
						if (!consume(ctx, COMMA)!)
						{
							break;
						}
					}
				}
				else
				{
					node.return_desc = parse_expr(scope)!;
				}
			}
			else
			{
				if (catch advance(ctx)) break;
			}
		}
		else
		{
			if (catch advance(ctx)) break;
		}
	}

	node.ensures = alloc::clone_slice(ctx.arena, ensures.array_view());
	node.requires = alloc::clone_slice(ctx.arena, requires.array_view());
	node.params = alloc::clone_slice(ctx.arena, params.array_view());
	node.returns = alloc::clone_slice(ctx.arena, returns.array_view());

	return (Node*)node;
}

<*
 import_decl ::= import path_expr (',' path_expr)* ';' attributes?
*>
fn Node*? parse_import_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, IMPORT)!;
	ImportDecl* node = ctx.ast.alloc_node(ImportDecl, start_pos);
	List{Node*} temp_paths;
	temp_paths.init(tmem, 4);

	while (true)
	{
		Node* path_node = parse_path_expr(scope)!;
		temp_paths.push(path_node);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(EOS))
		{
			temp_paths.push(unexpected(ctx, "Expected an import path after ','")!);
			break;
		}
	}

	node.paths = alloc::clone_slice(ctx.arena, temp_paths.array_view());

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node)!;
	}

	node.offset.end = ctx.current_pos();
	
	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 alias_type_decl ::= 'alias' TYPE_IDENT generic_decl? attributes? '=' type_expr ';'
 module_alias_decl ::= 'alias' IDENT attributes? '=' 'module' module_path ';'
 alias_decl ::= 'alias' alias_name generic_decl? attributes? '=' alias_source ';'
*>
fn Node*? parse_alias_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, ALIAS)!;
	AliasDecl* node = ctx.ast.alloc_node(AliasDecl, start_pos);

	do CHECK_NAME:
	{
		Token t = @expect_some_else(ctx, { TYPE_IDENT, IDENT, CONST_IDENT, AT_IDENT } ; err)
		{
			ctx.error("Expected alias name identifier");
			break CHECK_NAME;
		}!;

		node.name = ctx.ident(t);
		node.name_kind = t.kind;
	};

	node.generics = parse_generic_decl(scope)!;
	node.attributes = parse_attributes(scope, node, { .allow_type_ident = true })!;

	expect(ctx, EQ)!;

	if (ctx.is(MODULE))
	{
		node.alias_kind = MODULE_ALIAS;
		advance(ctx)!;
		node.target = parse_path_expr(scope)!;
	}
	else if (node.name_kind == TYPE_IDENT)
	{
		node.alias_kind = TYPE_ALIAS;
		node.target = parse_alias_type_target(scope)!;
	}
	else
	{
		node.alias_kind = IDENT_ALIAS;
		node.target = parse_expr(scope)!;
		if (ctx.is(LBRACE))
		{
			// TODO: represent generic target arguments for identifier aliases.
			skip_balanced_group(ctx, LBRACE, RBRACE)!;
		}
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;
	return node;
}

<*
 typedef_decl ::= 'typedef' TYPE_IDENT interface_list? attributes? '=' 'inline'? type_expr attributes? ';'

 Typedef declarations create distinct types. Function pointer syntax is
 alias-only in C3, so a typedef base beginning with `fn` is consumed only for
 recovery and an ERROR node is returned.
*>
fn Node*? parse_typedef_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;
	expect(ctx, TYPEDEF)!;
	TypedefDecl* node = ctx.ast.alloc_node(TypedefDecl, start_pos);
	if (flags.is_inline)
	{
		ctx.error("'inline' must appear after '=' in typedef declarations");
		node.kind = MISSING;
	}

	Token name = ctx.current();
	if (name.kind != TYPE_IDENT)
	{
		ctx.error("Expected typedef type name");
		node.kind = MISSING;
		if (!ctx.is(EOS) && !ctx.eof())
		{
			advance(ctx)!;
		}
	}
	else
	{
		node.name = ctx.ident(name);
		advance(ctx)!;
	}

	node.generics = parse_generic_decl(scope)!;
	node.interfaces = parse_interface_type_list(scope)!;
	foreach (interface_type : node.interfaces)
	{
		if (is_error_or_missing_node(interface_type))
		{
			node.kind = MISSING;
		}
	}

	List{Node*} attributes;
	attributes.init(tmem, 4);
	parse_attributes_into(scope, (Node*)node, &attributes)!;

	expect(ctx, EQ)!;

	if (consume(ctx, INLINE)!)
	{
		node.is_inline = true;
	}

	if (ctx.is(FN))
	{
		unexpected(ctx, "Cannot define a new function type")!;
	}
	else
	{
		node.base_type = parse_type_expr(scope)!;
	}

	parse_attributes_into(scope, (Node*)node, &attributes)!;
	node.attributes = alloc::clone_slice(ctx.arena, attributes.array_view());
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;
	return node;
}

<*
 macro_decl ::= macro type_expr? (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_macro_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	expect(ctx, MACRO)!;

	plog::debug("parse_macro");

	MacroDecl* node = ctx.ast.alloc_node(MacroDecl, start_pos);

	if (is_type(ctx))
    {
        Node* first_type = parse_type_expr(scope)!;

        if (consume(ctx, DOT)!)
        {
            node.associated_type.set(first_type);
        }
        else
        {
            node.ret_type.set(first_type);

            if (is_type(ctx))
            {
                node.associated_type.set(parse_type_expr(scope)!);
                expect(ctx, DOT)!;
            }
        }
    }
	
	do NAME:
	{
		Token t;
		if (ctx.is(AT_IDENT))
		{
			t = ctx.current();
			advance(ctx)!;
		}
		else
		{
			t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
			{
				ctx.error("Expected macro name identifier");
				break NAME;
			}!;
		}

		node.name = ctx.ident(t);
	};

	parse_macro_params(scope, node)!;

	if (ctx.is(LESS))
	{
		node.generics = parse_generic_decl(scope)!;
	}

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node)!;
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			return ctx.ast.error(start_pos);
		}
		node.body = parse_compound_stmt(scope)!;
		node.offset.end = node.body.offset.end;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			return ctx.ast.error(start_pos);
		}

		node.body = parse_short_body(scope, true)!;
		node.offset.end = node.body.offset.end;		
	}
	else
	{
		// No body provided
		node.offset.end = ctx.current_pos();
		expect(ctx, EOS)!;
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
 @require (scope.ctx != null)
*>
fn Node*? parse_param_decl(ContextScope scope, ParamParseFlags flags = {})
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;

	VarDecl* node = ctx.ast.alloc_node(VarDecl, start_pos);

	if (consume(ctx, ELLIPSIS)!)
	{
		node.var_kind = VAR_PARAM;
		node.flags.is_variadic = true;
		return node;
	}

	bool is_ref                  = consume(ctx, AMP)!;
	Node* parsed_type            = null;
	bool has_ellipsis_after_type = false;

	if (!is_ref && check_if_typed_parameter(ctx))
	{
		parsed_type = parse_type_expr(scope)!;
		if (parsed_type.kind == ERROR) return parsed_type;
		if (parsed_type.as(TypeExpr).optional)
		{
			ctx.error("Parameters may not be optional");
		}

		if (consume(ctx, ELLIPSIS)!)
		{
			has_ellipsis_after_type = true;
			node.flags.is_variadic = true;
		}
	}

	node.type = parsed_type;

	Token t = ctx.current();
	switch (t.kind)
	{
		case CT_CONST_IDENT:
			ctx.error("Parameter names may not be all uppercase.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
		case CT_IDENT:
			node.name = ctx.ident(t);
			node.var_kind = VAR_PARAM_CT;
			node.offset.end = ctx.current_pos();
			advance(ctx)!;
			if (consume(ctx, ELLIPSIS)!)
			{
				ctx.error("Untyped constant vaargs are not supported.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			break;
		case IDENT:
			String token_text = ctx.current_text();
			node.name = ctx.ident(ctx.current());
			node.var_kind = VAR_PARAM;
			node.flags.is_ref = is_ref;
			node.offset.end = ctx.current_pos();
			advance(ctx)!;

			if (token_text == "self")
			{
				node.flags.is_self = true;
				node.flags.is_self_by_ref = is_ref;
			}

			if (consume(ctx, ELLIPSIS)!)
			{
				if (has_ellipsis_after_type)
				{
					ctx.error("Duplicate '...' variadic marker encountered.");
					ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
					return ctx.ast.error(start_pos);
				}
				if (parsed_type)
				{
					ctx.error("For typed variadic parameters, '...' must follow the type expression, not the name.");
					ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
					return ctx.ast.error(start_pos);
				}
				node.flags.is_variadic = true;
				node.type = alloc_any_type_expr(ctx);
			}
			break;
		case HASH_IDENT:
			if (is_ref || has_ellipsis_after_type)
			{
				ctx.error("Expression and Type parameters cannot be variadic or references.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			node.name = ctx.ident(t);
			node.var_kind = VAR_PARAM_EXPR;
			node.offset.end = ctx.current_pos();
			advance(ctx)!;
			break;
		case CT_TYPE_IDENT:
			if (is_ref || has_ellipsis_after_type)
			{
				ctx.error("Expression and Type parameters cannot be variadic or references.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			node.name = ctx.ident(t);
			node.var_kind = (parsed_type && parsed_type.kind != MISSING) ? VAR_PARAM : VAR_PARAM_CT_TYPE;
			node.offset.end = ctx.current_pos();
			advance(ctx)!;
			break;
		case COMMA:
		case RPAREN:
			if (parsed_type == null)
			{
				ctx.error("Expected a parameter name or type specification.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			node.var_kind = VAR_PARAM;
			break;

		default:
			ctx.error("Expected a valid parameter definition.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
	}

	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node)!;
	}

	if (consume(ctx, EQ)!)
	{
		if (consume(ctx, ELLIPSIS)!)
		{
			node.flags.is_macro_optional_ellipsis = true;
		}
		else
		{
			node.init_expr = parse_expr(scope)!;
			node.offset.end = node.init_expr.offset.end;
		}
	}

	return node;
}

<*
 var_decl ::= ('var' | type_expr) decl_element (',' decl_element)* ';'
*>
fn Node*? parse_var_decl(ContextScope scope, Node* type = null)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = (type != null) ? type.offset.start : ctx.current().pos;

	Node* contract;
	if (ctx.is(CONTRACT))
	{
		contract = parse_contract_decl(scope)!;

		if (consume(ctx, INLINE)!)
		{
			flags.is_inline = true;
		}
	}

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			unexpected(ctx, "A local variable cannot have an 'extern' modifier");
			advance(ctx)!;
		}
		if (flags.is_inline)
		{
			unexpected(ctx, "A local variable cannot be 'inline'");
		}
	}
	
	Node* type_node = type;

	if (!type_node)
	{
		if (flags.is_var)
		{
			advance(ctx)!; // Consume 'var'
			flags.is_comptime = true;
		}
		else if (is_type_primitive(ctx.current().kind) || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
		{
			type_node = parse_type_expr(scope.with_only_flags(flags), null)!;
			if (type_node.kind == ERROR) return type_node;
		}
		else if (!flags.is_const)
		{
			unexpected(ctx, "Expected a valid type signature or 'var'");
		}
	}

	VarDecl* head_node;
	VarDecl* tail_node;

	while (true)
	{
		Token t = ctx.current();

		//if (flags.is_const && t.kind != CONST_IDENT)
		//{
		//	unexpected(ctx, "Constants must use an uppercase CONST_IDENT, found '%s'", ctx.current().kind.description);
		//}
		//if (!flags.is_const && t.kind != IDENT && !flags.is_local && !flags.is_comptime)
		//{
		//	unexpected(ctx, "Global variables must use lower-case IDENT, found '%s'", ctx.current().kind.description);
		//}
		//if (t.kind != IDENT && t.kind != CONST_IDENT && !flags.is_comptime)
		//{
		//	unexpected(ctx, "Expected a variable name identifier, got '%s'", ctx.current().kind.description);
		//}
		//if (t.kind != CT_IDENT && t.kind != CT_TYPE_IDENT && flags.is_comptime)
		//{
		//	unexpected(ctx, "name must be a $ident")!;
		//}


		Ident* name = ctx.ident(t);
		plog::debug("var name: %s", ctx.token_text(t));
		advance(ctx)!;

		int var_start = (head_node == null) ? start_pos : t.pos;
		VarDecl* var_node    = ctx.ast.alloc_node(VarDecl, var_start);

		if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
		{
			var_node.attributes = parse_attributes(scope, (Node*)var_node, { .allow_type_ident = true })!;
		}

		Node* init_expr = null;

		if EQ_LABEL: (ctx.is(EQ))
		{
			advance(ctx)!;

			if (head_node != null)
			{
				unexpected(ctx, "Initializers are not allowed on multi decleration");
			}
			if (flags.is_extern)
			{
				unexpected(ctx, "An extern declaration cannot contain an initial value assignment expression");
			}
			if (flags.is_struct)
			{
				unexpected(ctx, "Fields cannot have an initializer");
			}

			init_expr = parse_expr(scope)!;
			if (init_expr.kind == ERROR) return init_expr;
		}
		else if (flags.is_const && !flags.is_extern)
		{
			unexpected(ctx, "Constants must be initialized at their declaration site")!;
		}

		var_node.name = name;
		var_node.type = type_node; // Reused across the entire chain segment
		var_node.init_expr = init_expr;
		var_node.next = null;

		var_node.flags.is_extern = flags.is_extern;
		var_node.flags.is_const = flags.is_const;
		var_node.flags.is_inline = flags.is_inline;
		var_node.flags.is_local = flags.is_local;
		var_node.flags.is_thread_local = flags.is_thread_local;
		var_node.flags.is_static = flags.is_static;

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

		var_node.offset.end = ctx.current().pos;

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

		if (flags.is_expr) break;
		if (!consume(ctx, COMMA)!) break;
	}

	if (!flags.skip_eos)
	{
		if (!consume(ctx, EOS)!)
		{
			ctx.error("Expected ';' to terminate variable declaration sequence");
		}
	}

	return head_node;
}

fn Node* make_overload(ParseContext* ctx, Token t)
{
	OverloadExpr* expr = ctx.ast.alloc_node(OverloadExpr, t.pos, t.end_pos());
	expr.overload_kind = core::get_overload_kind(t.kind);
	(void)advance(ctx);
	return expr;
}

<*
 attributes ::= attribute attribute*
  attribute  ::= (AT_IDENT | path? AT_TYPE_IDENT) ("(" expression_list? ")")?
 @require(scope.ctx != null)
*>
fn NodeArray? parse_attributes(ContextScope scope, Node* parent_node, AttributeParseFlags flags = { }) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} nodes;
	nodes.init(tmem, 4);

	while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		if (ctx.is(AT_TYPE_IDENT) && !flags.allow_type_ident)
		{
			unexpected(ctx, "Tried parsing a @TypeIdent when not allowed")!;
		}

		Token t = ctx.current();
		advance(ctx)!;

		AttributeDecl* attr_node = ctx.ast.alloc_node(AttributeDecl, t.pos);
		String text = ctx.token_text(t);
		attr_node.name = ctx.ident(t);
		attr_node.attribute_kind = core::get_attribute_from_string(text);

		if (parent_node && attr_node.attribute_kind == AttributeKind.PRIVATE)
		{
			parent_node.visibility = Visibility.PRIVATE;
		}

		if (consume(ctx, LPAREN)!)
		{
			List{Node*} exprs; exprs.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				Node* expr;
				bool next_is_rparen = ctx.can_peek(1) && ctx.peek(1)!.kind == RPAREN;

				switch (ctx.current().kind)
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
						expr = make_overload(ctx, ctx.current());
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						plog::debug("parse_attributes - found op overload: %s", ov_expr.kind.description);
						break;
					case AMP:
						if (next_is_rparen)
						{
							expr = make_overload(ctx, ctx.current());
							break;
						}
						expr = (Node*)ctx.ast.alloc_node(OverloadExpr, t.pos, t.end_pos());
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						advance(ctx)!;
						expect(ctx, LBRACKET)!;
						expr.offset.end = ctx.current_pos();
						expect(ctx, RBRACKET)!;
						ov_expr.overload_kind = OV_ELEMENT_REF;
						break;
					case LBRACKET:
						expr = (Node*)ctx.ast.alloc_node(OverloadExpr, t.pos, t.end_pos());
						OverloadExpr* ov_expr = expr.as(OverloadExpr);
						advance(ctx)!;
						expect(ctx, RBRACKET)!;
						ov_expr.overload_kind = consume(ctx, EQ)! ? OV_ELEMENT_SET : OV_ELEMENT_AT;
						expr.offset.end = ctx.peek(-1)!.end_pos();
						break;
					case NOT_EQUAL:
					case LESS_EQ:
					case GREATER:
					case GREATER_EQ:
						unexpected(ctx, "use '<' and '==', other comparison operations will be derived from those")!;
					case PLUSPLUS:
					case MINUSMINUS:
						unexpected(ctx, "Increment and decrement operators '++' and '--' cannot be directly overloaded, use '+=' and '-=' instead")!;
					case DOT:
						unexpected(ctx, "Cannot overload '.'")!;
					default:
						expr = parse_constant_expr(scope)!;
						break;
				}
				
				exprs.push(expr);
				if (!consume(ctx, COMMA)!) break;
			}
			attr_node.offset.end = ctx.current_pos();
			expect(ctx, RPAREN)!;
			attr_node.exprs = alloc::clone_slice(&ctx.ast.arena, exprs.array_view());
		}

		nodes.push(attr_node);

		if (flags.use_comma)
		{
			attr_node.offset.end = ctx.current_pos();
			consume(ctx, COMMA)!;
		}
	}

	if (parent_node) parent_node.flags.has_attributes = nodes.len() > 0;

	return alloc::clone_slice(&ctx.ast.arena, nodes.array_view());
}

<*
 ct_expand_decl ::= $expand '(' expr ')' attributes? ';'
*>
fn Node*? parse_expand_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, CT_EXPAND)!;
	CtExpandDecl* node = ctx.ast.alloc_node(CtExpandDecl, start_pos);
	expect(ctx, LPAREN)!;
	node.expr = parse_constant_expr(scope)!;
	expect(ctx, RPAREN)!;
	if (ctx.is(AT_IDENT))
	{
		node.attributes = parse_attributes(scope, node)!;
	}
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;
	return node;
}

<*
 struct_decl ::= "struct | union" TYPE_IDENT ("(" type ("," type)* ")")? attributes? "{" struct_body "}"
*>
fn Node*? parse_struct_union_decl(ContextScope scope, bool is_sub = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int start_pos  = ctx.current().pos;
	bool is_struct = ctx.is(STRUCT);
	if (is_struct)
	{
		expect(ctx, STRUCT)!;
	}
	else
	{
		expect(ctx, UNION)!;
	}
	StructDecl* node = ctx.ast.alloc_node(StructDecl, start_pos);
	node.is_union = !is_struct;

	do NAME_CHECK:
	{
		if (!is_sub)
		{
			Token t = @expect_some_else(ctx, { TYPE_IDENT } ; err)
			{
				ctx.error("Structs must have a 'Type' identifier");
				break NAME_CHECK;
			}!;

			node.name = ctx.ident(t);
			break NAME_CHECK;
		}

		if (ctx.is(IDENT))
		{
			node.name = ctx.ident(ctx.current());
			advance(ctx)!;
		}
	};

	node.interfaces = parse_interface_type_list(scope)!;
	node.generics = parse_generic_decl(scope)!;
	node.attributes = parse_attributes(scope, node, { .allow_type_ident = true })!;

	@expect_else_skip(ctx, LBRACE, { RBRACE } ; brace_err)
	{
		return brace_err;
	}!;

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
				sub_decl = parse_bitstruct_decl(scope, true)!;
			}
			else
			{
				sub_decl = parse_struct_union_decl(scope, true)!;
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
			struct_flags.is_inline = consume(ctx, INLINE)!;
			Node* field = parse_var_decl(scope.with_only_flags(struct_flags), null)!;
			fields.push(field);
		}
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	node.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return (Node*)node;
}

<*
 bitstruct_decl ::= "bitstruct" TYPE_IDENT ("(" type ("," type)* ")")? ":" type attributes? "{" bitstruct_body "}"
*>
fn Node*? parse_bitstruct_decl(ContextScope scope, bool is_nested = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, BITSTRUCT)!;
	StructDecl* node = ctx.ast.alloc_node(StructDecl, start_pos);

	if COND: (true)
	{
		if (is_nested && !ctx.is(IDENT)) break COND;
		Token t = @expect_some_else(ctx, { IDENT, TYPE_IDENT } ; err)
		{
			ctx.error("Bitstructs must have a name identifier");
			break COND;
		}!;

		node.name = ctx.ident(t);
	}

	node.interfaces = parse_interface_type_list(scope.with_only_flags({ .no_generics = true }))!;

	if (consume(ctx, COLON)!)
	{
		node.type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!;
		node.attributes = parse_attributes(scope, node)!;
	}

	@expect_else_skip(ctx, LBRACE, { RBRACE } ; brace_err)
	{
		return brace_err;
	}!;

	List{Node*} fields;
	fields.tinit();

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		int field_start  = ctx.current().pos;
		VarDecl* field_node = ctx.ast.alloc_node(VarDecl, field_start);
		field_node.var_kind = VAR_BITFIELD;

		if (ctx.is(CONTRACT)) field_node.contract.set(parse_contract_decl(scope)!);
		field_node.type = parse_type_expr(scope)!;
		field_node.attributes = parse_attributes(scope, field_node)!;

		if IF_IDENT: (true)
		{
			Token t = @expect_else_skip(ctx, IDENT, { COLON, EOS, RBRACE } ; name_err)
			{
				break IF_IDENT;
			}!;

			field_node.name = ctx.ident(t);
		}

		if (consume(ctx, COLON)!)
		{
			field_node.init_expr = parse_constant_expr(scope)!;
			if (consume(ctx, DOTDOT)!)
			{
				field_node.bit_end = parse_constant_expr(scope)!;
			}
		}
		expect(ctx, EOS)!;
		field_node.offset.end = ctx.current().pos;
		fields.push((Node*)field_node);
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;
	node.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return (Node*)node;
}

<*
 faultdef_decl ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
*>
fn Node*? parse_faultdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, FAULTDEF)!;
	FaultdefDecl* node = ctx.ast.alloc_node(FaultdefDecl, start_pos);

	List{Node*} faults;
	faults.tinit();

	while (!ctx.eof() && !ctx.is(EOS))
	{
		FaultDecl* fault_node = ctx.ast.alloc_node(FaultDecl, ctx.current().pos);
		if (ctx.is(AT_IDENT))
		{
			fault_node.contract.set(parse_contract_decl(scope)!);
		}

		if CHECK_IDENT: (true)
		{
			Token t = @expect_else(ctx, CONST_IDENT ; err)
			{
				break CHECK_IDENT;
			}!;

			fault_node.name = ctx.ident(t);
		}

		fault_node.attributes = parse_attributes(scope, node)!;
		fault_node.offset.end = ctx.previous_end_pos();

		node.offset.end = ctx.current_pos();
		if (!consume(ctx, COMMA)!) break;
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;

	node.faults = alloc::clone_slice(ctx.arena, faults.array_view());

	return (Node*)node;
}

<*
 interface_decl ::= 'interface' TYPE_IDENT ':' (TYPE_IDENT (',' TYPE_IDENT) interface_body
*>
fn Node*? parse_interface_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, INTERFACE)!;
	InterfaceDecl* node = ctx.ast.alloc_node(InterfaceDecl, start_pos);

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { EOS, AT_IDENT, COLON, LBRACE } ; err)
		{
			break CHECK_NAME;
		}!;

		node.name = ctx.ident(t);
	}

	List{Node*} list;
	list.tinit();

	if (consume(ctx, COLON)!)
	{
		do
		{
			list.push(parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!);
		} while (consume(ctx, COMMA)!);
	}

	node.interfaces = alloc::clone_slice(ctx.arena, list.array_view());
	list.clear();
	node.attributes = parse_attributes(scope, node)!;

	expect(ctx, LBRACE)!;

	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		Node* contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract_decl(scope)!;
		}
		Node* func_node = parse_fn_decl(scope.with_only_flags({ .is_interface = true }))!;
		FnDecl* func    = func_node.as(FnDecl);
		if (contract)
		{
			func.contract.set(contract);
		}
	}

	node.methods = alloc::clone_slice(ctx.arena, list.array_view());
	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	return (Node*)node;
}

<*
 attrdef_decl ::= "attrdef" AT_IDENT ("(" parameter_list? ")")? ("=" attribute_list)? ";"
*>
fn Node*? parse_attrdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, ATTRDEF)!;
	AttrdefDecl* node = ctx.ast.alloc_node(AttrdefDecl, start_pos);

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, AT_TYPE_IDENT, { EOS, EQ, LPAREN, RPAREN } ; err)
		{
			break CHECK_NAME;
		}!;

		node.name = ctx.ident(t);
	}

	if (ctx.is(LPAREN))
	{
		node.params = parse_parameter_list(scope)!;//, { .is_attrdef = true })!;
	}

	if (ctx.is(AT_IDENT))
	{
		node.defined_attributes = parse_attributes(scope, node)!;
	}

	if (consume(ctx, EOS)!)
	{
		return node;
	}

	expect(ctx, EQ)!;

	node.defined_attributes = parse_attributes(scope, node, { .use_comma = true })!;

	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;

	return (Node*)node;
}

<*
 enum_decl ::= "enum" TYPE_IDENT ("(" type ("," type)* ")")? (":" type? enum_param_list?)? attributes? "{" enum_body "}"

    constdef_decl ::= "constdef" TYPE_IDENT ("(" type ("," type)* ")")? (":" "inline"? type)? attributes? "{" constdef_body "}"
*>
fn Node*? parse_enum_constdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	expect(ctx, flags.is_constdef ? CONSTDEF : ENUM)!;

	EnumDecl* node = ctx.ast.alloc_node(EnumDecl, start_pos);

	if CHECK_IDENT: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { COLON, LBRACE, EOS } ; err)
		{
			break CHECK_IDENT;
		}!;

		node.name = ctx.ident(t);
	}

	node.interfaces = parse_interface_type_list(scope)!;

	// Optional backing type and/or associated value parameters: ":" "inline"? type? enum_param_list?
	if (consume(ctx, COLON)!)
	{
		node.is_inline_backing = consume(ctx, INLINE)!;

		if (!ctx.is(LPAREN))
		{
			node.backing_type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!;
		}

		if (consume(ctx, LPAREN)!)
		{
			List{Node*} assoc;
			assoc.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				VarDecl* param = ctx.ast.alloc_node(VarDecl, ctx.current().pos);

				param.type = parse_type_expr(scope)!;
				if (is_non_type_ident(ctx.current().kind))
				{
					param.name = ctx.ident(ctx.current());
					advance(ctx)!;
				}
				if (ctx.is(AT_IDENT))
				{
					parse_attributes(scope, param)!;
				}
				param.offset.end = ctx.current().pos;
				assoc.push((Node*)param);
				if (!consume(ctx, COMMA)!) break;
			}
			expect(ctx, RPAREN)!;
			node.assoc_params = alloc::clone_slice(ctx.arena, assoc.array_view());
		}
	}

	if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		node.attributes = parse_attributes(scope, node, { .allow_type_ident = true })!;
	}

	expect(ctx, LBRACE)!;

	List{Node*} variants;
	variants.init(tmem, 4);
	while ENUM_VARIANT: (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node* contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract_decl(scope)!;
		}
		if (!ctx.is(CONST_IDENT))
		{
			variants.push(unexpected(ctx, "Expected enum variant name")!);
			ctx.skip_until({ COMMA, RBRACE, CONTRACT, CONST_IDENT })!;
            consume(ctx, COMMA)!;
			continue;
		}

		VarDecl* variant = ctx.ast.alloc_node(VarDecl, ctx.current().pos);
		variant.var_kind = VAR_GLOBAL;
		variant.contract.set(contract);
		variant.flags.is_const = true;
		variant.name = ctx.ident(ctx.current());
		advance(ctx)!;

		// Optional per-variant attributes: @attr ...  (come before = and {})
		if (ctx.is(AT_IDENT))
		{
			variant.attributes = parse_attributes(scope, variant)!;
		}

		// Optional ordinal: "=" expr
		if (consume(ctx, EQ)!)
		{
			variant.init_expr = parse_expr(scope)!;
		}

		// Optional associated values: "{" expr ("," expr)* "}"
		if (ctx.is(LBRACE))
		{
			variant.assoc_values = parse_expr(scope)!;
		}

		variant.offset.end = ctx.current().pos;
		variants.push(variant);

		if (!consume(ctx, COMMA)!) break;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, RBRACE)!;

	node.variants = alloc::clone_slice(ctx.arena, variants.array_view());

	return (Node*)node;
}

<*
 generic_decl ::= '<' (type_expr | ident_expr)* '>'
 @return "null if no generics are present"
*>
fn Node*? parse_generic_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	if (!ctx.is(LESS))
	{
		return null;
	}
	if (ctx.is(GREATER))
	{
		unexpected(ctx, "At least one parameter is required")!;
		return null;
	}

	expect(ctx, LESS)!;

	int start_pos = ctx.current().pos;
	GenericDecl* node    = ctx.ast.alloc_node(GenericDecl, start_pos);
	List{Node*} params;
	params.tinit();
	while (!ctx.eof())
	{
		switch (ctx.current().kind)
		{
			case TYPE_IDENT:
			case CONST_IDENT:
				break;
			default:
				params.push(unexpected(ctx, "Expected either 'Type' or 'CONST_IDENT'")!);
				advance(ctx)!;
		}

		// so it only parses the prefix
		params.push(parse_expr(scope, HIGHEST)!);
		if (!consume(ctx, COMMA)!) break;
	}
	node.offset.end = ctx.current_pos();
	expect(ctx, GREATER)!;
	node.params = alloc::clone_slice(ctx.arena, params.array_view());
	return (Node*)node;
}
