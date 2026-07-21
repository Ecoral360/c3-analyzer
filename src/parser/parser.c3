module analyzer::parser;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::maybe;
import analyzer::core;
import analyzer::lexer;

<*
 @param [&in] context : "The main context"
*>
fn ParseContext* create(AnalyzerContext* context)
{
	ParseContext* ctx = alloc::new(context.allocator, ParseContext);
	ctx.allocator = context.allocator;
	ctx.context = context;
	return ctx;
}

fn void free(AnalyzerContext* main_ctx, ParseContext* ctx)
{
	alloc::free(main_ctx.allocator, ctx);
}


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

fn bool is_token_start_of_decl(TokenKind kind)
{
	switch (kind)
	{
		case DOCS_START:
		case INTERFACE:
		case MODULE:
		case IMPORT:
		case FAULTDEF:
		case FN:
		case MACRO:
		case ALIAS:
		case TYPEDEF:
		case ATTRDEF:
		case UNION:
		case STRUCT:
		case BITSTRUCT:
		case CONSTDEF:
		case ENUM:
		case CONST:
		case CT_EXPAND:
		case CT_ASSERT:
			return true;
		default:
			return false;
	}
}

fn bool is_token_start_of_stmt(TokenKind kind)
{
	switch (kind)
	{
		case LBRACE:
		case SWITCH:
		case CONTINUE:
		case BREAK:
		case NEXTCASE:
		case RETURN:
		case DEFER:
		case CT_SWITCH:
		case IF:
		case CT_IF:
		case FOR:
		case CT_FOR:
		case WHILE:
		case DO:
		case FOREACH:
		case FOREACH_R:
		case CT_FOREACH:
		case CT_ASSERT:
		case CT_ERROR:
		case CT_ECHO:
		case VAR:
		case CONST:
		case STATIC:
		case TLOCAL:
		case ASSERT:
		case CT_EXPAND:
		case ASM:
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
			return true;
		default:
			return false;
	}
}

fn void skip_until(ParseContext* ctx, TokenKind[] targets)
{
	int brace_depth = 0;
	while (!ctx.eof())
	{
		if (ctx.is(LBRACE)) brace_depth++;
		if (ctx.is(RBRACE)) brace_depth--;

		// Target check (only stop if not inside a nested structure)
		if (brace_depth <= 0)
		{
			foreach (TokenKind target : targets)
			{
				if (ctx.is(target)) return;
			}
		}

		if (brace_depth < 0) return;

		advance(ctx);
	}
}

enum SyncTarget
{
	DECLARATION,
	STATEMENT
}

fn void synchronize(ParseContext* ctx, SyncTarget target)
{
	while (!ctx.eof())
	{
		if (ctx.is(EOS))
		{
			return;
		}

		if (target == DECLARATION && is_token_start_of_decl(ctx.current.kind))
		{
			return;
		}

		if (target == STATEMENT && is_token_start_of_stmt(ctx.current.kind))
		{
			return;
		}

		advance(ctx);
	}
}

fn bool ParseContext.eof(&self) @inline => self.pos >= self.lexer.tokens.len() || self.current.is_eof();

fn bool ParseContext.is(&self, TokenKind kind)
{
	return self.peek(0).kind == kind;
}

fn Token ParseContext.peek(&self, int pos) @inline
{
	if (self.pos + pos >= (int)self.lexer.tokens.len())
	{
		return self.lexer.tokens.last()!!;
	}
	if (self.pos + pos < 0)
	{
		return self.lexer.tokens.first()!!;
	}
	return self.lexer.tokens[(sz)self.pos + pos];
}

<*
 make a ident from token
 Note: Does not advance
*>
fn Ident* ParseContext.ident(&self, Token t) @inline
{
	Ident* ident = alloc::new(self.allocator, Ident);
	*ident = {
		.range = t.range,
		.text = t.value.copy(self.allocator)
	};

	return ident;
}

fn Ident* ParseContext.ident_string(&self, String str) @inline
{
	Ident* ident = alloc::new(self.allocator, Ident);
	*ident = {
		.text = str.copy(self.allocator)
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
		diagnostics::log_debug("parser::advance() : eof");
	}

	ctx.pos += len;

	if (ctx.pos >= ctx.lexer.tokens.len())
	{
		ctx.pos = (int)ctx.lexer.tokens.len() - 1;
	}

	ctx.current = ctx.lexer.tokens[ctx.pos];
}

<*
 @param [&in] ctx
 @param [&inout] node : "Node to flag with error"
 @param [&inout] ctx : "The kind to expect"
