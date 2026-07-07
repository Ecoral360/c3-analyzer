module analyzer::core::ast;

import std::collections::list;

struct ErrorNode
{
	inline Node node;
	NodeArray inner;
}
