# AXI-Lite Watchdog Timer — Safety Interlock

AXI4-Lite slave Watchdog Timer IP core for the NebuCore SoC.  
This is the **critical safety IP** of the system.

## Overview

The Watchdog Timer enforces the hard hardware safety guarantee of the NebuCore
SoC: once a treatment dose is complete (or a firmware fault is detected), the
piezoelectric nebulising element is **permanently silenced** until the next
hardware reset.

The central element is `wdt_locked` — a **SET-ONLY flip-flop**:
- It can be **set** by: (a) the external `wdt_trigger_i` input, or (b) an
  internal stall-detection timeout.
- It can **only be cleared** by asserting hardware reset (`rst_n = 0`).
- **No AXI register write can ever clear it.**

When `wdt_locked` is set, `wdt_locked_o` is driven HIGH. This connects
combinationally to `pwm_force_disable_i` in the PWM Generator, forcing
`pwm_out` LOW with zero clock-cycle latency.

```
wdt_locked_o  ──►  pwm_force_disable_i  (forces pwm_out LOW, combinational)
alarm_out_o   ──►  alarm LED / buzzer   (combinational copy of wdt_locked)
wdt_irq_o     ──►  RISC-V interrupt     (wdt_locked AND irq_en)
```

## Lock sources

| Source | Condition | Description |
|--------|-----------|-------------|
| External trigger | `wdt_trigger_i` asserted for ≥ 1 clock | Timer IP signals dose complete |
| Stall detection | `stall_counter >= WINDOW` and `wdt_en=1` | Firmware heartbeat missed |

## Register Map

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| 0x00   | CTRL   | R/W    | [0] wdt_en — enables stall detection; [1] irq_en |
| 0x04   | WINDOW | R/W    | [15:0] stall window in seconds (default 5) |
| 0x08   | KICK   | W      | Write any value to reset stall counter (heartbeat) |
| 0x0C   | STATUS | R      | [0] wdt_locked (SET-ONLY), [1] stall_detected |

## Stall detection

With `wdt_en = 1`, a 32-bit prescaler generates 1-second ticks from the
100 MHz system clock. A 16-bit counter increments each second. If firmware
does not write to the KICK register within `WINDOW` seconds, `wdt_locked` is
set permanently.

Firmware must write to KICK (any value) at least once per `WINDOW` seconds
to confirm the core is running correctly.

## Address in SoC

`0x1600_0000` (suggested, 4 KiB) on Interconnect M06.

## Files

```
wdt/
├── README.md
├── project.config
├── scripts/
│   └── filelist
└── src/
    ├── include/
    │   └── wdt_defines.vh
    └── rtl/
        └── axi_wdt_top.v
```

## Integration notes

```systemverilog
// In soc_top.sv:
axi_wdt_top u_wdt (
    .axi_aclk_i          (clk),
    .axi_aresetn_i       (rst_n),
    // ... AXI-Lite M06 wires via width adapter ...
    .wdt_trigger_i       (timer_done_o),        // from Timer IP
    .wdt_locked_o        (wdt_locked),
    .wdt_irq_o           (wdt_irq),
    .alarm_out_o         (alarm_out_o)
);

// PWM generator receives the lock signal:
axi_pwm_top u_pwm (
    // ...
    .pwm_force_disable_i (wdt_locked),          // combinational path
    // ...
);
```

## Safety properties (for verification)

1. `wdt_locked` is 0 after reset and only ever transitions 0→1, never 1→0
   while `rst_n = 1`.
2. Asserting `wdt_trigger_i` for one clock cycle sets `wdt_locked` on the
   next rising edge, regardless of `wdt_en` or any register state.
3. No sequence of AXI writes (including writes to STATUS) can clear
   `wdt_locked`.
4. `wdt_locked_o` is a direct wire from the `wdt_locked` flop — no
   combinational gating between the flop and the output.
5. When `wdt_locked = 1`, `alarm_out_o = 1` and (if `irq_en = 1`)
   `wdt_irq_o = 1`, both combinationally.
