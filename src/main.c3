module parser @if($feature(ANALYZER_CLI));
import utils::ast;
import std::io;
import analyzer::parser;
import analyzer::core;
import std::collections::maybe;
import std::collections::list;
import seali;

struct Cli @Command({ .name = "c3_parser", .help_on_empty = true })
{
	Maybe{Std} std @Seali(arg(subcommand));
	Maybe{String} file @Seali(arg(long, short, help = "Parse this file"));
	bool verbose @Seali(arg(short, long, default_value = false, help = "Verbose output"));
	bool json @Seali(arg(short, long, default_value = false, help = "Output as json"));
	bool no_invalid @Seali(arg(long, default_value = false, help = "Treat invalid node as an error"));
	bool no_dump @Seali(arg(long, default_value = false, help = "Don't dump the workspace"));
	bool quiet @Seali(arg(short, long, default_value = false, help = "Don't output anything"));
}

struct Std @Command({ .name = "std", .about = "Test parser against the std lib", .help_on_empty = true })
{
	String path @Seali(arg(help = "The std path"));
}

fn int main(String[] args) => @pool()
{
	Cli cli = seali::parse(Cli, args)!!;

	if (cli.verbose) log::set_priority_all(LogPriority.VERBOSE);

	if (cli.quiet) log::set_logger(&&(NullLogger) { });

	diagnostics::log_debug("Init...");
	diagnostics::log_debug("args: %s", args);

	AnalyzerContext* context = core::context_create(tmem);

	//if (try std = cli.std.get())
	//{
	//	test_std_lib(&ws, std.path)!!;
	//}
	if (try file_path = cli.file.get())
	{
		core::process_file(context, file_path);
	}
	
	return 0;
}
