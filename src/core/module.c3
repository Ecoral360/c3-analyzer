module analyzer::core::mod;

import analyzer::core::diagnostics;
import analyzer::core::ast;

import analyzer::lexer;
import analyzer::parser;
import analyzer::sema;

import std::io;

<*
 @param [&in] ctx
 @param [in] name
 @require name.len > 0
*>
fn Module* create(AnalyzerContext* ctx, String name)
{
	if (try Module* mod = ctx.modules.get(name))
	{
		return mod;
	}

	Module* mod = alloc::new(ctx.allocator, Module);

	diagnostics::log_debug("Created module: %s", name);

	mod.name = name;	
	mod.nodes.init(ctx.allocator);
	mod.module_decls.init(ctx.allocator);
	mod.node_map.init(ctx.allocator);

	ctx.modules.set(name, mod);

	return mod;
}

fn void add_node(Module* mod, Node* node)
{
	mod.nodes.push(node);
	mod.node_map.set(node.id, node);

	if (node.kind == MODULE_DECL)
	{
		mod.module_decls.push(node.as(ModuleDecl));
	}
}

<*
 @param [&in] mod
 @param [in] local_name : "The name to format with"
 @return "e.g. foo::local"
*>
fn String get_qualified_name(Allocator alloc, Module* mod, String local_name)
{
	return string::format(alloc, "%s::%s", mod.name, local_name);
}

<*
 @param [&in] ctx
 @param [&in] mod
*>
fn void free(AnalyzerContext* ctx, Module* mod)
{
	(void)ctx.modules.remove(mod.name);
	alloc::free(ctx.allocator, mod);
}
