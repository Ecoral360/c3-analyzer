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

struct TypeInfo
{
	String mod;
	Node* node;
}

struct VariableInfo
{
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
	HashMap{String, FunctionInfo*} functions;
	HashMap{String, VariableInfo*} variables;
	HashMap{String, TypeInfo*} types;
}

struct Type 
{
	TypeKind kind;
	uint size;
	String name;

	union data
	{
		Type* pointer_base;
		Node* decl;

		struct array
		{
			Type* base;
			ulong len;
		}

		struct func
		{
			Node* decl;
		}

		bitstruct builtin : uint
		{
			char bitsize        : 0..7;
			char bytesize       : 8..15;
			char abi_alignment  : 16..23;
			char pref_alignment : 24..31;
		}
	}
}