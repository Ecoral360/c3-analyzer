module analyzer::cursor @if($feature(SEMA));

import analyzer::workspace;
import analyzer::core;
import analyzer::sema;

import std::collections::list;

import std::io;


fn SymbolEntry resolve_symbol(Workspace* ws, ModuleSection* section, String name)
{
	do LOCAL:
	{
		List{SymbolEntry}*? local_entries = ws.lookup_in_module(section.parent_module.name, name);
		if (catch local_entries) break LOCAL;
		if (!local_entries) break LOCAL;
		if (local_entries.len() <= 0) break LOCAL;
		return local_entries.get(0);
	};
	
	foreach (imp : section.resolved_imports)
	{
		log::info("Checking for symbol = %s, in import = %s", name, imp);
		List{SymbolEntry}*? entries = ws.lookup_in_module(imp, name);
		if (catch entries) continue;
		if (!entries) continue;
		if (entries.len() <= 0) continue;
		return entries.get(0);
	}
	
	List{SymbolEntry} global_entries = ws.find_symbol_by_name(name);
	if (global_entries.len() <= 0) return {};
	return global_entries.get(0);
}

fn Node* resolve_chained_type(Workspace* ws, ModuleSection* section, List{String} path)
{
	SymbolEntry root_entry = resolve_symbol(ws, section, path[0]);
	if (!root_entry.node) return null;

	Node* current_node = root_entry.node;

	for (sz i = 1; i < path.len(); i++)
	{
		String member_name = path[i];
		Cursor c = { current_node };
		current_node = c.find_member_in_type(member_name);
		if (current_node) break;
	}

	return current_node;
}
