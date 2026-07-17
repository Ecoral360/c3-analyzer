module analyzer::core;

import std::collections;

import analyzer::sema;
import analyzer::lexer;

attrdef @UseSema = @if($feature(SEMA));

struct SourceFile
{
	Lexer* lexer;
	String path;
	String content;
	Allocator allocator;
	Ast ast;
}

struct Module
{
	String name;
	HashMap{NodeID, Node*} nodes;
}

struct Lookup
{
	HashMap{String, Type*} types;
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

enum TypeModifierKind : char
{
	NONE,
	POINTER,
	SLICE,
	ARRAY,
	CONST,
}

struct TypeInfo
{
	TypeInfo* next;
	String name;
	String mod;
	Node* node;
	Type* resolved;
}

struct VariableInfo
{
	String name;
	String mod;
	Node* node;
}

struct Registry
{
	HashMap{String, TypeInfo*} types;
	HashMap{String, FunctionInfo*} functions;
}

struct Scope
{
	Scope* parent;
	Range range;
	List{Scope*} children;
	HashMap{String, FunctionInfo*} functions;
	HashMap{String, VariableInfo*} variables;
	HashMap{String, TypeInfo*} types;
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
	TargetOS os;
	TargetArch arch;
	TargetLayout layout;
}

enum TargetOS : char
{
	UNKNOWN,
	WIN32,
	LINUX,
	IOS,
	MACOS,
	TVOS,
	WATCHOS,
	NETBSD,
}

enum TargetArch : char
{
	UNKNOWN,
	X86,
	X86_64,
	ARM,
	AARCH64,
	RISCV32,
	RISCV64,
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
