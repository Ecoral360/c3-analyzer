module analyzer::core;

import std::collections;

import analyzer::sema;

struct SourceFile
{
	String path;
	Allocator allocator;
	Ast ast;
	bool is_dirty;
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
	TypeRegistry registry;
	MethodRegistry methods;
	SymbolTable symbols;
	Allocator allocator;
}