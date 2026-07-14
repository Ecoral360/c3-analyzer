module analyzer::sema::registry;

import analyzer::core;
import std::collections;
import std::io;

fn Registry* create(Allocator alloc)
{
	Registry* registry = alloc::new(alloc, Registry);

	registry.functions.init(alloc);
	registry.types.init(alloc);

	return registry;
}

fn void register(AnalyzerContext* context, SourceFile* sf) => @pool()
{
	Module* current_mod;

	foreach (Node* statement : sf.ast.statements)
	{
		if (!statement) continue;
		if (statement.kind == CONTRACT_DECL) continue;

		if (statement.kind == MODULE_DECL)
		{
			ModuleDecl* mod_decl = statement.as(ModuleDecl);
			PathExpr* path = mod_decl.path.as(PathExpr);
			current_mod = core::module_create(context, path.path.text);
			continue; 
		}

		if (current_mod == null)
		{
			Path? path = path::tnew(sf.path);
			if (catch err = path)
			{
				diagnostics::log_error("Failed to infer module name: %s", err);
				return;
			}
			current_mod = core::module_create(context, path.basename());
		}

		register_and_dispatch(context, current_mod, statement);
	}
}

fn void register_and_dispatch(AnalyzerContext* context, Module* mod, Node* node)
{
	mod.nodes.set(node.id, node);

	switch (node.kind)
	{
		case STRUCT_DECL:
		case ENUM_DECL:
		case TYPEDEF_DECL:
			register_type(context, mod, node);
			break;
		case FN_DECL:
			register_function(context, mod, node);
			break;
		default:
			break;
	}
}

fn void register_type(AnalyzerContext* context, Module* mod, Node* node)	
{
	Ident* name;
	switch (node.kind)
	{
		case STRUCT_DECL:
		{
			StructDecl* decl = node.as(StructDecl);
			name = decl.name;
		}
		case ENUM_DECL:
		{
			EnumDecl* decl = node.as(EnumDecl);
			name = decl.name;
		}
		case TYPEDEF_DECL:
		{
			TypedefDecl* decl = node.as(TypedefDecl);
			name = decl.name;
		}
		case ALIAS_DECL:
		{
			AliasDecl* decl = node.as(AliasDecl);
			name = decl.name;
		}
		case VAR_DECL:
		{
			VarDecl* decl = node.as(VarDecl);
			name = decl.name;
		}
		default:
			return;
	}

	if (!name)
	{
		diagnostics::log_error("registry::register_type - name is null");
		return;
	}

	String qname = string::format(context.allocator, "%s::%s", mod.name, name.text);

	TypeInfo* type_info = alloc::new(context.allocator, TypeInfo);
	type_info.mod = mod.name;
	type_info.node = node;

	TypeInfo* existing_head = context.registry.types.get(qname) ?? null;
	type_info.next = existing_head;

	diagnostics::log_debug("[Registry]: registered type: %s", qname);

	context.registry.types.set(qname, type_info);
}

fn void register_function(AnalyzerContext* context, Module* mod, Node* node)
{
	FnDecl* decl = node.as(FnDecl);
	if (!decl.name)
	{
		diagnostics::log_error("registry::register_function - function name is null");
		return;
	}

	String qname = string::format(context.allocator, "%s::%s", mod.name, decl.name.text);

	FunctionInfo* function_info = alloc::new(context.allocator, FunctionInfo);
	function_info.mod = mod.name;
	function_info.node = node;

	FunctionInfo* existing_head = context.registry.functions.get(qname) ?? null;
	function_info.next = existing_head;

	diagnostics::log_debug("[Registry]: registered fn: %s", qname);

	context.registry.functions.set(qname, function_info);
}