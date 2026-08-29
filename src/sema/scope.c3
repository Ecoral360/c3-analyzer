module analyzer::sema::scope @feat(SEMA);

import analyzer::core;

<*
 @param is_barrier : "true for a function-like scope, which lookup does not climb out of"
*>
fn Scope* new(Allocator alloc, Range range, Scope* parent = null, bool is_barrier = false)
{
	Scope* scope = alloc::new(alloc, Scope);

	scope.parent = parent;
	scope.range = range;
	scope.is_barrier = is_barrier;
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


fn void add_variable(Scope* scope, Allocator alloc, String name, Node* node)
{
	VariableInfo* variable = alloc::new(alloc, VariableInfo);

	variable.name = name;
	variable.mod = name;
	variable.node = node;

	scope.variables.set(name, variable);
}

<*
 Look for a variable in this scope and the ones enclosing it, stopping at the
 first function-like scope: C3 lets a local shadow a global, and a lambda
 cannot see the locals of the function it is written in.
*>
fn bool has_variable(Scope* scope, String name)
{
	if (scope.variables.has_key(name))
	{
		return true;
	}

	if (scope.parent && !scope.is_barrier)
	{
		return has_variable(scope.parent, name);
	}

	return false;
}

<*
 Stops at a function-like scope, the same way 'has_variable' does.
*>
fn VariableInfo* get_variable(Scope* scope, String name)
{
	if (scope.variables.has_key(name))
	{
		return scope.variables.get(name)!!;
	}

	if (scope.parent && !scope.is_barrier)
	{
		return get_variable(scope.parent, name);
	}

	return null;
}

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
