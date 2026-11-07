# AXI-Lite PWM Generator

AXI4-Lite slave PWM Generator IP core for the NebuCore SoC.

## Overview

Produces a variable duty-cycle waveform for driving the external analog Piezo
Driver in the nebulizer system.  The enable must be refreshed by firmware once
per Timer tick; a hardware `pwm_force_disable` input (driven by the Watchdog
Timer) can force the output low regardless of firmware state.

## Register Map

| Offset | Name   | Access | Description                                      |
|--------|--------|--------|--------------------------------------------------|
| 0x00   | CTRL   | R/W    | [0] pwm_en — firmware refreshes each Timer tick  |
| 0x04   | DUTY   | R/W    | [7:0] duty cycle numerator (0–255)               |
| 0x08   | PERIOD | R/W    | [15:0] period in clock ticks                     |
| 0x0C   | STATUS | R      | [0] pwm_active, [1] force_disabled               |

## Address in SoC

`0x1400_0000` (12-bit window, 4 KiB) on Interconnect M04.

## Files

```
pwm/
├── README.md
├── project.config
├── scripts/
│   └── filelist
└── src/
    ├── include/
    │   └── pwm_defines.vh
    ├── rtl/
    │   └── axi_pwm_top.v
    ├── mem/
    └── package/
```
