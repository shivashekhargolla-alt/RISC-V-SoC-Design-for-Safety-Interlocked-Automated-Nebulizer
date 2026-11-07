/*
 * NebuCore SoC — Linker Script
 *
 * Links firmware for the RISC-V VeeR EL2 SoC booting from RAM at 0x0000_0000.
 *
 * Memory map:
 *   RAM  : 0x0000_0000 – 0x3FFF_FFFF  (M01, 1 GiB)
 *   UART : 0x1000_0000 – 0x10FF_FFFF  (M00)
 *   PWM  : 0x1400_0000 – 0x1400_0FFF  (M04)
 *
 * The testbench sets rst_vec = 0x0000_0000, so .text.init must be at address 0.
 *
 * RAM size used by the TB is 64 KiB (0x10000).  We keep .text + .data + stack
 * well within that range.
 */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x10000  /* 64 KiB */
}

SECTIONS
{
    /* Code starts at address 0 — this is the reset vector */
    . = 0x00000000;

    .text.init : {
        *(.text.init)       /* _start entry point */
    } > RAM

    .text : {
        *(.text)            /* regular code */
        *(.text.*)
    } > RAM

    .rodata : {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
    } > RAM

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > RAM

    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    /* Completion marker area — placed at a known offset */
    . = 0x1000;
    .marker (NOLOAD) : {
        KEEP(*(.marker))
    } > RAM

    /* Stack at the top of the 64 KiB RAM */
    . = ORIGIN(RAM) + LENGTH(RAM) - 0x100;  /* 256 bytes below top */
    _stack_top = .;

    /* Provide end symbol */
    _end = .;
}
