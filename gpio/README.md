# AXI-Lite GPIO Controller

AXI4-Lite slave bidirectional 8-bit GPIO Controller IP core for the NebuCore SoC.

## Overview

Provides 8 individually-configurable GPIO pins for interfacing with the
volume-selection input switches and alarm output indicator in the nebulizer
system.  Each pin direction (input/output) is controlled via the DIR register.
An IRQ-on-change mechanism allows the RISC-V core to be interrupted when any
enabled input pin changes state.

## Register Map

| Offset | Name | Access | Description                                                   |
|--------|------|--------|---------------------------------------------------------------|
| 0x00   | DIR  | R/W    | [7:0] per-pin direction: 1=output, 0=input. Reset=0x00       |
| 0x04   | OUT  | R/W    | [7:0] output data; only pins with DIR=1 are driven            |
| 0x08   | IN   | R      | [7:0] sampled input value (two-flop synchronised, read-only)  |
| 0x0C   | IRQ  | R/W    | [7:0] IRQ-on-change enable per pin; write any value to clear pending IRQs |

## Physical Interface

| Port           | Width | Direction | Description                              |
|----------------|-------|-----------|------------------------------------------|
| `gpio_pin_i`   | [7:0] | input     | Physical pad inputs (from board pads)    |
| `gpio_pin_o`   | [7:0] | output    | Physical pad outputs (to board pads)     |
| `gpio_pin_oe`  | [7:0] | output    | Output-enable per pin (high = drive pad) |
| `gpio_irq_o`   | 1     | output    | Level interrupt to RISC-V PLIC/PIC       |

## Output Logic

```
gpio_pin_oe[n] = dir_reg[n]
gpio_pin_o[n]  = out_reg[n] & dir_reg[n]   // inactive pins drive 0
```

## IRQ Behaviour

Input pins are passed through a two-flop synchroniser to prevent metastability.
An edge detector compares the current and previous synchronised samples.  Any
rising or falling edge on a pin whose `irq_en` bit is 1 latches the internal
`irq_pending` flag, asserting `gpio_irq_o` (level-high).  Writing any value to
the IRQ register clears `irq_pending` — firmware should read the IN register
first to determine which pins changed before clearing.

## Address in SoC

`0x1800_0000` (suggested, 4 KiB window) on Interconnect M03.

## Files

```
gpio/
├── README.md
├── project.config
├── scripts/
│   └── filelist
└── src/
    ├── include/
    │   └── gpio_defines.vh
    └── rtl/
        └── axi_gpio_top.v
```
