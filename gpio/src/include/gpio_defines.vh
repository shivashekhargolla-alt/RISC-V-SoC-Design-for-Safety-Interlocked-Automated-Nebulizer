/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite GPIO Controller IP Core
 * File           : gpio_defines.vh
 * Description    : AXI4-Lite GPIO Controller parameters and register-map defines
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 * Register Map (offsets, word-addressed, 32-bit registers)
 *
 *   Offset  Register   Description
 *   0x00    DIR        Direction: [7:0]=dir (1=output, 0=input per pin), [31:8]=reserved
 *   0x04    OUT        Output data: [7:0]=out (value driven on output pins), [31:8]=reserved
 *   0x08    IN         Input data: [7:0]=in (reflects gpio_pin_i, read-only), [31:8]=reserved
 *   0x0C    IRQ        IRQ-on-change enable: [7:0]=irq_en per pin; write any value to clear pending
 * -----------------------------------------------------------------------------
 * AXI-Lite interface dimensions
 *   DATA  : 32 bits
 *   ADDR  : 4 bits  (covers 0x00–0x0C, 4 registers)
 *   ID    : 12 bits (matches PWM/UART IP convention)
 *   STRB  : 4 bits
 * -----------------------------------------------------------------------------
 */

`ifndef _GPIO_DEFINES_H_
`define _GPIO_DEFINES_H_

// ── AXI-Lite interface widths ─────────────────────────────────────────────────
`define _GPIO_AXI_DATA_WIDTH_  32
`define _GPIO_AXI_ADDR_WIDTH_   4   // 4 registers × 4 bytes → 4-bit offset
`define _GPIO_AXI_ID_WIDTH_    12

// ── Register offsets (word-aligned byte addresses) ───────────────────────────
`define _GPIO_REG_DIR_    4'h0   // [7:0] direction: 1=output, 0=input (per pin)
`define _GPIO_REG_OUT_    4'h4   // [7:0] output data register
`define _GPIO_REG_IN_     4'h8   // [7:0] input data register (read-only)
`define _GPIO_REG_IRQ_    4'hC   // [7:0] IRQ-on-change enable per pin; write 1 to clear pending

`endif