*>
macro Token expect(ParseContext* ctx, Node* node, TokenKind kind)
{
	if (ctx.is(kind))
	{
		advance(ctx);
		return ctx.peek(-1);
	}

	diagnostics::error(ctx.context, ctx.current.range,
		"Expected '%s' got '%s'", kind.description, ctx.current.kind.description);
	$if $feature(ANALYZER_PRINT):
		diagnostics::log_error("Happened here.");
	$endif
	node.flags.has_error = true;
	ctx.error_count++;
	return {
		.kind = ERROR,
		.range = ctx.current.range,
		.value = "<error>"
	};
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

<*
 Parse specified source file
 expects tokens to be ready, a call to lexer.tokenize()
 will return false if the last token is not a EOF token

 @param [&inout] ctx
 @param [&in] source_file
 @require ctx.allocator != null
 @require source_file.lexer != null
 @require source_file.lexer.tokens.len() > 0
 @return "true if succeeded"
*>
fn bool parse(ParseContext* ctx, SourceFile* source_file) => @pool()
{
	ctx.lexer = source_file.lexer;
	ctx.ast = &source_file.ast;
	ctx.context.current_source_file = source_file;

	if (ctx.lexer.tokens.last()!!.kind != EOF)
	{
		diagnostics::log_error(
			"The last token in the lexer has to be a EOF token. Got: %s",
			ctx.lexer.tokens.last()!!.kind.description);
		return false;
	}

	ctx.current = ctx.lexer.tokens[0];

	while (!ctx.eof())
	{
		int pos = ctx.pos;
		Node* node = parse_top_level_statement(ctx);
		if (ctx.pos == pos)
		{
			diagnostics::error(ctx.context, ctx.current.range, "Parser failed to advance in parse_top_level_statement. Returning!");
			break;
		}
		ctx.ast.statements.push(node);
		if (ctx.contract && node.kind != CONTRACT_DECL)
		{
			attach_contract(ctx, node, ctx.contract);
			ctx.contract = null;
		}
	}

	return ctx.error_count == 0;
}

fn Node* parse_top_level_statement(ParseContext* ctx)
{
	diagnostics::log_debug("parse_top_level_statement: %s", ctx.current.value);

	Node* node;
	ContextScope scope = {
		.ctx = ctx
	};

	// TODO: Remove this shitshow xD
	while (true)
	{
		Token t = ctx.current;

		if (t.kind == EXTERN)
		{
			if (scope.flags.is_extern)
			{
				diagnostics::error(ctx.context, t.range, "Duplicate 'extern' modifier");
			}
			scope.flags.is_extern = true;
		}
		else if (t.kind == TLOCAL)
		{
			if (scope.flags.is_thread_local)
			{
				diagnostics::error(ctx.context, t.range, "Duplicate 'tlocal' modifier");
			}
			scope.flags.is_thread_local = true;
		}
		else if (t.kind == INLINE)
		{
			if (scope.flags.is_inline)
			{
				diagnostics::error(ctx.context, t.range, "Duplicate 'inline' modifier");
			}
			scope.flags.is_inline = true;
		}
		else
		{
			break;
		}

		advance(ctx);
	}

	if (is_type(ctx) || ctx.is(IDENT))
	{
		node = parse_var_decl(scope, null);
		return node;;
	}

	switch (ctx.current.kind)
	{
		case DOCS_START:
			if (ctx.contract)
			{
				diagnostics::error(ctx.context, ctx.current.range, "There are more than one doc comment in a row, that is not allowed.");
				ctx.ast.error(ctx.current.range);
			}
			node = parse_contract_decl(scope);
			ctx.contract = node;
		case INTERFACE:
			node = parse_interface_decl(scope);
		case MODULE:
			node = parse_module_decl(scope);
		case IMPORT:
			node = parse_import_decl(scope);
		case FAULTDEF:
			node = parse_faultdef_decl(scope);
		case FN:
			node = parse_fn_decl(scope);
		case MACRO:
			node = parse_macro_decl(scope);
		case ALIAS:
			node = parse_alias_decl(scope);
		case TYPEDEF:
			node = parse_typedef_decl(scope);
		case ATTRDEF:
			node = parse_attrdef_decl(scope);
		case UNION:
		case STRUCT:
			node = parse_struct_union_decl(scope);
		case BITSTRUCT:
			node = parse_bitstruct_decl(scope);
		case CONSTDEF:
			node = parse_enum_constdef_decl(scope.with_flags({ .is_constdef = true }));
		case ENUM:
			node = parse_enum_constdef_decl(scope);
		case CONST:
			advance(ctx);
			node = parse_var_decl(scope.with_flags({ .is_const = true }), null);
		case CT_EXPAND:
			node = parse_expand_decl(scope);
		case CT_ASSERT:
			Range start = ctx.peek(0).range;
			Node* stmt = parse_ct_assert_stmt(scope);
			node = (Node*)ctx.ast.alloc_node(CtAssertDecl, start);
			node.range.end = ctx.peek(-1).range.end;
			CtAssertDecl* ctassert = node.as(CtAssertDecl);
			ctassert.stmt = stmt;
		default:
			synchronize(ctx, DECLARATION);
			break;
	}

	return node;
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

fn void error_node(ParseContext* ctx, Node* node)
{
	node.flags.has_error = true;
}
