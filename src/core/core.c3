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
 @param [&in] context : "The main context"
 @param [in] alloc : "The allocator to use for the file's internal data (AST, etc.) Defaults to context.allocator"
 @return "SourceFile* using context.allocator or null if failed to read from specified path"
*>
fn SourceFile* source_file_create(AnalyzerContext* context, String path, Allocator alloc = null)
{
	String? content = (String)file::load(context.allocator, path);
	if (catch err = content)
	{
		diagnostics::log_error("Failed to read file: %s", path);
		return null;
	}

	SourceFile* source_file = alloc::new(context.allocator, SourceFile);

	context.files.set(path, source_file);
	
	source_file.content = content;
	source_file.allocator = alloc ? alloc : context.allocator;
	source_file.ast.allocator = source_file.allocator;
	source_file.ast.nodes.init(source_file.allocator);
	source_file.ast.statements.init(source_file.allocator);
	source_file.path = path;
	
	return source_file;
}

fn void source_file_free(AnalyzerContext* context, SourceFile* sf)
{
	sf.path.free(context.allocator);
	sf.ast.nodes.free();
	sf.ast.statements.free();
	(void)context.files.remove(sf.path);
	alloc::free(context.allocator, sf);
}

<*
 @param [&in] context : "The main context"
 @param [&in] sf
*>
fn ParseContext* parse_context_create(AnalyzerContext* context, SourceFile* sf)
{
	ParseContext* ctx = alloc::new(context.allocator, ParseContext);

	ctx.allocator = sf.allocator;
	ctx.sf = sf;
	ctx.ast = &sf.ast;

	return ctx;
}

fn void parse_context_free(AnalyzerContext* main_ctx, ParseContext* ctx)
{
	alloc::free(main_ctx.allocator, ctx);
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

<*
 @param [&in] context
 @require $Typeof(item) == POINTER : "item must be a pointer"
*>
macro void free(AnalyzerContext* context, item) 
{
	$if $defined(item.free):
		item.free(context.allocator);
	$else
		alloc::free(context.allocator, item);
	$endif
}

fn AnalyzerContext* process_file(Allocator alloc, String path)
{
	AnalyzerContext* main_ctx = context_create(alloc);
	Lexer* lexer = lexer::create(main_ctx);
	defer lexer::free(main_ctx, lexer);
	SourceFile* source = source_file_create(main_ctx, path, alloc);
	ParseContext* parse_ctx = parse_context_create(main_ctx, source);

	parser::parse(main_ctx);

	parse_context_free(main_ctx, parse_ctx);
	
}