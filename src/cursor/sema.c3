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

	log::info("Checking for symbol globally: %s", name);
	List{SymbolEntry} global_entries = ws.find_symbol_by_name(name);
	if (global_entries.len() <= 0) return {};
	return global_entries.get(0);
}

fn SymbolEntry resolve_chained_type(Workspace* ws, SemaScope* leaf, String[] path)
{
    if (path.len == 0) return {};
    
    SemaVar? root_var = leaf.find_variable(path[0]);
    if (catch root_var) return {};
	if (!root_var.def) return {};

    SymbolEntry current_entry = resolve_type_from_expr(ws, workspace::get_section_from_id(ws, (ulong)root_var.section_id), root_var.def);
    
    for (sz i = 1; i < path.len; i++)
    {
        String member_name = path[i];

        if (!current_entry.node || current_entry.node.kind != STRUCT_DECL) return {};
		
        Cursor c = { current_entry.node };
        Node* member_node = c.find_member_in_type(member_name);
        if (!member_node) return {};
        
        ModuleSection* member_section = workspace::get_section_from_id(ws, (ulong)current_entry.section_id); ;
        current_entry = resolve_type_from_expr(ws, member_section, member_node);
    }

    return current_entry;
}

fn SymbolEntry resolve_type_from_expr(Workspace* ws, ModuleSection* section, Node* node)
{
    Cursor c = { node };
	Node* type_expr = c.get_type();
    if (!type_expr) return {};

	c = { type_expr };
    String type_name = c.raw_type_identifier() ?? "";
    if (type_name.len == 0) return {};
    SymbolEntry entry = resolve_symbol(ws, section, type_name);
    return entry;
}

