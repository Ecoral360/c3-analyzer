module seali_test;
import seali;
import std::io;
import std::collections::maybe;

// ── Structs ────────────────────────────────────────────────────────────────

struct StringLongCli @Command({.name = "t"}) {
    String name @Seali(arg(long, help = "name"));
}

struct StringShortAutoCli @Command({.name = "t"}) {
    String name @Seali(arg(short, help = "name"));
}

struct StringShortCustomCli @Command({.name = "t"}) {
    String name @Seali(arg(short = 'x', help = "name"));
}

struct UintCli @Command({.name = "t"}) {
    uint count @Seali(arg(long, help = "count"));
}

struct IntCli @Command({.name = "t"}) {
    int offset @Seali(arg(long, help = "offset"));
}

struct BoolLongCli @Command({.name = "t"}) {
    bool verbose @Seali(arg(long, default_value = false, help = "verbose"));
}

struct BoolShortCli @Command({.name = "t"}) {
    bool verbose @Seali(arg(short = 'V', default_value = false, help = "verbose"));
}

struct DefaultsCli @Command({.name = "t"}) {
    String output  @Seali(arg(long, default_value = "out.txt", help = "output file"));
    uint   threads @Seali(arg(long, default_value = 4, help = "threads"));
}

struct MaybeStringCli @Command({.name = "t"}) {
    Maybe{String} output @Seali(arg(long, help = "output"));
}

struct MaybeUintCli @Command({.name = "t"}) {
    Maybe{uint} count @Seali(arg(long, help = "count"));
}

struct PositionalCli @Command({.name = "t"}) {
    String input @Seali(arg(help = "input file"));
}

struct KebabCaseCli @Command({.name = "t", .rename_all = KEBAB_CASE}) {
    String input_file @Seali(arg(long, help = "input file"));
}

struct VerbatimCli @Command({.name = "t", .rename_all = VERBATIM}) {
    String input_file @Seali(arg(long, help = "input file"));
}

struct ShortAndLongCli @Command({.name = "t"}) {
    String name @Seali(arg(short, long, help = "name"));
}

struct CustomLongCli @Command({.name = "t"}) {
    String output @Seali(arg(long = "out", help = "output"));
}

struct SkipCli @Command({.name = "t"}) {
    String name     @Seali(arg(long, help = "name"));
    int    internal @Seali(arg(skip));
}

struct SubInstall @Command({.name = "install"}) {
    String name @Seali(arg(help = "lib name"));
}

struct SubFetch @Command({.name = "fetch"}) {
    String url @Seali(arg(long, help = "url"));
}

struct SubCli @Command({.name = "t"}) {
    Maybe{SubInstall} install @Seali(arg(subcommand));
    Maybe{SubFetch}   fetch   @Seali(arg(subcommand));
}

struct MultiCli @Command({.name = "t"}) {
    String name    @Seali(arg(short, long, help = "name"));
    uint   count   @Seali(arg(short, long, default_value = 1, help = "count"));
    bool   verbose @Seali(arg(short = 'V', long, default_value = false, help = "verbose"));
}

struct PosAndFlagCli @Command({.name = "t"}) {
    String flag       @Seali(arg(long, default_value = "default", help = "flag"));
    String positional @Seali(arg(help = "positional"));
}

struct ShortCustomAndLongCli @Command({.name = "t"}) {
    String output @Seali(arg(short = 'o', long = "out", help = "output"));
}

// ── String flags ───────────────────────────────────────────────────────────

fn void test_string_long_flag() @test {
    String[] args = {"prog", "--name", "Alice"};
    StringLongCli cli = seali::parse(StringLongCli, args)!!;
    assert(cli.name == "Alice");
}

fn void test_string_short_auto_flag() @test {
    String[] args = {"prog", "-n", "Bob"};
    StringShortAutoCli cli = seali::parse(StringShortAutoCli, args)!!;
    assert(cli.name == "Bob");
}

fn void test_string_short_custom_flag() @test {
    String[] args = {"prog", "-x", "Charlie"};
    StringShortCustomCli cli = seali::parse(StringShortCustomCli, args)!!;
    assert(cli.name == "Charlie");
}

// ── Numeric flags ──────────────────────────────────────────────────────────

fn void test_uint_flag() @test {
    String[] args = {"prog", "--count", "42"};
    UintCli cli = seali::parse(UintCli, args)!!;
    assert(cli.count == 42);
}

fn void test_uint_flag_zero() @test {
    String[] args = {"prog", "--count", "0"};
    UintCli cli = seali::parse(UintCli, args)!!;
    assert(cli.count == 0);
}

fn void test_uint_flag_large() @test {
    String[] args = {"prog", "--count", "65535"};
    UintCli cli = seali::parse(UintCli, args)!!;
    assert(cli.count == 65535);
}

fn void test_int_positive() @test {
    String[] args = {"prog", "--offset", "99"};
    IntCli cli = seali::parse(IntCli, args)!!;
    assert(cli.offset == 99);
}

// ── Bool flags ─────────────────────────────────────────────────────────────

