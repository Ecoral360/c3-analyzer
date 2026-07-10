module analyzer::sema @if($feature(SEMA));

import analyzer::core;

import analyzer::workspace @norecurse;
import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;

faultdef NOT_FOUND;

struct SemaContext
{
	ModuleSection* section;
	Workspace* ws;
	Allocator allocator;
}

struct SemaMod
{
	inline Mod mod;
	DynamicArenaAllocator arena;
	HashMap{String, List{SymbolEntry}} symbols;
	Registry registry;
}

fn void SemaMod.init(&self, String name, GlobalTypeRegistry* registry, Allocator backing_allocator)
{
	Mod.init(self, name, backing_allocator);

	self.arena.init(backing_allocator, 4096);
	self.symbols.init(backing_allocator);
	self.registry.init(&self.arena);
}

fn void SemaMod.free(&self, Allocator allocator)
{
	Mod.free(self, allocator);

	self.symbols.free();
	self.registry.free();
	self.arena.free();
}

struct SemaModSection
{
	inline ModSection section;
	List{String} resolved_imports;
	SemaScope scope;
}

fn void SemaModSection.init(&self, Module* mod, SourceFile* sf, Allocator alloc)
{
	ModSection.init(self, mod, sf, alloc);

	self.resolved_imports.init(&mod.arena);
}

fn void SemaModSection.free(&self)
{
	ModSection.free(self);
}

struct SemaVar
{
	Node* def;
	ByteOffset lifetime;
	sz section_id;
}

<*
 - `parent`: can be null
 - `children`: list of all children defined in this scope
*>
struct SemaScope
{
	SemaScope* parent;
	ByteOffset range;
	List{SemaScope*} children;
	// Only used for LOOKUP (Shadowing/Visibility)
	HashMap{String, SemaVar} variables;
}

fn SemaVar? SemaScope.find_variable(&self, String name)
{
	SemaScope* current = self;

	while (current != null)
	{
		if (try var_ = current.variables.get(name))
		{
			return var_;
		}

		current = current.parent;
	}

	return NOT_FOUND~;
}

<*
 Recursively finds the deepest child scope at the given offset.
*>
fn SemaScope* find_deepest_scope(SemaScope* current, int offset)
{
	foreach (child : current.children)
	{
		if (offset >= child.range.start && offset <= child.range.end)
		{
			return find_deepest_scope(child, offset);
		}
	}
	
	// If no children contain the offset, the current scope is the leaf.
	return current;
}

fn List{SemaVar} collect_visible_symbols(Allocator allocator, SemaScope* leaf_scope, int cursor_offset)
{
	List{SemaVar} visible_symbols; visible_symbols.init(allocator);
	HashSet{String} seen_names; seen_names.tinit();

	SemaScope* current = leaf_scope;
	
	while (current != null)
	{
		current.variables.@each(; name, var_)
		{
			if (!seen_names.contains(name))
			{
				bool in_range = (cursor_offset >= var_.lifetime.start && cursor_offset <= var_.lifetime.end);

				if (in_range)
				{
					visible_symbols.push(var_);
					seen_names.add(name);
				}
			}
		};
		current = current.parent;
	}

	return visible_symbols;
}

fn Node* lookup_symbol(SemaContext* ctx, Node* path, Ident* name)
{
    // Qualified Lookup (e.g., "pkg::mod::Name")
    if (path != null)
    {
        Module* target_mod = resolve_module_path(ctx, path);
        if (!target_mod) return null;
        return target_mod.symbol_table.get(name);
    }

    if (Node* found = ctx.current_scope.get(name)) 
    {
        return found;
    }

    // B. Check the current module's exported symbols
    if (Node* found = ctx.current_module.symbol_table.get(name))
    {
        return found;
    }

    foreach (imp : ctx.current_module.imports)
    {
        if (Node* found = imp.mod.symbol_table.get(name))
        {
            return found;
        }
    }

    return null;
}