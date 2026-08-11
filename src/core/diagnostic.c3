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

		int line_num_width = 4;
		sz max_line = (sz)range.start.line + 1;
		int digits = 0;
		while (max_line > 0)
		{
			digits++;
			max_line /= 10;
		}
		if (digits > line_num_width) line_num_width = digits;

		sz start_ctx = range.start.line > 3 ? (sz)range.start.line - 3 : 0;

		for (sz i = start_ctx; i <= range.start.line; i++)
		{
			if (i < lines.len)
			{
				String line = lines[i];
				if (line.len > 0 && line[line.len - 1] == '\r')
				{
					line = line[0 .. line.len - 1];
				}

				// replaced \t with just 4 spaces, i couldnt get it working

				io::eprintf("%*d | ", (int)line_num_width, (int)(i + 1));
				for (sz j = 0; j < line.len; j++)
				{
					if (line[j] == '\t')
					{
						io::eprint("    ");
					}
					else
					{
						io::eprintf("%c", line[j]);
					}
				}
				io::eprintn("");

				// If this is the line with the error, print the carets
				if (i == range.start.line)
				{
					sz gutter_width = (sz)line_num_width + 3;

					for (sz j = 0; j < gutter_width; j++)
					{
						io::eprint(" ");
					}

					sz max_col = math::min((sz)range.start.column, line.len);
					for (sz j = 0; j < max_col; j++)
					{
						if (line[j] == '\t')
						{
							io::eprint("    ");
						}
						else
						{
							io::eprint(" ");
						}
					}

					io::eprint(Ansi.RED);
					sz caret_len = 1;
					if (range.end.line == range.start.line && range.end.column > range.start.column)
					{
						caret_len = (sz)range.end.column - (sz)range.start.column;
					}
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
