module analyzer::core::ast;

import std::collections::list;

struct Ident
{
	Range range;
	String text;
}