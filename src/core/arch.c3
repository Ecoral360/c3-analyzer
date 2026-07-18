module analyzer::core::arch;

import analyzer::core;

fn ArchType current()
{
	return env::ARCH_TYPE;
}

<*
 get the size of a pointer in bytes for the given architecture
*>
fn char ptr_size(ArchType arch)
{
	switch (arch)
	{
		case X86_64:
		case AARCH64:
		case RISCV64:
			return 8;
		case X86:
		case ARM:
			return 4;
		default:
			return 0;
	}
}

fn char ArchType.ptr_size(self) => ptr_size(self);

// Returns the native word size in bytes (usually matches pointer size).
fn char word_size(ArchType arch)
{
	return ptr_size(arch);
}

fn char native_alignment(ArchType arch)
{
	return ptr_size(arch);
}

fn bool is_64bit(ArchType arch)
{
	return ptr_size(arch) == 8;
}

<*
 the max integer width the architecture can handle in one register.
*>
fn char max_int_width(ArchType arch)
{
	return ptr_size(arch) * 8;
}

fn TargetLayout get_platform_layout(OsType os, ArchType arch)
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
    TargetLayout layout = get_platform_layout(LINUX, X86_64);

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
