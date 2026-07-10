module analyzer::core;

fn AnalyzerContext* context_create(Allocator alloc)
{
	AnalyzerContext* ctx = alloc::new(alloc, AnalyzerContext);

	ctx.allocator = alloc;
	ctx.files.init(alloc);
	ctx.methods.init(alloc);
	ctx.modules.init(alloc);
	ctx.registry.init(alloc);
	ctx.symbols.init(alloc);

	return ctx;
}

<*
 @require ctx != null
*>
fn void context_free(AnalyzerContext* ctx)
{
	ctx.files.free();
	ctx.methods.free();
	ctx.modules.free();
	ctx.registry.free();
	ctx.symbols.free();

	alloc::free(ctx.allocator, ctx);
}

<*
 @param [&in] ctx
 @param [in] name
 @require name.len > 0
*>
fn Module* module_create(AnalyzerContext* ctx, String name)
{
	if (try Module* mod = ctx.modules.get(name))
	{
		return mod;
	}

	Module* mod = alloc::new(ctx.allocator, Module);

	mod.name = name;	
	mod.nodes.init(ctx.allocator);

	ctx.modules.set(name, mod);

	return mod;
}

<*
 @param [&in] ctx
 @param [&in] mod
*>
fn void module_free(AnalyzerContext* ctx, Module* mod)
{
	(void)ctx.modules.remove(mod.name);
	alloc::free(ctx.allocator, mod);
}