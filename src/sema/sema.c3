module analyzer::sema @if($feature(SEMA));

import analyzer::core;

import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;
import std::collections::set;

struct SemaContext
{
	Allocator allocator;
	Scope* scope;
}

fn SemaContext* create(Allocator alloc)
{
	SemaContext* ctx = alloc::new(alloc, SemaContext);

	ctx.allocator = alloc;
	ctx.scope = scope::create(alloc);

	return ctx;
}