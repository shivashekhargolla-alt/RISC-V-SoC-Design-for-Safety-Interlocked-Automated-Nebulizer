# AXI-Lite Countdown Timer

AXI4-Lite slave Countdown Timer IP core for the NebuCore SoC.

## Overview

Second-resolution countdown timer that enforces the nebulizer treatment
duration.  Firmware loads the dose time (in seconds) into LOAD, sets
`timer_en`, and the timer counts down to zero.  On expiry it asserts
`timer_done_o` (combinational feed to the Watchdog `wdt_trigger`) and
`timer_irq_o` (interrupt to the RISC-V PIC) so the actuator is shut down
by hardware even if firmware stalls.

## Register Map

| Offset | Name   | Access | Description                                           |
|--------|--------|--------|-------------------------------------------------------|
| 0x00   | CTRL   | R/W    | [0] timer_en, [1] irq_en                             |
| 0x04   | LOAD   | R/W    | [15:0] countdown initial value (seconds); write reloads COUNT |
| 0x08   | COUNT  | R      | [15:0] current countdown value (live, read-only)     |
| 0x0C   | STATUS | R/W    | [0] irq_pending (W1C), [1] done (read-only)          |

## Non-AXI Outputs

| Signal        | Width | Destination              | Description                        |
|---------------|-------|--------------------------|------------------------------------|
| `timer_irq_o` | 1     | RISC-V VeeR EL2 PIC      | Asserted when done and irq_en=1    |
| `timer_done_o`| 1     | Watchdog `wdt_trigger`   | Combinational; asserted when done  |

## Address in SoC

`0x1800_0000` (suggested, 4 KiB window) on Interconnect M02.

## Files

```
timer/
├── README.md
├── project.config
├── scripts/
│   └── filelist
└── src/
    ├── include/
    │   └── timer_defines.vh
    └── rtl/
        └── axi_timer_top.v
```
