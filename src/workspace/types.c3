module analyzer::workspace::types;

import analyzer::core;

Type type_bool;
Type type_void;
Type type_voidptr;
Type type_float16;
Type type_bfloat;
Type type_float;
Type type_double;
Type type_f128;
Type type_typeid;
Type type_any;
Type type_typeinfo;
Type type_ichar;
Type type_short;
Type type_int;
Type type_long;
Type type_i128;
Type type_iptr;
Type type_sz;
Type type_char;
Type type_ushort;
Type type_uint;
Type type_ulong;
Type type_u128;
Type type_uptr;
Type type_usz;
Type type_fault;
Type type_untypedlist;
Type type_wildcard;
Type type_member;
Type type_reflection;
Type type_chars;
Type type_wildcard_optional;
Type type_string;
Type type_reflected_param;
Type type_cint;
Type type_cuint;

fn void init()
{
	BitSizes pointer_bits = core::int_to_bit_size(bitsizeof(void*));

	type_init("void", &type_void, TYPE_VOID, BITS8, void);
	type_init("void*", &type_voidptr, TYPE_POINTER, pointer_bits, void*);
	type_init("typeid", &type_typeid, TYPE_TYPEID, pointer_bits, typeid);

	type_init("float16", &type_float16, TYPE_F16, BITS16, float16);
	type_init("bfloat", &type_bfloat, TYPE_BF16, BITS16, bfloat);
	type_init("float", &type_float, TYPE_F32, BITS32, float);
	type_init("double", &type_double, TYPE_F64, BITS64, double);
	type_init("float128", &type_f128, TYPE_F128, BITS128, float128);

	type_init("ichar", &type_ichar, TYPE_I8, BITS8, ichar);
	type_init("short", &type_short, TYPE_I16, BITS16, short);
	type_init("int", &type_int, TYPE_I32, BITS32, int);
	type_init("long", &type_long, TYPE_I64, BITS64, long);
	type_init("int128", &type_i128, TYPE_I128, BITS128, int128);

	type_init("bool", &type_bool, TYPE_BOOL, BITS8, bool);
	type_init("char", &type_char, TYPE_U8, BITS8, char);
	type_init("ushort", &type_ushort, TYPE_U16, BITS16, ushort);
	type_init("uint", &type_uint, TYPE_U32, BITS32, uint);
	type_init("ulong", &type_ulong, TYPE_U64, BITS64, ulong);
	type_init("uint128", &type_u128, TYPE_U128, BITS128, uint128);

	type_create("typeinfo", &type_typeinfo, TYPE_TYPEINFO, 1, 1, 1);
	type_create("member_ref", &type_member, TYPE_MEMBER, 1, 1, 1);
	type_create("reflection_ref", &type_reflection, TYPE_TYPEINFO, 1, 1, 1);
	type_create("untypedlist", &type_untypedlist, TYPE_UNTYPEDLIST, 1, 1, 1);
	type_create("void", &type_wildcard, TYPE_WILDCARD, 1, 1, 1);
}

macro void type_init(String name, Type* location, TypeKind kind, BitSizes bitsize, type)
{
	uint byte_size = $Typeof(type)::size;
	uint align = $Typeof(type)::alignment;
	*location = {
		.kind = kind,
		.size = byte_size,
		.name = name,
		.data.builtin = {
			.bytesize = (char)byte_size,
			.bitsize = bitsize.ordinal,
			.abi_alignment = (char)align,
			.pref_alignment = (char)align
		},
		.canonical = location
	};
}

fn void type_create(String name, Type* type, TypeKind kind, uint bitsize, uint align, uint pref_align)
{
	uint byte_size = (bitsize + 7) / 8;
	*type = {
		.kind = kind,
		.name = name,
		.size = byte_size,
		.data.builtin = {
			.bytesize = (char)byte_size,
			.bitsize = (char)bitsize,
			.abi_alignment = (char)align,
			.pref_alignment = pref_align ? (char)pref_align : (char)align
		},
		.canonical = type,
	};
}

fn void type_create_alias(String name, Type* location, Type* canonical)
{
	unreachable("Not implemented yet, waiting for node rework!");
}