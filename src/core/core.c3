module analyzer::core;

import analyzer::lexer;
import analyzer::parser;

import std::io;

fn AnalyzerContext* context_create(Allocator alloc)
{
	AnalyzerContext* ctx = alloc::new(alloc, AnalyzerContext);

	ctx.allocator = alloc;
	ctx.files.init(alloc);
	ctx.modules.init(alloc);
	$if $feature(SEMA):
		ctx.methods.init(alloc);
		ctx.registry.init(alloc);
		ctx.symbols.init(alloc);
	$endif

	return ctx;
}

<*
 @require ctx != null
*>
fn void context_free(AnalyzerContext* ctx)
{
	ctx.files.free();
	ctx.modules.free();

	$if $feature(SEMA):
		ctx.registry.free();
		ctx.methods.free();
		ctx.symbols.free();
	$endif

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
 @param [&in] lexer : "Lexer to parse with and get source from"
 @param [in] path : "The path the lexer points to"
 @param [in] alloc : "The allocator to use for the file's internal data (AST, etc.) Defaults to context.allocator"
 @return "SourceFile* using context.allocator or null if failed to read from specified path"
*>
fn SourceFile* source_file_create(AnalyzerContext* context, Lexer* lexer, String path, Allocator alloc = null)
{
	SourceFile* source_file = alloc::new(context.allocator, SourceFile);

	source_file.content = lexer.buffer;
	source_file.lexer = lexer;

	context.files.set(path, source_file);
	
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
*>
fn ParseContext* parse_context_create(AnalyzerContext* context)
{
	ParseContext* ctx = alloc::new(context.allocator, ParseContext);
	ctx.allocator = context.allocator;
	ctx.context = context;
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

fn bool process_file(AnalyzerContext* context, String path) => @pool()
{
	String? buffer = (String)file::load(tmem, path);
	if (catch err = buffer)
	{
		diagnostics::log_error("core::process_file - failed to load file (&s) %s", err, path);
		return false;
	}

	Lexer* lexer = lexer::create(context, buffer);
	defer lexer::free(context, lexer);
	lexer::tokenize(lexer);

	SourceFile* source = source_file_create(context, lexer, path);
	defer source_file_free(context, source);

	ParseContext* parse_ctx = parse_context_create(context);
	defer parse_context_free(context, parse_ctx);

	return parser::parse(parse_ctx, source);
}