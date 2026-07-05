module analyzer::core::ast;

import analyzer::core::string_pool;
import std::collections::list;

struct Ident
{
	ByteOffset range;
	StringID id;
}