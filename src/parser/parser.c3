module analyzer::parser;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::maybe;
import analyzer::core;
import analyzer::lexer;

faultdef
	UNKNOWN, 
	UNEXPECTED_EOS, 
	MODULE_HEADER_FAILED, 
	CONTRACT_NOT_ALLOWED, 
	INVALID_PATH, 
	NOT_A_PATH, 
	PATH_TOO_LONG, 
	EXPECTED_EXPRESSION, 
	UNEXPECTED_TOKEN, 
	OVERFLOW_PARSING,
	EOT;

struct ContextScope
{
	ParseContext* ctx;
	ParseFlags flags;
}

fn ContextScope ContextScope.with_flags(&self, ParseFlags flags)
{
	return { 
		.ctx = self.ctx, 
		.flags = self.flags | flags 
	};
}

fn ContextScope ContextScope.with_only_flags(&self, ParseFlags flags)
{
	return { 
		.ctx = self.ctx, 
		.flags = flags 
	};
}

fn void? ParseContext.skip_until(ParseContext* ctx, TokenKind[] targets)
{
	while (!ctx.eof())
	{
		TokenKind current = ctx.current.kind;

		if (current == EOF) return;

		foreach (t : targets)
		{
			if (current == t) return;
		}

		advance(ctx)!;
	}
}

<*
 synchronize the top level/recover top level
 @param [&inout] ctx
*>
fn void? synchronize(ParseContext* ctx)
{
	int brace_depth = 0;

	while (!ctx.eof())
	{
		Token t      = ctx.current;
		Location loc = ctx.line_map.resolve((sz)t.pos);

		// Track depth to ensure we aren't inside a body
		if (t.kind == LBRACE) brace_depth++;
		if (t.kind == RBRACE)
		{
			brace_depth = (brace_depth > 0) ? brace_depth - 1 : 0;
		}

		if (brace_depth <= 0 && loc.column == 0)
		{
			switch (t.kind)
			{
				case CONTRACT:
				case MODULE:
				case IMPORT:
				case ALIAS:
				case TYPEDEF:
				case FN:
				case MACRO:
				case STRUCT:
				case CONST:
				case ENUM:
				case EXTERN:
					return;
				default:
					break;
			}
		}

		if (brace_depth <= 0 && t.kind == EOS)
		{
			advance(ctx)!;
			return;
		}

		advance(ctx)!;
	}
}

fn bool ParseContext.eof(&self) @inline => self.pos >= self.tokens.len || self.current.is_eof();

fn bool ParseContext.is(&self, TokenKind kind)
{
	return self.peek(0).kind == kind;
}

fn Token ParseContext.peek(&self, int pos) @inline
{
	if (self.pos + pos >= self.lexer.tokens.len()) {
		return self.lexer.tokens.last()!!;
	}
	if (self.pos + pos < 0) {
		return self.lexer.tokens.first()!!;
	}
	return self.tokens[(sz)self.pos + pos];
}

<*
 make a ident from token
 Note: Does not advance
*>
fn Ident* ParseContext.ident(&self, Token t) @inline
{
	Ident* ident = alloc::new(self.arena, Ident);
	*ident = {
		.range = t.range,
		.text = self.token_text(t).copy(self.arena)
	};

	return ident;
}

fn Ident* ParseContext.ident_string(&self, String str) @inline
{
	Ident* ident = alloc::new(self.arena, Ident);
	*ident = { 
		.text = str.copy(self.arena)
	};
	return ident;
}

<*
 @param [&inout] ctx
*>
fn void advance(ParseContext* ctx, int len = 1)
{
	if (ctx.eof())
	{
		diagnostics::log_debug("analyzer::advance() : eof");
	}

	ctx.pos += len;

	if (ctx.pos >= ctx.tokens.len) 
	{
		ctx.pos = ctx.tokens.len - 1;
	}

	ctx.current = ctx.lexer.tokens[ctx.pos];
}

<*
 a macro just so that it logs where it happened
 @param [&inout] ctx
