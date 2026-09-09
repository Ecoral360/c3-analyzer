module parser_tests;

import analyzer::core;
import analyzer::sema;
import analyzer::lexer;
import analyzer::parser;

import std::io;
import std::collections::list;

macro AttributeDecl* @attr(self, int idx)
{
	return self.attributes[idx].as(AttributeDecl) @inline;
}

<*
 Count how many top-level nodes inside this specific Module match a given kind.
*>
fn int count_kind(Module* mod, NodeKind kind)
{
	int n = 0;

	foreach (node_ptr : mod.nodes)
	{
		if (node_ptr == null) continue;

		// Directly check the node's kind field
		if (node_ptr.kind == kind)
		{
			n++;
		}
	}
	return n;
}

int error_diag_count;
String last_error_message;
char[512] last_error_buffer;

<*
 Count ERROR diagnostics instead of printing them, so a test can assert that
 a source parses cleanly. 'context::process' only reports the errors raised
 through 'expect', which is why counting the diagnostics is the reliable check.
*>
fn void count_error_diags(SourceFile* file, Range range, DiagnosticLevel level, String message)
{
	if (level != DiagnosticLevel.ERROR) return;

	error_diag_count++;

	// The message is only valid for the length of the call, so keep a copy a
	// test can still read once processing is over.
	usz len = message.len < last_error_buffer.len ? message.len : last_error_buffer.len;

	for (usz i = 0; i < len; i++)
	{
		last_error_buffer[i] = message[i];
	}

	last_error_message = (String)last_error_buffer[:len];
}

<*
 Install the counting callback and reset the counter.
*>
fn void start_counting_diags()
{
	error_diag_count = 0;
	last_error_message = "";
	diagnostics::callback = &count_error_diags;
}

fn void stop_counting_diags()
{
	diagnostics::callback = null;
}

<*
 The single statement inside a case body.
*>
fn Node* case_body(Node* case_node)
{
	CaseStmt* cs = case_node.as(CaseStmt);
	CompoundStmt* body = cs.body.as(CompoundStmt);
	test::eq(body.statements.len, 1);
	return body.statements[0];
}

<*
 Parse a buffer and hand back the SourceFile, which 'context::process' frees
 before it returns. A test that needs the Ast itself - to ask the cursor about
 a location, say - has to drive the pipeline on its own.
*>
fn SourceFile* parse_source(AnalyzerContext* context, String source_code, String path = "test")
{
	Lexer* lex = lexer::new(context, source_code);
	SourceFile* sf = source_file::new(context, lex, path);

	context.current_source_file = sf;
	lexer::tokenize(lex);

	ParseContext* parse_ctx = parser::new(context);
	parser::parse(parse_ctx, sf);

	return sf;
}

<*
 Run the full pipeline the way 'context::process' does, but hand back the
 SemaContext it builds - the sections, scopes and imports a sema test wants to
 look at live there and are otherwise dropped when processing ends.
*>
fn SemaContext* analyze_source(AnalyzerContext* context, String source_code, String path = "test")
{
	SourceFile* sf = parse_source(context, source_code, path);

	registry::register(context, sf);

	SemaContext* sema_ctx = sema::new(context);
	sema::analyze_source_file(sema_ctx, sf);

	return sema_ctx;
}

<*
 Lex a buffer on its own and hand back every token, the trailing EOF included.
*>
fn Token[] lex_all(AnalyzerContext* context, String source_code)
{
	Lexer* lex = lexer::new(context, source_code);

	lexer::tokenize(lex);

	return lex.tokens.to_tarray();
}
