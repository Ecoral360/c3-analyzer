module analyzer::core::ast;

import std::collections::list;
import std::collections::nullable;

alias NodeArray = Node*[];
alias NullableNode = Nullable{Node};

typedef NodeID = inline ulong;

NodeID next_node_id = (NodeID)1;

bitstruct NodeFlags : ushort
{
	bool is_inline;
	bool is_static;
	bool is_extern;
	bool has_attributes;
	bool has_error;
}

struct Node
{
	NodeKind kind;
	Visibility visibility;
	NodeFlags flags;
	Range range;
	NodeID id;
}

<*
 @require self.kind == NodeKind.$eval(@str_constantcase($Type::name)) : "Invalid kind to cast"
*>
macro Node.as(&self, $Type) => ($Type*)self;

fn bool Node.is_valid(&self) @inline
{
	return self.kind != ERROR && !self.flags.has_error;
}

struct Ast
{
	Allocator allocator;
	List{Node*} nodes;
	List{Node*} statements;
}

macro Node* Ast.error(&self, Range range)
{
	Node* node = (Node*)self.alloc_node(Error, range);
	node.flags.has_error = true;
	self.nodes.push(node);
	return node;
}

<*
 Allocates and initializes a strongly typed AST node inside the AST arena.
 @param range : "Range of the node"
*>
macro Ast.alloc_node(&self, $Type, Range range)
{
	$Type* node = alloc::new(self.allocator, $Type);

	node.kind = NodeKind.$eval(@str_constantcase($Type::name));
	node.range = range;
	node.id = next_node_id++;
	self.nodes.push(node);

	return node;
}


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
