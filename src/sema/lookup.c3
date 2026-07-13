module analyzer::sema::lookup @if($feature(SEMA));

import analyzer::core;

fn Lookup* create(Allocator alloc)
{
	Lookup* lookup = alloc::new(alloc, Lookup);

	lookup.types.init(alloc);

	return lookup;
}

fn void register_type(Lookup* lookup, Allocator alloc, String name, Node* node) 
{
	Type* type = alloc::new(alloc, Type);

	type.name = name;
	type.node = node;

	lookup.types.set(name, type);
}