module analyzer::sema @feat(SEMA);

import analyzer::core;
import analyzer::cursor;

import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;
import std::io::path;

struct SemaContext
{
	AnalyzerContext* context;
	Allocator allocator;
	SemaModuleContext* current_module;
	HashMap{String, List{SemaModuleContext*}} modules;

	// The '$for' or '$foreach' whose body is being analyzed, and the scope it
	// sits in. Its body is inlined once per iteration, so a runtime variable
	// declared straight in that scope would be declared again on the next one.
	Node* inlined_loop;
	Scope* inlined_loop_scope;
}

struct SemaModuleContext
{
	Module* mod;
	Range range;
	Scope* runtime_scope;
	Scope* comptime_scope;
	HashMap{String, ImportInfo} imports;
}

fn SemaContext* new(AnalyzerContext* context)
{
	SemaContext* ctx = alloc::new(context.allocator, SemaContext);

	ctx.context = context;
	ctx.allocator = context.allocator;
	ctx.modules.init(ctx.allocator);

	return ctx;
}

fn SemaModuleContext* SemaContext.set_current_module(&self, String name)
{
	Module* mod = self.context.modules.get(name) ?? null;
	if (!mod) return null;

	SemaModuleContext* sema_mod = alloc::new(self.allocator, SemaModuleContext);

	sema_mod.mod = mod;
	sema_mod.runtime_scope = scope::new(self.allocator, { }, null, MODULE);
	sema_mod.comptime_scope = scope::new(self.allocator, { }, null, MODULE);
	sema_mod.imports.init(self.allocator);

	// 'get' hands back a copy of the list header, so pushing to it would drop
	// the section on the floor - the map has to be updated through a reference.
	if (try sema_mods = self.modules.get_ref(name))
	{
		sema_mods.push(sema_mod);
	}
	else
	{
		List{SemaModuleContext*} sema_mods;
		sema_mods.init(self.allocator);
		sema_mods.push(sema_mod);

		self.modules.set(name, sema_mods);
	}

	self.current_module = sema_mod;
	return sema_mod;
}

<*
 Enter the section a module declaration opens.

 The import pass records one SemaModuleContext per section and hangs the
 imports off it, so a later pass has to find that same section back: starting a
 second one would leave the imports on one object and the scopes on another.
*>
fn SemaModuleContext* SemaContext.enter_module_section(&self, String name, Location start)
{
	if (try sections = self.modules.get_ref(name))
	{
		foreach (section : *sections)
		{
			if (section.range.start == start)
			{
				self.current_module = section;
				return section;
			}
		}
	}

	return self.set_current_module(name);
}

fn SemaModuleContext* set_default_module(SemaContext* ctx, SourceFile* sf) @local
{
	Path? path = path::tnew(sf.path);
	if (catch err = path)
	{
		diagnostics::log_error("Failed to infer module name: %s", err);
		return null;
	}
	return ctx.set_current_module(path.basename());
}

<*
 @require ctx.context != null
*>
fn void analyze_source_file(SemaContext* ctx, SourceFile* sf)
{
	ctx.context.current_source_file = sf;

	set_default_module(ctx, sf);
	// ctx.runtime_scope = scope::new(ctx.allocator, { }, null, FILE);
	// ctx.comptime_scope = scope::new(ctx.allocator, { }, null, FILE);

	run_module_feature_pass(ctx);
	run_import_pass(ctx);

	run_variable_pass(ctx);
}
