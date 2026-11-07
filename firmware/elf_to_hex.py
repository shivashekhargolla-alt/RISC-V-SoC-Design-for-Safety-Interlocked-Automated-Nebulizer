#!/usr/bin/env python3
"""
NebuCore SoC — ELF to Verilog $readmemh Hex Converter

Converts a RISC-V ELF binary into a hex file suitable for $readmemh in the
NebuCore SoC testbench.  The testbench RAM is organised as 64-bit words
(8 bytes per word), little-endian.

Output format:
  @<word_address_in_hex>      (Verilog $readmemh address, 0-based word index)
  XX XX XX XX XX XX XX XX      (8 bytes per line, space-separated, uppercase hex)
  XX XX XX XX XX XX XX XX
  ...

The hex file covers the loadable segments of the ELF.  Gaps between segments
are skipped by emitting new @-address directives.

Usage:
  python3 elf_to_hex.py <input.elf> <output.hex> [--word-size 8]

The --word-size option controls how many bytes are packed per line.
Default is 8 (matching the 64-bit AXI4 RAM in tb_soc_top.sv).
"""

import struct
import sys
import argparse


def read_elf_segments(elf_path):
    """Read loadable segments from an ELF file.
    Returns a list of (phys_addr, data_bytes) tuples sorted by address.
    """
    with open(elf_path, "rb") as f:
        # Read ELF header
        magic = f.read(4)
        if magic != b"\x7fELF":
            raise ValueError(f"Not an ELF file: {elf_path}")

        ei_class = struct.unpack("B", f.read(1))[0]
        if ei_class == 1:
            is_32bit = True
        elif ei_class == 2:
            is_32bit = False
        else:
            raise ValueError(f"Unknown ELF class: {ei_class}")

        ei_data = struct.unpack("B", f.read(1))[0]
        if ei_data == 1:
            endian = "<"  # little-endian
        elif ei_data == 2:
            endian = ">"  # big-endian
        else:
            raise ValueError(f"Unknown ELF endianness: {ei_data}")

        f.read(10)  # skip ei_version, ei_osabi, ei_pad (10 bytes)

        if is_32bit:
            # ELF32 header: after the 16-byte e_ident, we have:
            #   e_type(H) e_machine(H) e_version(I) e_entry(I) e_phoff(I)
            #   e_shoff(I) e_flags(I) e_ehsize(H) e_phentsize(H) e_phnum(H)
            # = 2+2+4+4+4+4+4+2+2+2 = 30 bytes
            e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, \
                e_flags, e_ehsize, e_phentsize, e_phnum = struct.unpack(
                    endian + "HHIIIIIHHH", f.read(30))
        else:
            # ELF64 header
            e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, \
                e_flags, e_ehsize, e_phentsize, e_phnum = struct.unpack(
                    endian + "HHIQQQIHHH", f.read(36))

        # Read program headers
        segments = []
        for i in range(e_phnum):
            f.seek(e_phoff + i * e_phentsize)
            if is_32bit:
                p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, \
                    p_flags, p_align = struct.unpack(
                        endian + "IIIIIIII", f.read(32))
            else:
                p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, \
                    p_memsz, p_align = struct.unpack(
                        endian + "IIQQQQQQ", f.read(56))

            # PT_LOAD = 1
            if p_type == 1 and p_filesz > 0:
                f.seek(p_offset)
                data = f.read(p_filesz)
                segments.append((p_paddr, data))

        segments.sort(key=lambda s: s[0])
        return segments


def segments_to_hex(segments, word_size=8):
    """Convert segments to $readmemh format.
    Each line has one `word_size`-byte word in little-endian order,
    formatted as an unspaced uppercase hex string.
    Address lines use @<hex_word_index>.
    """
    lines = []

    for seg_addr, seg_data in segments:
        # Align segment data to word boundaries
        # If the segment doesn't start on a word boundary, we need to handle
        # the partial word.  For simplicity, we pad to word alignment.
        word_index = seg_addr // word_size
        offset_in_word = seg_addr % word_size

        # Emit @address directive
        lines.append(f"@{word_index:08X}")

        # If there's an offset within the word, pad the beginning
        byte_idx = 0
        if offset_in_word != 0:
            # Pad the first partial word with zeros
            word_bytes = [0] * word_size
            remaining = word_size - offset_in_word
            to_copy = min(remaining, len(seg_data))
            word_bytes[offset_in_word:offset_in_word + to_copy] = \
                list(seg_data[:to_copy])
            lines.append("".join(f"{b:02X}" for b in reversed(word_bytes)))
            byte_idx = to_copy
            word_index += 1
            if byte_idx < len(seg_data):
                lines.append(f"@{word_index:08X}")

        # Output full words
        while byte_idx + word_size <= len(seg_data):
            word_bytes = seg_data[byte_idx:byte_idx + word_size]
            lines.append("".join(f"{b:02X}" for b in reversed(word_bytes)))
            byte_idx += word_size
            word_index += 1

        # Handle remaining bytes (partial last word)
        if byte_idx < len(seg_data):
            word_bytes = list(seg_data[byte_idx:]) + [0] * (word_size - (len(seg_data) - byte_idx))
            lines.append("".join(f"{b:02X}" for b in reversed(word_bytes)))

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Convert RISC-V ELF to Verilog $readmemh hex format")
    parser.add_argument("elf", help="Input ELF file")
    parser.add_argument("hex", help="Output hex file")
    parser.add_argument("--word-size", type=int, default=8,
                        help="Bytes per line (default: 8 for 64-bit RAM)")
    args = parser.parse_args()

    segments = read_elf_segments(args.elf)
    if not segments:
        print(f"ERROR: No loadable segments found in {args.elf}", file=sys.stderr)
        sys.exit(1)

    hex_content = segments_to_hex(segments, args.word_size)

    with open(args.hex, "w") as f:
        f.write(hex_content)

    # Print summary
    total_bytes = sum(len(d) for _, d in segments)
    print(f"Converted {args.elf} → {args.hex}")
    print(f"  Segments: {len(segments)}")
    for addr, data in segments:
        print(f"    0x{addr:08X}: {len(data)} bytes")
    print(f"  Total: {total_bytes} bytes ({total_bytes // args.word_size} "
          f"× {args.word_size}-byte words)")


if __name__ == "__main__":
    main()
