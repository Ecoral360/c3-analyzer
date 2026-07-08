module main @if($feature(SEALI_DEV));
import seali;

enum LogLevel : (String name) {
  VERBOSE { "verbose" },
  DEBUG { "debug" },
  INFO { "information" },
  WARN { "warn" },
  ERROR { "error" },
}
struct EnumDesCli @Command({.name = "t"}) {
  LogLevel log_level_description @Seali(arg(long, help = "Log level", default_value = VERBOSE));
  LogLevel log_level_ordinal @Seali(arg(long, help = "Log level", enum_as = ORDINAL));
  LogLevel log_level_field @Seali(arg(long, help = "Log level", enum_as = name, default_value = WARN));
  String file_path @Seali(arg(long, help = "The file path"));
}


fn void main(String[] args) {
  EnumDesCli cli = seali::parse(EnumDesCli, args)!!;

}
