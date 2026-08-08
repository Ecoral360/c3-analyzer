module analyzer::core::diagnostics;

import std::io;
import std::math;

alias DiagnosticsCallback = fn void(SourceFile* file, Range range, DiagnosticLevel level, String message);

DiagnosticsCallback callback;

enum DiagnosticLevel : char
{
	NOTE,
	INFO,
	WARN,
	ERROR,
}

<*
 @param [&in] ctx
*>
fn void diagnose(
	AnalyzerContext* ctx,
	Range range,
	DiagnosticLevel level,
	String fmt,
	args...) => @pool()
{
	SourceFile* sf = ctx.current_source_file;

	if (callback)
	{
		callback(sf, range, level, string::format(ctx.allocator, fmt, ...args));
	}

	$if $feat(ANALYZER_PRINT):
		String[] lines = sf.content.tsplit("\n");
		String line_str = lines[range.start.line != 0 ? range.start.line - 1 : 0];

		Ansi color;
		switch (level)
		{
			case NOTE:  color = Ansi.BRIGHT_BLUE; break;
			case INFO:  color = Ansi.GREEN;       break;
			case WARN:  color = Ansi.BG_YELLOW;   break;
			case ERROR: color = Ansi.RED;         break;
		}

 		io::eprintf("%s:%s:%s: %s%s%s:%s ", sf.path, range.start.line + 1, range.start.column + 1, color, Ansi.BOLD, level.description, Ansi.RESET);
		io::eprintf(fmt, ...args);
		io::eprintn("");
		sz start_ctx = math::max(0, range.start.line - 3);
		for (sz i = start_ctx; i <= range.start.line; i++)
		{
			if (i < lines.len) 
			{
				io::eprintf(" %4d | %s\n", i + 1, lines[i]);
				
				// If this is the line with the error, print the carets
				if (i == range.start.line)
				{
					// Gutter is " %4d | " -> 1 + 4 + 3 = 8 chars
					sz gutter_width = 8;
					
					for (sz j = 0; j < gutter_width + range.start.column; j++) 
					{
						io::eprint(" ");
					}

					io::eprint(Ansi.RED);
					sz caret_len = (range.end.line == range.start.line) ? (sz)(range.end.column - range.start.column) : 1;
					for (sz j = 0; j < caret_len; j++) 
					{
						io::eprint("^");
					}
					io::eprintn(Ansi.RESET);
				}
			}
		}
	$endif
}

macro void note(AnalyzerContext* ctx, Range range, String fmt, ...)
{
	diagnose(ctx, range, NOTE, fmt, ...$vaarg);
}

macro void info(AnalyzerContext* ctx, Range range, String fmt, ...)
{
	diagnose(ctx, range, INFO, fmt, ...$vaarg);
}

macro void warn(AnalyzerContext* ctx, Range range, String fmt, ...)
{
	diagnose(ctx, range, WARN, fmt, ...$vaarg);
}

macro void error(AnalyzerContext* ctx, Range range, String fmt, ...)
{
	$if $feat(ANALYZER_CLI):
	log_error("Error happened here");
	$endif
	diagnose(ctx, range, ERROR, fmt, ...$vaarg);
}


macro void log(LogPriority priority, String fmt, ...)
{
	$if $feat(ANALYZER_PRINT):
		std::core::log::call_log(priority, std::core::log::default_category, fmt, ...$vaarg);
	$endif
}

macro void log_debug(String fmt, ...) => log(DEBUG, fmt, ...$vaarg);
macro void log_info(String fmt, ...) => log(INFO, fmt, ...$vaarg);
macro void log_error(String fmt, ...) => log(ERROR, fmt, ...$vaarg);
macro void log_warn(String fmt, ...) => log(WARN, fmt, ...$vaarg);