fn void test_bool_long_flag_sets_true() @test {
    String[] args = {"prog", "--verbose"};
    BoolLongCli cli = seali::parse(BoolLongCli, args)!!;
    assert(cli.verbose == true);
}

fn void test_bool_long_flag_absent_uses_default() @test {
    String[] args = {"prog"};
    BoolLongCli cli = seali::parse(BoolLongCli, args)!!;
    assert(cli.verbose == false);
}

fn void test_bool_short_flag_sets_true() @test {
    String[] args = {"prog", "-V"};
    BoolShortCli cli = seali::parse(BoolShortCli, args)!!;
    assert(cli.verbose == true);
}

fn void test_bool_short_flag_absent_uses_default() @test {
    String[] args = {"prog"};
    BoolShortCli cli = seali::parse(BoolShortCli, args)!!;
    assert(cli.verbose == false);
}

// ── Default values ─────────────────────────────────────────────────────────

fn void test_all_defaults_applied() @test {
    String[] args = {"prog"};
    DefaultsCli cli = seali::parse(DefaultsCli, args)!!;
    assert(cli.output == "out.txt");
    assert(cli.threads == 4);
}

fn void test_all_defaults_overridden() @test {
    String[] args = {"prog", "--output", "custom.txt", "--threads", "8"};
    DefaultsCli cli = seali::parse(DefaultsCli, args)!!;
    assert(cli.output == "custom.txt");
    assert(cli.threads == 8);
}

fn void test_partial_defaults() @test {
    String[] args = {"prog", "--threads", "2"};
    DefaultsCli cli = seali::parse(DefaultsCli, args)!!;
    assert(cli.output == "out.txt");
    assert(cli.threads == 2);
}

// ── Maybe{T} fields ────────────────────────────────────────────────────────

fn void test_maybe_string_present() @test {
    String[] args = {"prog", "--output", "file.txt"};
    MaybeStringCli cli = seali::parse(MaybeStringCli, args)!!;
    assert((cli.output.get() ?? "") == "file.txt");
}

fn void test_maybe_string_absent() @test {
    String[] args = {"prog"};
    MaybeStringCli cli = seali::parse(MaybeStringCli, args)!!;
    assert((cli.output.get() ?? "ABSENT") == "ABSENT");
}

fn void test_maybe_uint_present() @test {
    String[] args = {"prog", "--count", "7"};
    MaybeUintCli cli = seali::parse(MaybeUintCli, args)!!;
    assert((cli.count.get() ?? 0) == 7);
}

fn void test_maybe_uint_absent() @test {
    String[] args = {"prog"};
    MaybeUintCli cli = seali::parse(MaybeUintCli, args)!!;
    assert((cli.count.get() ?? 999) == 999);
}

// ── Positional args ────────────────────────────────────────────────────────

fn void test_positional_arg() @test {
    String[] args = {"prog", "myfile.txt"};
    PositionalCli cli = seali::parse(PositionalCli, args)!!;
    assert(cli.input == "myfile.txt");
}

fn void test_positional_with_flag_before() @test {
    String[] args = {"prog", "--flag", "flagval", "posval"};
    PosAndFlagCli cli = seali::parse(PosAndFlagCli, args)!!;
    assert(cli.flag == "flagval");
    assert(cli.positional == "posval");
}

fn void test_positional_with_flag_after() @test {
    String[] args = {"prog", "posval", "--flag", "flagval"};
    PosAndFlagCli cli = seali::parse(PosAndFlagCli, args)!!;
    assert(cli.flag == "flagval");
    assert(cli.positional == "posval");
}

fn void test_positional_flag_uses_default() @test {
    String[] args = {"prog", "posval"};
    PosAndFlagCli cli = seali::parse(PosAndFlagCli, args)!!;
    assert(cli.flag == "default");
    assert(cli.positional == "posval");
}

// ── Case renaming ──────────────────────────────────────────────────────────

fn void test_kebab_case_underscore_to_dash() @test {
    String[] args = {"prog", "--input-file", "test.txt"};
    KebabCaseCli cli = seali::parse(KebabCaseCli, args)!!;
    assert(cli.input_file == "test.txt");
}

fn void test_verbatim_preserves_underscores() @test {
    String[] args = {"prog", "--input_file", "test.txt"};
    VerbatimCli cli = seali::parse(VerbatimCli, args)!!;
    assert(cli.input_file == "test.txt");
}

// ── Short + long flags ─────────────────────────────────────────────────────

fn void test_both_flags_used_via_long() @test {
    String[] args = {"prog", "--name", "Alice"};
    ShortAndLongCli cli = seali::parse(ShortAndLongCli, args)!!;
    assert(cli.name == "Alice");
}

fn void test_both_flags_used_via_long_eq() @test {
    String[] args = {"prog", "--name=Alice"};
    ShortAndLongCli cli = seali::parse(ShortAndLongCli, args)!!;
    assert(cli.name == "Alice");
}