*>
macro @expect_else(ParseContext* ctx, TokenKind kind; @body(err))
{
	if (!ctx.is(kind))
	{
		ctx.error("Expected '%s' got '%s'", kind.description, ctx.current.kind.description);
		$if $feature(PARSER_LIB):
			diagnostics::log_error("Error happened here");
		$endif
		@body(ctx.ast.missing(ctx.current.pos));

		return ctx.current;
	}
	else
	{
		advance(ctx)!;
		return ctx.peek(-1);
	}
}

<*
 @param [&inout] ctx
*>
macro @expect_some_else(ParseContext* ctx, TokenKind[] kind; @body(err))
{
	foreach (k : kind)
	{
		if (ctx.is(k))
		{
			advance(ctx)!;
			return ctx.peek(-1);
		}
	}

	ctx.error("Expected any of '%s' got '%s'", kind, ctx.current.kind.description);
	$if $feature(PARSER_LIB):
		diagnostics::log_error("Error happened here");
	$endif
	@body(ctx.ast.missing(ctx.current.pos));
	return ctx.current;
}

<*
 a helper function that expect else skips
 @param [&inout] ctx
*>
macro @expect_else_skip(ParseContext* ctx, TokenKind kind, TokenKind[] targets; @body(err))
{
	return @expect_else(ctx, kind ; err)
	{
		ctx.skip_until(targets)!;
		err.offset.end = ctx.current.pos;
		@body(err);
	};
}

<*
 a macro just so that it logs where it happened
 @param [&inout] ctx
*>
macro Token expect(ParseContext* ctx, TokenKind kind) @maydiscard
{
	if (!ctx.is(kind))
	{
		ctx.error("Expected '%s' got '%s'", kind.description, ctx.current.kind.description);
		$if $feature(PARSER_CLI):
			diagnostics::log_error("Error happened here");
		$endif
		ctx.ast.missing(ctx.current.pos);
		return ctx.current;
	}
	else
	{
		advance(ctx)!;
		return ctx.peek(-1);
	}
}

<*

*>
macro Node*? unexpected(ParseContext* ctx, String fmt, ...) @maydiscard
{
	ctx.error(fmt, ...$vaarg);
	$if $feature(PARSER_CLI):
		diagnostics::log_error("Error happened here");
	$endif
	return ctx.ast.missing(ctx.current.pos);
}

macro Node*? unexpected_at(ParseContext* ctx, Token t, String fmt, ...) @maydiscard
{
	ctx.error_at(t, fmt, ...$vaarg);
	$if $feature(PARSER_CLI):
		diagnostics::log_error("Error happened here");
	$endif
	return ctx.ast.missing(ctx.current.pos);
}

<*
 @param [&inout] ctx
 @param kind : "type to consume"
*>
fn bool consume(ParseContext* ctx, TokenKind kind)
{
	if (ctx.is(kind))
	{
		advance(ctx);
		return true;
	}

	return false;
}

fn String? path_to_module_name(String path)
{
	String base_name = path.file_tbasename()!;
	return base_name.strip_suffix(".c3");
}

<*
 Appends the nodes to the provided Modules Ast
 @param [&inout] ctx
 @require ctx.allocator != null
 @require ctx.lexer != null
 @require ctx.lexer.tokens.len() > 0
 @return "true if succeeded"
*>
fn bool parse(ParseContext* ctx) => @pool()
{
	if (ctx.lexer.tokens.last()!!.kind != EOF)
	{
		diagnostics::log_error(
			"The last token in the lexer has to be a EOF token. Got: %s",
			ctx.lexer.tokens.last()!!.kind.description);
		return;
	}
	
	while (!ctx.eof())
	{
		if (catch err = parse_top_level(ctx))
		{
			diagnostics::log_error("Got error: %s", err);

			int before = ctx.pos;
			synchronize(ctx)!;
			if (ctx.pos == before && !ctx.eof())
			{
				advance(ctx);
			}
		}
	}

	return !ctx.has_error;
}

fn void add_node(ParseContext* ctx, Node* node) @local
{
	ctx.ast.statements.push(node);
	if (ctx.contract && node.kind != CONTRACT_DECL)
	{
		attach_contract(ctx, node, ctx.contract);
		ctx.contract = null;
	}
}

