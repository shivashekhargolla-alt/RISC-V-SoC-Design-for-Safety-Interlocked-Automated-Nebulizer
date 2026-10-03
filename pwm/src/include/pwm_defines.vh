/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite PWM Generator IP Core
 * File           : pwm_defines.vh
 * Description    : AXI4-Lite PWM Generator parameters and register-map defines
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 * Register Map (offsets, word-addressed, 32-bit registers)
 *
 *   Offset  Register   Description
 *   0x00    CTRL       Control: [0]=pwm_en, [31:1]=reserved
 *   0x04    DUTY       Duty cycle: [7:0]=duty (0–255), [31:8]=reserved
 *   0x08    PERIOD     Period count: [15:0]=period (clk ticks for full cycle)
 *   0x0C    STATUS     Status (read-only): [0]=pwm_active, [1]=force_disabled
 * -----------------------------------------------------------------------------
 * AXI-Lite interface dimensions
 *   DATA  : 32 bits
 *   ADDR  : 4 bits  (covers 0x00–0x0C, 4 registers)
 *   ID    : 12 bits (matches UART IP convention)
 *   STRB  : 4 bits
 * -----------------------------------------------------------------------------
 */

`ifndef _PWM_DEFINES_H_
`define _PWM_DEFINES_H_

// ── AXI-Lite interface widths ─────────────────────────────────────────────────
`define _PWM_AXI_DATA_WIDTH_  32
`define _PWM_AXI_ADDR_WIDTH_   4   // 4 registers × 4 bytes → 4-bit offset
`define _PWM_AXI_ID_WIDTH_    12
`define _PWM_AXI_RESP_WIDTH_   2

// ── Register offsets (word-aligned byte addresses) ───────────────────────────
`define _PWM_REG_CTRL_         4'h0   // Control register
`define _PWM_REG_DUTY_         4'h4   // Duty-cycle register
`define _PWM_REG_PERIOD_       4'h8   // Period register
`define _PWM_REG_STATUS_       4'hC   // Status register (read-only)

// ── CTRL register bit positions ───────────────────────────────────────────────
`define _PWM_CTRL_EN_BIT_      0      // bit[0] = pwm_en

// ── Default reset values ──────────────────────────────────────────────────────
`define _PWM_DUTY_RESET_       8'd128   // 50 % duty cycle at reset
`define _PWM_PERIOD_RESET_     16'd1000 // default period = 1000 clk ticks

`endif
