module analyzer::sema::scope @feat(SEMA);

import analyzer::core;
import std::collections;

<*
 Where a scope sits, which decides what a lookup climbing out of it can see.
*>
enum ScopeKind : char
{
	FILE,     // globals and file level constants / variables
	FUNCTION, // fn, macro, lambda, attrdef: a boundary for runtime bindings
	BLOCK,    // compound statement, loop, non-compound if body
}

struct Scope
{
	Scope* parent;
	ScopeKind kind;
	Range range;
	List{Scope*} children;
	HashMap{String, FunctionInfo*} functions;
	HashMap{String, VariableInfo*} variables;
	HashMap{String, TypeInfo*} types;
}

fn Scope* new(Allocator alloc, Range range, Scope* parent = null, ScopeKind kind = BLOCK)
{
	Scope* scope = alloc::new(alloc, Scope);

	scope.parent = parent;
	scope.range = range;
	scope.kind = kind;
	scope.children.init(alloc);
	scope.functions.init(alloc);
	scope.variables.init(alloc);
	scope.types.init(alloc);

	return scope;
}

fn void free(Scope* scope)
{
	if (!scope) return;

	foreach (child : scope.children)
	{
		free(child);
	}
	scope.children.free();

	scope.functions.free();
	scope.variables.free();
	scope.types.free();
}


fn void add_variable(Scope* scope, Allocator alloc, String name, Node* node, BindingKind binding = RUNTIME)
{
	VariableInfo* variable = alloc::new(alloc, VariableInfo);

	variable.name = name;
	variable.mod = name;
	variable.node = node;
	variable.binding = binding;
	variable.scope = scope;

	scope.variables.set(name, variable);
}

<*
 Find 'name' as it is seen from this scope.

 A lookup climbs outwards, and a FUNCTION scope filters what it carries with
 it rather than stopping it: past that boundary the runtime bindings of the
 enclosing function are out of view, while globals and compile-time bindings
 stay visible. A binding hidden that way is not an answer and not the end of
 the search either - an outer binding of the same name can still be the one in
 view, which is why a filtered hit keeps climbing.
*>
fn VariableInfo* resolve(Scope* scope, String name)
{
	bool crossed_function;

	for (Scope* current = scope; current != null; current = current.parent)
	{
		if (current.variables.has_key(name))
		{
			VariableInfo* info = current.variables.get(name)!!;

			if (!crossed_function || info.binding != RUNTIME)
			{
				return info;
			}
		}

		if (current.kind == FUNCTION) crossed_function = true;
	}

	return null;
}

fn bool has_variable(Scope* scope, String name) => resolve(scope, name) != null;

fn VariableInfo* get_variable(Scope* scope, String name) => resolve(scope, name);

fn FunctionInfo* add_function(Scope* scope, Allocator alloc, String name, String mod, Node* node)
{
	FunctionInfo* function = alloc::new(alloc, FunctionInfo);

	function.mod = mod;
	function.node = node;

	scope.functions.set(name, function);

	return function;
}

fn bool has_function(Scope* scope, String name)
{
	if (scope.functions.has_key(name))
	{
		return true;
	}

	if (scope.parent)
	{
		return has_function(scope.parent, name);
	}

	return false;
}

fn FunctionInfo* get_function(Scope* scope, String name)
{
	if (scope.functions.has_key(name))
	{
		return scope.functions.get(name)!!;
	}

	if (scope.parent)
	{
		return get_function(scope.parent, name);
	}

	return null;
}
