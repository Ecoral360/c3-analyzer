module analyzer::core;

import std::collections;

import analyzer::sema;

attrdef @UseSema   = @if($feature(SEMA));

struct SourceFile
{
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

struct AnalyzerContext
{
	HashMap{String, SourceFile*} files;
	HashMap{String, Module*} modules;
	TypeRegistry registry @UseSema;
	MethodRegistry methods @UseSema;
	SymbolTable symbols @UseSema;
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
	bool has_error;
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