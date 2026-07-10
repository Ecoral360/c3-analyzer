module analyzer::sema @if($feature(SEMA));

import analyzer::core;

import std::collections;

<*
 -`pointer_cache`: Key: BaseType, Value: PointerType
*>
struct TypeRegistry
{
	Allocator allocator;
	Primitives primitives;
	HashMap{void*, Type*} types;
	HashMap{void*, Type*} pointer_cache;
}

struct Primitives
{
	Type* type_bool;
	Type* type_void;
	Type* type_voidptr;
	Type* type_float16;
	Type* type_bfloat;
	Type* type_float;
	Type* type_double;
	Type* type_f128;
	Type* type_typeid;
	Type* type_any;
	Type* type_ichar;
	Type* type_short;
	Type* type_int;
	Type* type_long;
	Type* type_i128;
	Type* type_iptr;
	Type* type_sz;
	Type* type_char;
	Type* type_ushort;
	Type* type_uint;
	Type* type_ulong;
	Type* type_u128;
	Type* type_uptr;
	Type* type_usz;
	Type* type_fault;
	Type* type_untypedlist;
	Type* type_wildcard;
	Type* type_member;
	Type* type_reflection;
	Type* type_chars;
	Type* type_wildcard_optional;
	Type* type_string;
	Type* type_reflected_param;
	Type* type_cint;
	Type* type_cuint;
}

fn void TypeRegistry.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.types.init(allocator);
	self.pointer_cache.init(allocator);

	BitSizes pointer_bits = core::int_to_bit_size(bitsizeof(void*));

	self.primitives.type_void = self.create_primitive("void", TYPE_VOID, BITS8, void);
	self.primitives.type_voidptr = self.create_primitive("void*", TYPE_POINTER, pointer_bits, void*);
	self.primitives.type_typeid = self.create_primitive("typeid", TYPE_TYPEID, pointer_bits, typeid);

	self.primitives.type_float16 = self.create_primitive("float16", TYPE_F16, BITS16, float16);
	self.primitives.type_bfloat = self.create_primitive("bfloat", TYPE_BF16, BITS16, bfloat);
	self.primitives.type_float = self.create_primitive("float", TYPE_F32, BITS32, float);
	self.primitives.type_double = self.create_primitive("double", TYPE_F64, BITS64, double);
	self.primitives.type_f128 = self.create_primitive("float128", TYPE_F128, BITS128, float128);

	self.primitives.type_ichar = self.create_primitive("ichar", TYPE_I8, BITS8, ichar);
	self.primitives.type_short = self.create_primitive("short", TYPE_I16, BITS16, short);
	self.primitives.type_int  = self.create_primitive("int", TYPE_I32, BITS32, int);
	self.primitives.type_long = self.create_primitive("long", TYPE_I64, BITS64, long);
	self.primitives.type_i128 = self.create_primitive("int128", TYPE_I128, BITS128, int128);

	self.primitives.type_bool = self.create_primitive("bool", TYPE_BOOL, BITS8, bool);
	self.primitives.type_char = self.create_primitive("char", TYPE_U8, BITS8, char);
	self.primitives.type_ushort = self.create_primitive("ushort", TYPE_U16, BITS16, ushort);
	self.primitives.type_uint = self.create_primitive("uint", TYPE_U32, BITS32, uint);
	self.primitives.type_ulong = self.create_primitive("ulong", TYPE_U64, BITS64, ulong);
	self.primitives.type_u128 = self.create_primitive("uint128", TYPE_U128, BITS128, uint128);

	//self.primitives.type_fault = self.create_primitive("fault", TYPE_FAULT, pointer_bits, void*);

	//self.primitives.type_member = create_primitive("member_ref", TYPE_MEMBER, 1, 1, 1);
	//self.primitives.type_reflection = create_primitive("reflection_ref", TYPE_TYPEINFO, 1, 1, 1);
	//self.primitives.type_untypedlist = create_primitive("untypedlist", TYPE_UNTYPEDLIST, 1, 1, 1);
	//self.primitives.type_void = create_primitive("void", TYPE_WILDCARD, 1, 1, 1);
}

fn Type* TypeRegistry.get_pointer(&self, Type* base)
{
	if (try Type* existing = self.pointer_cache.get(base)) 
	{
		return existing;
	}

	Type* t = alloc::new(self.allocator, Type);
	t.kind = TYPE_POINTER;
	t.data.pointer_base = base;

	self.pointer_cache.set(base, t);
	return t;
}

macro void TypeRegistry.free(&self)
{
	$foreach $member : Primitives::members:
		if (self.primitives.$member)
		{
			alloc::free(self.allocator, self.primitives.$member);
		}
	$endforeach

	self.pointer_cache.free();

	foreach (type : self.types)
	{
		type.name.free(self.allocator);
		alloc::free(self.allocator, type);
	}

	self.types.free();
}

macro Type* TypeRegistry.create_primitive(&self, String name, TypeKind kind, BitSizes bitsize, type)
{
	Type* t = alloc::alloc(self.allocator, Type);

	uint byte_size = $Typeof(type)::size;
	uint align = $Typeof(type)::alignment;

	t.kind = kind;
	t.size = byte_size;
	t.name = name.copy(self.allocator);
	t.data.builtin.bytesize = (char)byte_size;
	t.data.builtin.bitsize = bitsize.ordinal;
	t.data.builtin.abi_alignment = (char)align;
	t.data.builtin.pref_alignment = (char)align;

	self.types.set(t.name, t);

	return t;
}
