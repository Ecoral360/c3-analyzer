module analyzer::sema::scope @if($feature(SEMA));

import analyzer::core;

fn Scope* create(Allocator alloc, Scope* parent = null)
{
	Scope* scope = alloc::new(alloc, Scope);

	scope.parent = parent;
	scope.functions.init(alloc);
	scope.variables.init(alloc);
	scope.types.init(alloc);

	return scope;
}

fn void free(Scope* scope) 
{
	if (!scope) return;

	free(scope.parent);

	scope.functions.free();
	scope.variables.free();
	scope.types.free();
}


fn void add_variable(Scope* scope, Allocator alloc, String name, Node* node)
{
	VariableInfo* variable = alloc::new(alloc, VariableInfo);

	variable.name = name;
	variable.node = node;

	scope.variables.set(name, variable);
}

fn bool has_variable(Scope* scope, String name) 
{
    if (scope.variables.has_key(name)) 
	{
        return true;
    }

    if (scope.parent)
	{
        return has_variable(scope.parent, name);
    }

    return false;
}

fn VariableInfo* get_variable(Scope* scope, String name) 
{
    if (scope.variables.has_key(name)) 
	{
        return scope.variables.get(name)!!;
    }

    if (scope.parent) 
	{
        return get_variable(scope.parent, name);
    }

    return null;
}

fn FunctionInfo* add_function(Scope* scope, Allocator alloc, String name, String mod, Node* node) 
{
    FunctionInfo* function = alloc::new(alloc, FunctionInfo);

    function.mod  = mod;
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
