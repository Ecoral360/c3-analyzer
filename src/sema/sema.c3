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
	HashMap{String, SemaModuleContext*} modules;
}

struct SemaModuleContext
{
	Module* mod;
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
	if (try sema_mod = self.modules.get(name))
	{
		self.current_module = sema_mod;
		return sema_mod;
	}

	Module* mod = self.context.modules.get(name) ?? null;
	if (!mod) return null;

	SemaModuleContext* sema_mod = alloc::new(self.allocator, SemaModuleContext);

	sema_mod.mod = mod;
	sema_mod.runtime_scope = scope::new(self.allocator, { }, null, MODULE);
	sema_mod.comptime_scope = scope::new(self.allocator, { }, null, MODULE);
	sema_mod.imports.init(self.allocator);

	self.modules.set(name, sema_mod);
	self.current_module = sema_mod;
	return sema_mod;
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

	run_import_pass(ctx);

	run_variable_pass(ctx);
}
