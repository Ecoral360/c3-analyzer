module analyzer::core::context;

import analyzer::core::diagnostics;
import analyzer::core::source_file;
import analyzer::core::arch;
import analyzer::core::os;

import analyzer::lexer;
import analyzer::parser;
import analyzer::sema;

import std::io;

<*
 If target.os or target.arch is `UNKNOWN` it will be inferred
*>
fn AnalyzerContext* new(Allocator alloc, Target target = {})
{
	AnalyzerContext* ctx = alloc::new(alloc, AnalyzerContext);

	ctx.allocator = alloc;
	ctx.files.init(alloc);
	ctx.modules.init(alloc);
	ctx.target = target;

	if (target.arch == UNKNOWN)
	{
		target.arch = arch::current();
	}

	if (target.os == UNKNOWN)
	{
		target.os = os::current();
	}

	ctx.target.layout = arch::get_platform_layout(target.os, target.arch);

	$if $feat(SEMA):
		ctx.lookup = lookup::new(ctx, alloc);
		ctx.registry = registry::new(alloc);
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

	$if $feat(SEMA):
		// Both are created in `new` from ctx.allocator. A consumer that
		// swapped in its own pair is expected to null these first, so both
		// frees tolerate a null argument.
		registry::free(ctx.allocator, ctx.registry);
		lookup::free(ctx.lookup);
	$endif

	alloc::free(ctx.allocator, ctx);
}

<*
 process from a buffer
 @param path : "uri/path to the file or 'virtual' file"
 @require buffer.len > 0
*>
fn bool process(AnalyzerContext* context, String buffer, String path) => @pool()
{
	Lexer* lexer = lexer::new(context, buffer);
	defer lexer::free(context, lexer);

	// new the SourceFile before tokenizing: the lexer reports its
	// diagnostics against context.current_source_file, so anything it
	// finds is lost if that is still unset.
	SourceFile* source = source_file::new(context, lexer, path);
	defer source_file::free(context, source);
	context.current_source_file = source;

	lexer::tokenize(lexer);

	ParseContext* parse_ctx = parser::new(context);
	defer parser::free(context, parse_ctx);

	bool success = true;

	if (!parser::parse(parse_ctx, source))
	{
		success = false;
	}

	foreach (SourceFile* sf : context.files.value_iter())
	{
		registry::register(context, sf);
	}

	SemaContext* sema_ctx = sema::new(context);

	foreach (SourceFile* sf : context.files.value_iter())
	{
	    sema::analyze_source_file(sema_ctx, sf);
	}

	return success;
}

fn bool process_file(AnalyzerContext* context, String path) => @pool()
{
	String? buffer = (String)file::load(tmem, path);
	if (catch err = buffer)
	{
		diagnostics::log_error("core::process_file - failed to load file (&s) %s", err, path);
		return false;
	}

	return process(context, buffer, path);
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
