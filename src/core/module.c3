module analyzer::core::mod;

import analyzer::core::diagnostics;

import analyzer::lexer;
import analyzer::parser;
import analyzer::sema;

import std::io;

<*
 @param [&in] ctx
 @param [in] name
 @require name.len > 0
*>
fn Module* create(AnalyzerContext* ctx, String name)
{
	if (try Module* mod = ctx.modules.get(name))
	{
		return mod;
	}

	Module* mod = alloc::new(ctx.allocator, Module);

	diagnostics::log_debug("Created module: %s", name);

	mod.name = name;	
	mod.nodes.init(ctx.allocator);

	ctx.modules.set(name, mod);

	return mod;
}


<*
 @param [&in] ctx
 @param [&in] mod
*>
fn void free(AnalyzerContext* ctx, Module* mod)
{
	(void)ctx.modules.remove(mod.name);
	alloc::free(ctx.allocator, mod);
}
