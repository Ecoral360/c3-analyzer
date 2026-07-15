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
	type.data.node = node;
	type.status = UNRESOLVED; 

	lookup.types.set(name, type);
}	

fn void create_builtin(Lookup* lookup, Allocator alloc, String name, 
	TypeKind kind, char bits, char bytes, char abi_align, char pref_align)
{
	Type* type = alloc::new(alloc, Type);
	type.name = name;
	type.kind = kind;
	type.status = RESOLVED;

	type.data.builtin.bitsize = bits;
	type.data.builtin.bytesize = bytes;
	type.data.builtin.abi_alignment = abi_align;
	type.data.builtin.pref_alignment = pref_align;

	lookup.types.set(name, type);
}

fn void init_builtin_types(Lookup* lookup, Allocator alloc, TargetArch arch)
{
	char psize = arch::ptr_size(arch);
    char pbits = psize * 8;

	create_builtin(lookup, alloc, "void", TYPE_VOID, 1, 1, 1, 1);
	create_builtin(lookup, alloc, "bool", TYPE_BOOL, 8, 1, 1, 1);

	create_builtin(lookup, alloc, "ichar", TYPE_I8, 8, 1, 1, 1);
	create_builtin(lookup, alloc, "char", TYPE_U8, 8, 1, 1, 1);

	create_builtin(lookup, alloc, "short", TYPE_I16, 16, 2, 1, 1);
	create_builtin(lookup, alloc, "ushort", TYPE_U16, 16, 2, 1, 1);

	create_builtin(lookup, alloc, "int", TYPE_I32, 32, 4, 4, 4);
	create_builtin(lookup, alloc, "uint", TYPE_U32, 32, 4, 4, 4);

	create_builtin(lookup, alloc, "long", TYPE_I64, 64, 8, 4, 4);
	create_builtin(lookup, alloc, "ulong", TYPE_U64, 64, 8, 4, 4);

	create_builtin(lookup, alloc, "int128", TYPE_I128, 128, 16, 16, 16);
	create_builtin(lookup, alloc, "uint128", TYPE_U128, 128, 16, 16, 16);

	create_builtin(lookup, alloc, "float", TYPE_F32, 32, 4, 4, 4);
	create_builtin(lookup, alloc, "double", TYPE_F64, 64, 4, 4, 4);

	create_builtin(lookup, alloc, "sz", TYPE_SZ, pbits, psize, psize, psize);
	create_builtin(lookup, alloc, "usz", TYPE_USZ, pbits, psize, psize, psize);

	create_builtin(lookup, alloc, "iptr", TYPE_IPTR, pbits, psize, psize, psize);
	create_builtin(lookup, alloc, "uptr", TYPE_UPTR, pbits, psize, psize, psize);
}