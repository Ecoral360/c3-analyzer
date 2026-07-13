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

	$if $feature(ANALYZER_PRINT):
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

		io::eprintf(" %4s | %s\n", range.start.line + 1, line_str);

		sz padding = 4;
		io::eprintf(" %4s | ", "");
		for (sz i = math::max(0, range.start.line - 3); i < range.start.line; i++)
		{
			if (i < lines.len) 
			{
				io::eprintf("%d: %s\n", i + 1, lines[i]);
			}
		}
		io::eprintf("%s^%s\n", Ansi.RED, Ansi.RESET);
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
	diagnose(ctx, range, ERROR, fmt, ...$vaarg);
}


macro void log(LogPriority priority, String fmt, ...)
{
	$if $feature(ANALYZER_PRINT):
		std::core::log::call_log(priority, std::core::log::default_category, fmt, ...$vaarg);
	$endif
}

macro void log_debug(String fmt, ...) => log(DEBUG, fmt, ...$vaarg);
macro void log_info(String fmt, ...) => log(INFO, fmt, ...$vaarg);
macro void log_error(String fmt, ...) => log(ERROR, fmt, ...$vaarg);
macro void log_warn(String fmt, ...) => log(WARN, fmt, ...$vaarg);