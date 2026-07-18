module parser_tests;

import analyzer::core;
import analyzer::sema;

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
