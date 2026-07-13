module analyzer::parser;

import analyzer::core;

import std::collections::list;

<*
 @require scope.ctx.current.kind == ASM
*>
fn Node* parse_asm_block_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	Range start = ctx.current.range;
	advance(ctx);
	diagnostics::log_debug("parse_macro");
	AsmBlockStmt* node = ctx.ast.alloc_node(AsmBlockStmt, start);

	skip_until(ctx, { RBRACE, EOF });
	advance(ctx);

	return node;
}
