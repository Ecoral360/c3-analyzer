module analyzer::core::source_file;

import analyzer::lexer;
import analyzer::parser;
import analyzer::sema;

import std::io;

<*
 @param [&in] context : "The main context"
 @param [&in] lexer : "Lexer to parse with and get source from"
 @param [in] path : "The path the lexer points to"
 @param [in] alloc : "The allocator to use for the file's internal data (AST, etc.) Defaults to context.allocator"
 @return "SourceFile* using context.allocator or null if failed to read from specified path"
*>
fn SourceFile* create(AnalyzerContext* context, Lexer* lexer, String path, Allocator alloc = null)
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

fn void free(AnalyzerContext* context, SourceFile* sf)
{
	sf.path.free(context.allocator);
	sf.ast.nodes.free();
	sf.ast.statements.free();
	(void)context.files.remove(sf.path);
	alloc::free(context.allocator, sf);
}
