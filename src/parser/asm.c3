module analyzer::parser;

import analyzer::core;

import std::collections::list;

fn Node*? parse_asm_block_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;
	expect(ctx, ASM)!;
	plog::debug("parse_macro");
	Node* node = ctx.ast.alloc_node(ASM_BLOCK_STMT, start_pos);

	ctx.skip_until({ RBRACE, EOF })!;
	advance(ctx)!;

	return node;
}
