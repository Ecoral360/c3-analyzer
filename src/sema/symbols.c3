module analyzer::sema @if($feature(SEMA));

import analyzer::core;

import analyzer::workspace;

struct SymbolEntry
{
	Node* node;
	<* `@if(expr)` *>
	Node* condition;
	String qualified_name;
	sz section_id;
}

fn SymbolEntry get_qualified_symbol(Workspace* ws, String target_fqn)
{
	sz? index = target_fqn.rindex_of("::");
	if (catch index) return {};

	String mod_name = target_fqn[0..index];
	String sym_name = target_fqn[index + 2..];

	Module* target_mod = ws.modules.get(mod_name) ?? null;
	if (target_mod && target_mod.symbols.has_key(sym_name))
	{
		return target_mod.symbols.get(sym_name)[0] ?? {};
	}

	return {};
}