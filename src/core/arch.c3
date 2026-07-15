module analyzer::core::arch;

import analyzer::core;

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
    return layout;
}

fn void test_bitsizes() @test
{
	// Test X86_64 Linux (Standard 64-bit ABI)
    TargetLayout layout = get_platform_layout(TargetOS.LINUX, TargetArch.X86_64);

	log::error("Align: %s", int::alignment);
	log::error("Align: %s", short::alignment);
	log::error("Align: %s", long::alignment);
	log::error("Align: %s", int128::alignment);

    test::eq(layout.integers[BitSizes.BITS64].align, 5u);
    test::eq(layout.integers[BitSizes.BITS64].pref_align, 64u);
    test::eq(layout.integers[BitSizes.BITS32].align, 32u);
    test::eq(layout.integers[BitSizes.BITS128].align, 128u);
    test::eq(layout.integers[BitSizes.BITS8].align, 8u);
}