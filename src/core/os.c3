module analyzer::core::os;

import std::math;

fn OsType current()
{
	return env::OS_TYPE;
}

fn bool is_apple(OsType os)
{
	switch (os)
	{
		case MACOS:
		case TVOS:
		case WATCHOS:
		case IOS:
			return true;
		default:
			return false;
	}
}

<*
 @return "Alignment in bytes"
*>
fn AlignData get_alignment(OsType os, ArchType arch, uint bits)
{
	uint bytes = bits / 8;

	switch (arch)
	{
		case ARM:
		case THUMB:
		case ARMB:
		case THUMBEB:
		{
			if ((is_apple(os) || os == NETBSD) && bits > 32)
			{
				return { 4, math::min(8u, bytes) };
			}
			return { math::min(8u, bytes), math::min(8u, bytes) };
		}
		case PPC64:
		case PPC:
		case PPC64LE:
		case RISCV32:
		case AVR:
		case XTENSA:
			return { math::min(8u, bytes), math::min(8u, bytes) };
		case X86_64:
		case RISCV64:
		case WASM64:
		case WASM32:
			return { bytes, bytes };
		case AARCH64:
		case AARCH64_BE:
			if (bits < 32) return { bytes, 4 };
			return { bytes, bytes };
		case X86:
			if (bits <= 32) return { bytes, bytes };
			if (bits == 128) return { 16, 16 };
			if (os == ELFIAMCU) return { 4, 4 };
			if (os == WIN32 || os == NACL) return { 8, 8 };
			return { 4, 8 };
		default:
			break;
	}

	unreachable("Unknown Arch");
}
