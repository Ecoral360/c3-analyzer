module analyzer::core;

import std::collections;

import analyzer::sema;
import analyzer::lexer;

struct SourceFile
{
	Lexer* lexer;
	String path;
	String content;
	Allocator allocator;
	Ast ast;
}

<*
 -`node_map`: a fast lookup table
 -`nodes`: all nodes in this module with order preserved
 -`module_decls`: a index table for fast lookup of all modules/sections in this module
*>
struct Module
{
	String name;
	HashMap{NodeID, Node*} node_map;
	List{Node*} nodes;
	List{ModuleDecl*} module_decls;
}

struct Lookup
{
	HashMap{String, Type*} types;
	Allocator alloc;
	Target target;
}

struct AnalyzerContext
{
	HashMap{String, SourceFile*} files;
	HashMap{String, Module*} modules;
	Lookup* lookup;
	Registry* registry;
	Allocator allocator;
	SourceFile* current_source_file;
	Target target;
}

struct ParseContext
{
	AnalyzerContext* context;
	SourceFile* sf;
	Ast* ast;
	Lexer* lexer;
	Allocator allocator;
	Node* contract;
	Token current;
	int pos;
	int error_count;
}

struct FunctionInfo
{
	FunctionInfo* next;
	String mod;
	Node* node;
}

struct MacroInfo
{
	MacroInfo* next;
	String mod;
	Node* node;
}

enum TypeModifierKind : char
{
	NONE,
	POINTER,
	SLICE,
	ARRAY,
	CONST,
}

struct ImportInfo
{
	String path;
	Node* node;
}

fn bool ImportInfo.eq(self, ImportInfo other) @operator(==)
{
	return self.path == other.path && self.node == other.node;
}

struct TypeInfo
{
	TypeInfo* next;
	String name;
	String mod;
	Node* node;
	Type* resolved;
}

<*
 What a binding is, which decides whether it survives a function boundary.
*>
enum BindingKind : char
{
	GLOBAL,   // declared at file scope
	RUNTIME,  // parameter, local, local constant, static local
}

struct VariableInfo
{
	String name;
	String mod;
	Node* node;
	BindingKind binding;
	Scope* scope; // the scope the binding was declared in
}

struct Registry
{
	HashMap{String, TypeInfo*} types;
	HashMap{String, FunctionInfo*} functions;
	HashMap{String, MacroInfo*} macros;
}

enum ResolveStatus : char
{
	UNRESOLVED,
	RESOLVING,
	RESOLVED
}

struct Type
{
	TypeKind kind;
	ResolveStatus status;
	uint size;
	String name;

	union data
	{
		Node* node;

		bitstruct builtin : uint
		{
			char bitsize        : 0..7;
			char bytesize       : 8..15;
			char abi_alignment  : 16..23;
			char pref_alignment : 24..31;
		}
	}
}

struct Target
{
	OsType os;
	ArchType arch;
	TargetLayout layout;
}

struct AlignData
{
	uint align;
	uint pref_align;
}

struct TargetLayout
{
    AlignData[BitSizes::len] integers;
    AlignData[BitSizes::len] floats;
}
