module analyzer::sema::registry @if($feature(SEMA));

import std::collections::map;
import std::collections::list;

import analyzer::core::ast;

struct MethodBucket
{
    HashMap{String, Symbol*} methods;
}

struct MethodRegistry
{
	// Type*
	HashMap{void*, MethodBucket*} buckets;
	Allocator arena;
}

fn void MethodRegistry.init(&self, Allocator arena)
{
	self.arena = arena;
	self.methods.init(mem);
}

fn void MethodRegistry.free(&self)
{
	self.methods.free();
}

fn void MethodRegistry.reset(&self)
{
	self.methods.clear();
}

fn void MethodRegistry.register_method(&self, Type* type, String method_name, Node* method_node, Node* condition)
{	
	MethodBucket* bucket = self.buckets.get(type) ?? null;
	if (!bucket)
	{
		bucket = alloc::new(self.arena, MethodBucket);
		bucket.methods.init(self.arena);
		self.buckets[type] = bucket;
	}

	Symbol* head = bucket.methods.get(method_name) ?? null;

	Symbol* new_entry = alloc::new(self.arena, Symbol);
	*new_entry = { 
		.node = method_node,
		.condition = condition,
		.next = head
	};

	bucket.methods[method_name] = new_entry;
}

fn MethodBucket* MethodRegistry.get_bucket(Type* type)
{
	return self.buckets.get(type) ?? null;
}

fn void MethodRegistry.collect_all_methods(Type* type, List{Symbol*}* out_list) 
{
	MethodBucket* bucket = self.get_bucket(type);
	if (!bucket) return;

	foreach (entry : bucket.methods) 
	{
		Symbol* symbol = entry.value; 

		while (symbol) 
		{
			out_list.push(symbol);
			symbol = symbol.next;
		}
	}
}