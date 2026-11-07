/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Watchdog Timer (Safety Interlock) IP Core
 * File           : wdt_defines.vh
 * Description    : AXI4-Lite WDT parameters and register-map defines
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 * Register Map (offsets, word-addressed, 32-bit registers)
 *
 *   Offset  Register   Description
 *   0x00    CTRL       Control: [0]=wdt_en, [1]=irq_en, [31:2]=reserved
 *   0x04    WINDOW     Stall window: [15:0]=seconds before lock, [31:16]=reserved
 *   0x08    KICK       Heartbeat: write any value to reset stall counter
 *   0x0C    STATUS     Status (read-only): [0]=wdt_locked, [1]=stall_detected
 * -----------------------------------------------------------------------------
 * AXI-Lite interface dimensions
 *   DATA  : 32 bits
 *   ADDR  : 4 bits  (covers 0x00–0x0C, 4 registers)
 *   ID    : 12 bits (matches UART/PWM IP convention)
 *   STRB  : 4 bits
 * -----------------------------------------------------------------------------
 */

`ifndef _WDT_DEFINES_H_
`define _WDT_DEFINES_H_

// ── AXI-Lite interface widths ─────────────────────────────────────────────────
`define _WDT_AXI_DATA_WIDTH_  32
`define _WDT_AXI_ADDR_WIDTH_   4   // 4 registers × 4 bytes → 4-bit offset
`define _WDT_AXI_ID_WIDTH_    12

// ── Register offsets (word-aligned byte addresses) ───────────────────────────
`define _WDT_REG_CTRL_    4'h0  // [0]=wdt_en (enable stall detection), [1]=irq_en
`define _WDT_REG_WINDOW_  4'h4  // [15:0] stall-detect window in seconds
`define _WDT_REG_KICK_    4'h8  // write any value to kick the watchdog
`define _WDT_REG_STATUS_  4'hC  // [0]=wdt_locked (read-only), [1]=stall_detected (read-only)

// ── Default reset values ──────────────────────────────────────────────────────
// Stall timeout default: 5 seconds
`define _WDT_WINDOW_RESET_  16'd5
// Prescaler for 1-second tick at 100 MHz
`define _WDT_PRESCALER_     32'd100_000_000

`endif
