/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Countdown Timer IP Core
 * File           : timer_defines.vh
 * Description    : AXI4-Lite Timer parameters and register-map defines
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 * Register Map (offsets, word-addressed, 32-bit registers)
 *
 *   Offset  Register   Description
 *   0x00    CTRL       Control: [0]=timer_en, [1]=irq_en, [31:2]=reserved
 *   0x04    LOAD       Load value: [15:0]=load (seconds), [31:16]=reserved
 *   0x08    COUNT      Current countdown: [15:0]=count (read-only)
 *   0x0C    STATUS     Status: [0]=irq_pending (W1C), [1]=done (read-only)
 * -----------------------------------------------------------------------------
 * AXI-Lite interface dimensions
 *   DATA  : 32 bits
 *   ADDR  : 4 bits  (covers 0x00–0x0C, 4 registers)
 *   ID    : 12 bits (matches PWM/UART IP convention)
 *   STRB  : 4 bits
 * -----------------------------------------------------------------------------
 */

`ifndef _TIMER_DEFINES_H_
`define _TIMER_DEFINES_H_

// ── AXI-Lite interface widths ─────────────────────────────────────────────────
`define _TIMER_AXI_DATA_WIDTH_  32
`define _TIMER_AXI_ADDR_WIDTH_   4   // 4 registers × 4 bytes → 4-bit offset
`define _TIMER_AXI_ID_WIDTH_    12

// ── Register offsets (word-aligned byte addresses) ───────────────────────────
`define _TIMER_REG_CTRL_    4'h0   // [0]=timer_en, [1]=irq_en
`define _TIMER_REG_LOAD_    4'h4   // [15:0] countdown load value (seconds)
`define _TIMER_REG_COUNT_   4'h8   // [15:0] current countdown (read-only)
`define _TIMER_REG_STATUS_  4'hC   // [0]=irq_pending, [1]=done (read-only)

// ── Default prescaler for 1-second tick from 100 MHz clock ───────────────────
`define _TIMER_PRESCALER_   32'd100_000_000

`endif
