/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Seven-Segment Display Controller IP Core
 * File           : seg7_defines.vh
 * Description    : AXI4-Lite SEG7 Controller parameters and register-map defines
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 * Register Map (offsets, word-addressed, 32-bit registers)
 *
 *   Offset  Register   Description
 *   0x00    DATA       Digit data: [15:0] four 4-bit BCD/hex values
 *                        bits[3:0]  = digit0 (rightmost)
 *                        bits[7:4]  = digit1
 *                        bits[11:8] = digit2
 *                        bits[15:12]= digit3 (leftmost)
 *                        [31:16] reserved
 *   0x04    CTRL       Control: [0]=disp_en, [1]=blink_en, [31:2]=reserved
 *   0x08    STATUS     Status (read-only): [3:0]=current active digit index
 *   0x0C    BRIGHT     Brightness: [3:0]=PWM duty level (0=off, 15=max)
 * -----------------------------------------------------------------------------
 * AXI-Lite interface dimensions
 *   DATA  : 32 bits
 *   ADDR  : 4 bits  (covers 0x00–0x0C, 4 registers)
 *   ID    : 12 bits (matches PWM/UART IP convention)
 *   STRB  : 4 bits
 * -----------------------------------------------------------------------------
 * 7-Segment Encoding (segments a-g, active-high)
 *   Pattern bits: {g, f, e, d, c, b, a}
 *
 *   Hex  Char   Pattern
 *   0x0   0     0x3F
 *   0x1   1     0x06
 *   0x2   2     0x5B
 *   0x3   3     0x4F
 *   0x4   4     0x66
 *   0x5   5     0x6D
 *   0x6   6     0x7D
 *   0x7   7     0x07
 *   0x8   8     0x7F
 *   0x9   9     0x6F
 *   0xA   A     0x77
 *   0xB   b     0x7C
 *   0xC   C     0x39
 *   0xD   d     0x5E  (donE)
 *   0xE   E     0x79
 *   0xF   n     0x37  (off / blank marker)
 * -----------------------------------------------------------------------------
 */

`ifndef _SEG7_DEFINES_H_
`define _SEG7_DEFINES_H_

// ── AXI-Lite interface widths ─────────────────────────────────────────────────
`define _SEG7_AXI_DATA_WIDTH_  32
`define _SEG7_AXI_ADDR_WIDTH_   4   // 4 registers × 4 bytes → 4-bit offset
`define _SEG7_AXI_ID_WIDTH_    12

// ── Register offsets (word-aligned byte addresses) ───────────────────────────
`define _SEG7_REG_DATA_   4'h0  // [15:0] BCD/encoded digit data (4 digits × 4 bits)
`define _SEG7_REG_CTRL_   4'h4  // [0]=disp_en, [1]=blink_en
`define _SEG7_REG_STATUS_ 4'h8  // [3:0] current active digit index (read-only)
`define _SEG7_REG_BRIGHT_ 4'hC  // [3:0] brightness PWM duty (0=off, 15=max)

// ── CTRL register bit positions ───────────────────────────────────────────────
`define _SEG7_CTRL_DISP_EN_BIT_   0   // bit[0] = disp_en
`define _SEG7_CTRL_BLINK_EN_BIT_  1   // bit[1] = blink_en

// ── Default reset values ──────────────────────────────────────────────────────
`define _SEG7_DATA_RESET_    16'h0000  // all digits blank (0) at reset
`define _SEG7_BRIGHT_RESET_  4'hF      // full brightness at reset

// ── Multiplexer timing (100 MHz clock) ───────────────────────────────────────
// Each digit is displayed for ~4 ms  → 400,000 clock ticks
// Blink toggle period ~500 ms        → 50,000,000 clock ticks
`define _SEG7_MUX_PRESCALE_  20'd400000   // 4 ms per digit @ 100 MHz
// (stored as a 26-bit constant to accommodate 50,000,000)
`define _SEG7_BLINK_HALF_    26'd50000000 // 500 ms half-period @ 100 MHz

`endif