fn void? parse_top_level(ParseContext* ctx)
{
	diagnostics::log_debug("parse_top_level: %s", ctx.token_text(ctx.current));

	Node* node;
	ContextScope scope = {
		.ctx = ctx
	};

	// the individual parse functions will check that the modifiers are used appropiately
	while (true)
	{
		Token t = ctx.current;

		if (t.kind == EXTERN)
		{
			if (scope.flags.is_extern) ctx.error("Duplicate 'extern' modifier");
			scope.flags.is_extern = true;
		}
		else if (t.kind == TLOCAL)
		{
			if (scope.flags.is_thread_local) ctx.error("Duplicate 'tlocal' modifier");
			scope.flags.is_thread_local = true;
		}
		else if (t.kind == INLINE)
		{
			if (scope.flags.is_inline) ctx.error("Duplicate 'inline' modifier");
			scope.flags.is_inline = true;
		}
		else
		{
			break;
		}

		advance(ctx)!;
	}

	if (is_type(ctx) || ctx.is(IDENT))
	{
		node = parse_var_decl(scope, null)!;
		add_node(ctx, node);
		return;
	}

	switch (ctx.current.kind)
	{
		case CONTRACT:
			if (ctx.contract)
			{
				ctx.error("There are more than one doc comment in a row, that is not allowed.");
				ctx.ast.error(ctx.current.pos);
			}
			node = parse_contract_decl(scope)!;
			ctx.contract = node;
		case INTERFACE:
			node = parse_interface_decl(scope)!;
		case MODULE:
			node = parse_module_decl(scope)!;
		case IMPORT:
			node = parse_import_decl(scope)!;
		case FAULTDEF:
			node = parse_faultdef_decl(scope)!;
		case FN:
			node = parse_fn_decl(scope)!;
		case MACRO:
			node = parse_macro_decl(scope)!;
		case ALIAS:
			node = parse_alias_decl(scope)!;
		case TYPEDEF:
			node = parse_typedef_decl(scope)!;
		case ATTRDEF:
			node = parse_attrdef_decl(scope)!;
		case UNION:
		case STRUCT:
			node = parse_struct_union_decl(scope)!;
		case BITSTRUCT:
			node = parse_bitstruct_decl(scope)!;
		case CONSTDEF:
			node = parse_enum_constdef_decl(scope.with_flags({ .is_constdef = true }))!;
		case ENUM:
			node = parse_enum_constdef_decl(scope)!;
		case CONST:
			advance(ctx)!;
			node = parse_var_decl(scope.with_flags({ .is_const = true }), null)!;
		case CT_EXPAND:
			node = parse_expand_decl(scope)!;
		case CT_ASSERT:
			int start_pos = ctx.peek(0).pos;
			Node* stmt = parse_ct_assert_stmt(scope)!;
			node = (Node*)ctx.ast.alloc_node(CtAssertDecl, start_pos);
			node.offset.end = ctx.peek(0).pos;
			CtAssertDecl* ctassert = node.as(CtAssertDecl);
			ctassert.stmt = stmt;
		default:
			ctx.error("Couldn't find any matching top level declaration: \"%s\" %s", ctx.token_text(ctx.current), string::from_struct(tmem, ctx.current));
			return UNEXPECTED_TOKEN~;
	}

	add_node(ctx, node);
}

<*
 @param [&in] ctx
 @param [&inout] node
 @param [&in] contract
*>
fn void attach_contract(ParseContext* ctx, Node* node, Node* contract)
{
	switch (node.kind)
	{
		case MODULE_DECL:
			ModuleDecl* mod = node.as(ModuleDecl);
			mod.contract.set(contract);
		case FN_DECL:
			FnDecl* func = node.as(FnDecl);
			func.contract.set(contract);
		case FAULTDEF_DECL:
			FaultdefDecl* fd = node.as(FaultdefDecl);
			fd.contract.set(contract);
		case VAR_DECL:
			VarDecl* vd = node.as(VarDecl);
			vd.contract.set(contract);
		default:
			break;
	}
}
