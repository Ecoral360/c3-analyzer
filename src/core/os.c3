module analyzer::core::os;

import std::math;

fn bool is_apple(TargetOS os)
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
fn AlignData get_alignment(TargetOS os, TargetArch arch, uint bits)
{
	uint bytes = bits / 8;

	switch (arch)
	{
		case ARM:
		{
			if ((is_apple(os) || os == NETBSD) && bits > 32)
			{
				return { 4, math::min(8u, bytes) };
			}
			return { math::min(8u, bytes), math::min(8u, bytes) };
		}
		case X86_64:
		case RISCV64:
			return { bytes, bytes };
		case AARCH64:
			if (bits < 32) return { bytes, 4 };
			return { bytes, bytes };
		case X86:
			if (bits <= 32) return { bytes, bytes };
			if (bits == 128) return { 16, 16 };
			if (os == WIN32) return { 8, 8 };
			return { 4, 8 };
		default:
			break;
	}

	unreachable("Unknown Arch");
}
