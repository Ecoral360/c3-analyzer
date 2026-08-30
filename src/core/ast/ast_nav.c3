module analyzer::core::ast;

import std::collections::list;


<*
 Get the node at a certain path

 @require self.statements.size > 0 || path.len == 0
 @return "The node at that location, or null if the path is empty"
 @return? NOT_FOUND
*>
fn Node*? Ast.node_at(&self, NodePath path)
{
	if (path.len == 0) return null;

	NodeID target = path[path.len - 1];

	foreach (node : self.nodes)
	{
		if (node.id == target) return node;
	}

	return NOT_FOUND~;
}