fn void test_both_flags_used_via_short() @test {
    String[] args = {"prog", "-n", "Bob"};
    ShortAndLongCli cli = seali::parse(ShortAndLongCli, args)!!;
    assert(cli.name == "Bob");
}
fn void test_both_flags_used_via_short_eq() @test {
    String[] args = {"prog", "-n=Bob"};
    ShortAndLongCli cli = seali::parse(ShortAndLongCli, args)!!;
    assert(cli.name == "Bob");
}

fn void test_custom_short_and_long_via_short() @test {
    String[] args = {"prog", "-o", "result.txt"};
    ShortCustomAndLongCli cli = seali::parse(ShortCustomAndLongCli, args)!!;
    assert(cli.output == "result.txt");
}

fn void test_custom_short_and_long_via_long() @test {
    String[] args = {"prog", "--out", "result.txt"};
    ShortCustomAndLongCli cli = seali::parse(ShortCustomAndLongCli, args)!!;
    assert(cli.output == "result.txt");
}

fn void test_custom_long_name() @test {
    String[] args = {"prog", "--out", "result.txt"};
    CustomLongCli cli = seali::parse(CustomLongCli, args)!!;
    assert(cli.output == "result.txt");
}

// ── Skip ───────────────────────────────────────────────────────────────────

fn void test_skip_field_ignored_in_parse() @test {
    String[] args = {"prog", "--name", "Alice"};
    SkipCli cli = seali::parse(SkipCli, args)!!;
    assert(cli.name == "Alice");
    assert(cli.internal == 0);
}

// ── Subcommands ────────────────────────────────────────────────────────────

fn void test_subcommand_present_with_positional_arg() @test {
    String[] args = {"prog", "install", "mylib"};
    SubCli cli = seali::parse(SubCli, args)!!;
    SubInstall install = cli.install.get()!!;
    assert(install.name == "mylib");
}

fn void test_subcommand_present_with_flag_arg() @test {
    String[] args = {"prog", "fetch", "--url", "https://example.com"};
    SubCli cli = seali::parse(SubCli, args)!!;
    SubFetch f = cli.fetch.get()!!;
    assert(f.url == "https://example.com");
}

fn void test_subcommand_absent() @test {
    String[] args = {"prog"};
    SubCli cli = seali::parse(SubCli, args)!!;
    bool install_present = false;
    if (try cli.install.get()) { install_present = true; }
    assert(!install_present);
    bool fetch_present = false;
    if (try cli.fetch.get()) { fetch_present = true; }
    assert(!fetch_present);
}

fn void test_second_subcommand_absent_when_first_used() @test {
    String[] args = {"prog", "install", "lib"};
    SubCli cli = seali::parse(SubCli, args)!!;
    bool fetch_present = false;
    if (try cli.fetch.get()) { fetch_present = true; }
    assert(!fetch_present);
}

// ── Multi-flag commands ─────────────────────────────────────────────────────

fn void test_multi_all_flags_provided() @test {
    String[] args = {"prog", "--name", "World", "--count", "3", "-V"};
    MultiCli cli = seali::parse(MultiCli, args)!!;
    assert(cli.name == "World");
    assert(cli.count == 3);
    assert(cli.verbose == true);
}

fn void test_multi_only_required_flag_uses_defaults() @test {
    String[] args = {"prog", "--name", "World"};
    MultiCli cli = seali::parse(MultiCli, args)!!;
    assert(cli.name == "World");
    assert(cli.count == 1);
    assert(cli.verbose == false);
}

fn void test_multi_short_flags_combined_separately() @test {
    String[] args = {"prog", "-n", "World", "-c", "5"};
    MultiCli cli = seali::parse(MultiCli, args)!!;
    assert(cli.name == "World");
    assert(cli.count == 5);
    assert(cli.verbose == false);
}


enum LogLevel : (String name) {
  VERBOSE { "verbose" },
  DEBUG { "debug" },
  INFO { "information" },
  WARN { "warn" },
  ERROR { "error" },
}
struct EnumDesCli @Command({.name = "t"}) {
    LogLevel log_level @Seali(arg(long, help = "Log level"));
}

struct EnumOrdCli @Command({.name = "t"}) {
    LogLevel log_level @Seali(arg(long, enum_as = ORDINAL, help = "Log level"));
}

struct EnumLookupCli @Command({.name = "t"}) {
    LogLevel log_level @Seali(arg(long, enum_as = name, help = "Log level"));
}

fn void test_enum_description() @test {
    String[] args = {"prog", "--log-level", "info"};
    EnumDesCli cli = seali::parse(EnumDesCli, args)!!;
    assert(cli.log_level == INFO);
}

fn void test_enum_ordinal() @test {
    String[] args = {"prog", "--log-level", "2"};
    EnumOrdCli cli = seali::parse(EnumOrdCli, args)!!;
    assert(cli.log_level == INFO);
}

fn void test_enum_lookup() @test {
    String[] args = {"prog", "--log-level", "information"};
    EnumLookupCli cli = seali::parse(EnumLookupCli, args)!!;
    assert(cli.log_level == INFO);
}
