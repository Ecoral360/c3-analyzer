module analyzer::core::ast;

import analyzer::core::plog;
import analyzer::core::string_pool;

import std::collections::list;
import std::collections::nullable;

const sz ARENA_PAGE_SIZE = 4096;

sz next_node_id = 1;

alias NodeArray = Node*[];
alias NullableNode = Nullable{Node};

typedef NodeID = uint;

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
	DynamicArenaAllocator arena;
	List{Node*} top_level_nodes;
	List{Node*} error_nodes;
}

fn void Ast.init(&self, Allocator backing_allocator = mem)
{
	self.arena.init(backing_allocator, ARENA_PAGE_SIZE);
	self.top_level_nodes.init(&self.arena, 32);
	self.error_nodes.init(&self.arena);
}

macro Node* Ast.error(&self, int start, int end = -1)
{
	Node* node = (Node*)self.alloc_node(Error, start, end);
	self.error_nodes.push(node);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return node;
}

macro Node* Ast.missing(&self, int start, int end = -1)
{
	Missing* node = self.alloc_node(Missing, start, end);
	self.error_nodes.push(node);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return (Node*)node;
}

fn sz Ast.next_node_idx(&self) => self.top_level_nodes.len();

fn void Ast.clear(&self)
{
	self.arena.reset();
	self.top_level_nodes = { };
	self.error_nodes = { };

	self.top_level_nodes.init(&self.arena, 32);
	self.error_nodes.init(&self.arena);
}

fn void Ast.free(&self)
{
	self.top_level_nodes.clear();
	self.error_nodes.clear();
	self.arena.free();
}

<*
 Allocates and initializes a strongly typed AST node inside the AST arena.
 @param start : "The starting token index/position"
*>
macro Ast.alloc_node(&self, $Type, int start, int end = -1)
{
	$Type* node = alloc::new(&self.arena, $Type);
	
	node.kind = NodeKind.$eval(@typename_to_constname($Type::name));
	node.offset.start = start;
	node.offset.end = end == -1 ? node.offset.start : end;
	
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
