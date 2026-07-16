module analyzer::core::context;

import analyzer::core::diagnostics;
import analyzer::core::source_file;

import analyzer::lexer;
import analyzer::parser;
import analyzer::sema;

import std::io;

fn AnalyzerContext* create(Allocator alloc)
{
	AnalyzerContext* ctx = alloc::new(alloc, AnalyzerContext);

	ctx.allocator = alloc;
	ctx.files.init(alloc);
	ctx.modules.init(alloc);
	$if $feature(SEMA):
		ctx.lookup = lookup::create(alloc);
		ctx.registry = registry::create(alloc);
	$endif

	return ctx;
}

<*
 @require ctx != null
*>
fn void free(AnalyzerContext* ctx)
{
	ctx.files.free();
	ctx.modules.free();

	$if $feature(SEMA):
	$endif

	alloc::free(ctx.allocator, ctx);
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

	SourceFile* source = source_file::create(context, lexer, path);
	defer source_file::free(context, source);

	ParseContext* parse_ctx = parser::create(context);
	defer parser::free(context, parse_ctx);

	if (!parser::parse(parse_ctx, source))
	{
		return false;
	}

	foreach (SourceFile* sf : context.files.value_iter())
	{
		registry::register(context, sf);
	}

	return true;
}

<*
 @param [&in] context
 @require $Typeof(item) == POINTER : "item must be a pointer"
*>
macro void free_item(AnalyzerContext* context, item) 
{
	$if $defined(item.free):
		item.free(context.allocator);
	$else
		alloc::free(context.allocator, item);
	$endif
}

