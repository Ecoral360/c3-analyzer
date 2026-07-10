module analyzer::core;

import std::collections::list;
import std::collections::maybe;
import std::collections::map;

import analyzer::sema;

alias ModuleSection @if(!$feature(SEMA))= ModSection;
alias ModuleSection @if($feature(SEMA)) = SemaModSection;

alias Module @if(!$feature(SEMA)) = Mod;
alias Module @if($feature(SEMA)) = SemaMod;

ulong next_source_file_id = 1;
ulong next_section_id     = 1;
ulong next_module_id      = 1;

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

struct SourceFile
{
	String file_path;
	String source;
	LineMap line_map;
	List{ModuleSection*} sections;
	Ast* ast;
	ulong id;
}

struct ModSection
{
	List{Diagnostic} diagnostics;
	NodeArray nodes;
	SourceFile* source_file;
	Module* parent_module;
	Allocator allocator;
	ulong id;
}

fn void ModSection.init(&self, Module* mod, SourceFile* sf, Allocator alloc)
{
	self.id = next_section_id++;
	self.allocator = alloc;
	self.source_file = sf;
	self.parent_module = mod;
	self.diagnostics.init(alloc);
}

struct Mod
{
	String name;
	List{ModuleSection*} sections;
	ulong id;
	ulong version;
}

fn void Mod.init(&self, String name, Allocator allocator)
{
	self.name = name.copy(allocator);
	self.sections.init(allocator, 4);
	self.id = next_module_id++;
}

fn void Mod.free(&self, Allocator allocator)
{
	self.name.free(allocator);
	self.sections.free();
}

alias PathString = String;

fn void ModSection.free(&self)
{
	foreach (diag : self.diagnostics)
	{
		alloc::free(self.allocator, diag.message);
	}

	self.diagnostics.free();
}
