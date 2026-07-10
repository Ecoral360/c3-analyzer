module analyzer::core::ast;

import analyzer::core::plog;
import analyzer::core::string_pool;

import std::collections::list;
import std::collections::nullable;

alias NodeArray = Node*[];
alias NullableNode = Nullable{Node};

typedef NodeID = inline ulong;

NodeID next_node_id = 1;

bitstruct NodeFlags : ushort
{
	bool is_const;
	bool is_inline;
	bool is_static;
	bool is_extern;
	bool has_attributes;
}

struct Node
{
	NodeKind kind;
	Visibility visibility;
	NodeFlags flags;
	ByteOffset offset;
	NodeID id;
}

<*
 @require self.kind == NodeKind.$eval(@typename_to_constname($Type::name)) : "Invalid kind to cast"
*>
macro Node.as(&self, $Type) => ($Type*)self;

fn bool Node.is_valid(&self) @inline
{
	return self.kind != ERROR && self.kind != MISSING; 
}

struct Ast
{
	Allocator allocator;
	List{Node*} nodes;
}

macro Node* Ast.error(&self, int start, int end = -1)
{
	Node* node = (Node*)self.alloc_node(Error, start, end);
	self.nodes.push(node);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return node;
}

macro Node* Ast.missing(&self, int start, int end = -1)
{
	Missing* node = self.alloc_node(Missing, start, end);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return (Node*)node;
}

<*
 Allocates and initializes a strongly typed AST node inside the AST arena.
 @param start : "The starting token index/position"
*>
macro Ast.alloc_node(&self, $Type, int start, int end = -1)
{
	$Type* node = alloc::new(self.allocator, $Type);
	
	node.kind = NodeKind.$eval(@typename_to_constname($Type::name));
	node.offset.start = start;
	node.offset.end = end == -1 ? node.offset.start : end;
	node.id = next_node_id++;
	self.nodes.push(node);

	return node;
}

macro String @typename_to_constname(String $typename) @const
{
	var $name = "";
	$foreach $i, $c : $typename:
		$if $i != 0 &&& $c >= 'A' &&& $c <= 'Z':
			$name +++= "_";
		$endif
		$name +++= @str_upper("" +++ $c);
	$endforeach

	return $name;
}
