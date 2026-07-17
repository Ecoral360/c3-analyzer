module analyzer::core::arch;

import analyzer::core;

fn TargetArch current()
{
	switch (env::ARCH_TYPE)
	{
		case X86_64:  return X86_64;
		case X86:     return X86;
		case AARCH64: return AARCH64;
		case ARM:     return ARM;
		case RISCV32: return RISCV32;
		case RISCV64: return RISCV64;
		default: break;
	}

	unreachable("Unknown arch");
}

<*
 get the size of a pointer in bytes for the given architecture
*>
fn char ptr_size(TargetArch arch)
{
	switch (arch)
	{
		case TargetArch.X86_64:
		case TargetArch.AARCH64:
		case TargetArch.RISCV64:
			return 8;
		case TargetArch.X86:
		case TargetArch.ARM:
			return 4;
		default:
			return 0;
	}
}

fn char TargetArch.ptr_size(self) => ptr_size(self);

// Returns the native word size in bytes (usually matches pointer size).
fn char word_size(TargetArch arch)
{
	return ptr_size(arch);
}

fn char native_alignment(TargetArch arch)
{
	return ptr_size(arch);
}

fn bool is_64bit(TargetArch arch)
{
	return ptr_size(arch) == 8;
}

<*
 the max integer width the architecture can handle in one register.
*>
fn char max_int_width(TargetArch arch)
{
	return ptr_size(arch) * 8;
}

fn TargetLayout get_platform_layout(TargetOS os, TargetArch arch)
{
    TargetLayout layout;
    for (char i = BitSizes.BITS8.ordinal; i < BitSizes::len; i++)
    {
   		layout.integers[i] = os::get_alignment(os, arch, BitSizes::from_ordinal(i).bits);
    }
    return layout;
}

fn void test_bitsizes() @test
{
	// Test X86_64 Linux (Standard 64-bit ABI)
    TargetLayout layout = get_platform_layout(TargetOS.LINUX, TargetArch.X86_64);

	log::error("Align: %s", char::alignment);
	log::error("Align: %s", int::alignment);
	log::error("Align: %s", short::alignment);
	log::error("Align: %s", long::alignment);
	log::error("Align: %s", int128::alignment);

    test::eq(layout.integers[BitSizes.BITS64].align, 8u);
    test::eq(layout.integers[BitSizes.BITS64].pref_align, 8u);
    test::eq(layout.integers[BitSizes.BITS32].align, 4u);
    test::eq(layout.integers[BitSizes.BITS128].align, 16u);
    test::eq(layout.integers[BitSizes.BITS8].align, 1u);
}
