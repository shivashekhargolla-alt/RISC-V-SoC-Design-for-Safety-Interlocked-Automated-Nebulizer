/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite GPIO Controller IP Core
 * File           : axi_gpio_top.v
 * Description    : AXI4-Lite Slave Bidirectional 8-bit GPIO Controller
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 *
 * Overview
 * --------
 * This module implements a memory-mapped, bidirectional 8-bit GPIO controller
 * with an AXI4-Lite slave interface.  It is designed to interface with the
 * volume-selection input switches and alarm output indicator in the NebuCore SoC.
 *
 * Register Map (byte offsets, 32-bit registers)
 * ─────────────────────────────────────────────
 *  0x00  DIR   [7:0]  dir    – per-pin direction register.
 *                               1 = output (firmware drives the pin).
 *                               0 = input  (pin state sampled from gpio_pin_i).
 *                               Reset = 0x00 (all pins configured as inputs).
 *               [31:8] reserved (read as 0, writes ignored)
 *
 *  0x04  OUT   [7:0]  out    – output data register.
 *                               Value driven onto gpio_pin_o for pins where
 *                               DIR=1.  Pins with DIR=0 are forced to 0 on
 *                               gpio_pin_o regardless of this register.
 *               [31:8] reserved
 *
 *  0x08  IN    [7:0]  in     – input data register (read-only).
 *                               Always reflects the sampled value of gpio_pin_i,
 *                               regardless of pin direction.  Writes are silently
 *                               ignored.
 *               [31:8] reserved
 *
 *  0x0C  IRQ   [7:0]  irq_en – IRQ-on-change enable per input pin.
 *                               When a bit is 1, any rising or falling edge on
 *                               that input pin sets the internal irq_pending flag
 *                               and asserts gpio_irq_o.
 *                               Writing any value to this register clears all
 *                               pending IRQs (irq_pending is reset to 0).
 *               [31:8] reserved
 *
 * Physical GPIO interface
 * -----------------------
 *  gpio_pin_i[7:0]   – physical pad input (connect to pad RX path)
 *  gpio_pin_o[7:0]   – physical pad output (connect to pad TX path)
 *  gpio_pin_oe[7:0]  – output-enable per pin (high = drive the pad)
 *  gpio_irq_o        – level interrupt to the RISC-V interrupt controller
 *
 * Output logic
 * ------------
 *  gpio_pin_oe[n] = dir_reg[n]
 *  gpio_pin_o[n]  = out_reg[n] & dir_reg[n]   (inactive pins drive 0)
 *
 * IRQ behaviour
 * -------------
 *  Input pins are double-registered (two-flop synchroniser) to prevent
 *  metastability.  An edge detector compares the current and previous
 *  synchronised values.  Any edge on a pin whose irq_en bit is set latches
 *  irq_pending high.  Writing to the IRQ register (any value) clears
 *  irq_pending.  gpio_irq_o is the direct, unregistered output of irq_pending.
 *
 * AXI4-Lite notes
 * ---------------
 *  • Single-beat transfers only (AXI-Lite).
 *  • Write and read channels are handled by independent one-state FSMs
 *    (IDLE / ACTIVE) so simultaneous read and write are possible.
 *  • BRESP / RRESP are always OKAY (2'b00); out-of-range writes are silently
 *    ignored; out-of-range reads return 0.
 *  • The AXI reset (axi_aresetn_i) is active-low, matching the SoC rst_n.
 *
 * -----------------------------------------------------------------------------
 * Revision History
 *  Revision  | Description
 *  1.0       | Initial version for NebuCore SoC
 * -----------------------------------------------------------------------------
 */

`default_nettype none

module axi_gpio_top (
    // -------------------------------------------------------------------------
    // AXI4-Lite interface
    // -------------------------------------------------------------------------
    input  wire        axi_aclk_i,
    input  wire        axi_aresetn_i,   // active-low reset

    // -- Write address channel --
    input  wire [11:0] axi_awid_i,
    input  wire [3:0]  axi_awaddr_i,
    input  wire        axi_awvalid_i,
    output reg         axi_awready_o,

    // -- Write data channel --
    input  wire [31:0] axi_wdata_i,
    input  wire [3:0]  axi_wstrb_i,
    input  wire        axi_wvalid_i,
    output reg         axi_wready_o,

    // -- Write response channel --
    output reg  [11:0] axi_bid_o,
    output wire [1:0]  axi_bresp_o,
    output reg         axi_bvalid_o,
    input  wire        axi_bready_i,

    // -- Read address channel --
    input  wire [11:0] axi_arid_i,
    input  wire [3:0]  axi_araddr_i,
    input  wire        axi_arvalid_i,
    output reg         axi_arready_o,

    // -- Read data channel --
    output reg  [11:0] axi_rid_o,
    output reg  [31:0] axi_rdata_o,
    output wire [1:0]  axi_rresp_o,
    output reg         axi_rvalid_o,
    input  wire        axi_rready_i,

    // -------------------------------------------------------------------------
    // GPIO physical interface
    // -------------------------------------------------------------------------
    input  wire [7:0]  gpio_pin_i,    // physical pad inputs
    output wire [7:0]  gpio_pin_o,    // physical pad outputs
    output wire [7:0]  gpio_pin_oe,   // output-enable (high = drive pad)
    output wire        gpio_irq_o     // level interrupt to RISC-V PLIC/PIC
);

    // -------------------------------------------------------------------------
    // Include register-map defines
    // -------------------------------------------------------------------------
    `include "gpio_defines.vh"

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_DATA_W = `_GPIO_AXI_DATA_WIDTH_;   // 32
    localparam AXI_ADDR_W = `_GPIO_AXI_ADDR_WIDTH_;   // 4
    localparam AXI_ID_W   = `_GPIO_AXI_ID_WIDTH_;     // 12

    localparam REG_DIR = `_GPIO_REG_DIR_;   // 4'h0
    localparam REG_OUT = `_GPIO_REG_OUT_;   // 4'h4
    localparam REG_IN  = `_GPIO_REG_IN_;    // 4'h8
    localparam REG_IRQ = `_GPIO_REG_IRQ_;   // 4'hC

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [7:0] dir_reg;     // DIR[7:0] — per-pin direction (1=output)
    reg [7:0] out_reg;     // OUT[7:0] — firmware-driven output value
    reg [7:0] irq_en_reg;  // IRQ[7:0] — per-pin IRQ-on-change enable

    // -------------------------------------------------------------------------
    // Input synchroniser (two-flop metastability guard)
    // -------------------------------------------------------------------------
    reg [7:0] gpio_sync1;   // first  synchroniser stage
    reg [7:0] gpio_sync2;   // second synchroniser stage (stable)
    reg [7:0] gpio_prev;    // previous stable value (for edge detection)

    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            gpio_sync1 <= 8'h00;
            gpio_sync2 <= 8'h00;
            gpio_prev  <= 8'h00;
        end else begin
            gpio_sync1 <= gpio_pin_i;
            gpio_sync2 <= gpio_sync1;
            gpio_prev  <= gpio_sync2;
        end
    end

    // -------------------------------------------------------------------------
    // IRQ edge detection and pending latch
    // -------------------------------------------------------------------------
    wire [7:0] pin_edge;        // any edge (rising or falling) per pin
    reg        irq_pending;     // set on any enabled edge, cleared by IRQ write
    wire       irq_clear;       // pulsed for one cycle when IRQ reg is written

    assign pin_edge = gpio_sync2 ^ gpio_prev;   // bits where level changed

    // irq_clear is generated inside the write FSM (see below)
    reg irq_clear_r;

    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            irq_pending <= 1'b0;
        end else begin
            if (irq_clear_r) begin
                // Firmware wrote to IRQ register — clear all pending IRQs.
                irq_pending <= 1'b0;
            end else if (|(pin_edge & irq_en_reg & ~dir_reg)) begin
                // Edge detected on at least one IRQ-enabled input pin.
                irq_pending <= 1'b1;
            end
        end
    end

    assign gpio_irq_o = irq_pending;

    // -------------------------------------------------------------------------
    // AXI write-path state
    // -------------------------------------------------------------------------
    // Address and data channels are latched independently; response is issued
    // once both have been accepted — identical pattern to axi_pwm_top.v.
    reg        aw_active;       // write-address handshake done
    reg        w_active;        // write-data  handshake done
    reg [3:0]  aw_addr_lat;     // latched write address
    reg [11:0] aw_id_lat;       // latched write ID
    reg [31:0] w_data_lat;      // latched write data
    reg [3:0]  w_strb_lat;      // latched write strobe

    // -------------------------------------------------------------------------
    // AXI write FSM
    // -------------------------------------------------------------------------
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            aw_active      <= 1'b0;
            w_active       <= 1'b0;
            aw_addr_lat    <= 4'h0;
            aw_id_lat      <= 12'h0;
            w_data_lat     <= 32'h0;
            w_strb_lat     <= 4'h0;
            axi_awready_o  <= 1'b1;   // ready from reset
            axi_wready_o   <= 1'b1;
            axi_bvalid_o   <= 1'b0;
            axi_bid_o      <= 12'h0;
            dir_reg        <= 8'h00;  // all inputs at reset
            out_reg        <= 8'h00;
            irq_en_reg     <= 8'h00;
            irq_clear_r    <= 1'b0;
        end else begin
            // Default: clear the irq_clear pulse every cycle
            irq_clear_r <= 1'b0;

            // ── Accept write address ──────────────────────────────────────────
            if (axi_awvalid_i && axi_awready_o) begin
                aw_addr_lat   <= axi_awaddr_i;
                aw_id_lat     <= axi_awid_i;
                aw_active     <= 1'b1;
                axi_awready_o <= 1'b0;   // de-assert until response is done
            end

            // ── Accept write data ─────────────────────────────────────────────
            if (axi_wvalid_i && axi_wready_o) begin
                w_data_lat   <= axi_wdata_i;
                w_strb_lat   <= axi_wstrb_i;
                w_active     <= 1'b1;
                axi_wready_o <= 1'b0;
            end

            // ── Perform register write once both address and data are captured ─
            if (aw_active && w_active && !axi_bvalid_o) begin
                case (aw_addr_lat)
                    REG_DIR: begin
                        if (w_strb_lat[0]) dir_reg <= w_data_lat[7:0];
                    end
                    REG_OUT: begin
                        if (w_strb_lat[0]) out_reg <= w_data_lat[7:0];
                    end
                    REG_IN: begin
                        // IN is read-only; writes are silently ignored.
                    end
                    REG_IRQ: begin
                        // Writing any value to IRQ register:
                        //   1. Updates the irq_en field (strobe-guarded).
                        //   2. Pulses irq_clear to clear all pending IRQs.
                        if (w_strb_lat[0]) irq_en_reg <= w_data_lat[7:0];
                        irq_clear_r <= 1'b1;
                    end
                    default: begin
                        // Unmapped address – ignore.
                    end
                endcase

                // Issue write response
                axi_bid_o    <= aw_id_lat;
                axi_bvalid_o <= 1'b1;
                aw_active    <= 1'b0;
                w_active     <= 1'b0;
            end

            // ── Clear response once accepted ───────────────────────────────────
            if (axi_bvalid_o && axi_bready_i) begin
                axi_bvalid_o  <= 1'b0;
                axi_awready_o <= 1'b1;   // ready for next transaction
                axi_wready_o  <= 1'b1;
            end
        end
    end

    // BRESP is always OKAY
    assign axi_bresp_o = 2'b00;

    // -------------------------------------------------------------------------
    // AXI read FSM
    // -------------------------------------------------------------------------
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            axi_arready_o <= 1'b1;
            axi_rvalid_o  <= 1'b0;
            axi_rid_o     <= 12'h0;
            axi_rdata_o   <= 32'h0;
        end else begin
            if (axi_arvalid_i && axi_arready_o) begin
                // Latch ID and present read data in the same cycle
                axi_rid_o     <= axi_arid_i;
                axi_rvalid_o  <= 1'b1;
                axi_arready_o <= 1'b0;

                // Register read decode
                case (axi_araddr_i)
                    REG_DIR: axi_rdata_o <= {24'h0, dir_reg};
                    REG_OUT: axi_rdata_o <= {24'h0, out_reg};
                    REG_IN:  axi_rdata_o <= {24'h0, gpio_sync2};
                    REG_IRQ: axi_rdata_o <= {24'h0, irq_en_reg};
                    default: axi_rdata_o <= 32'h0;
                endcase
            end

            if (axi_rvalid_o && axi_rready_i) begin
                axi_rvalid_o  <= 1'b0;
                axi_arready_o <= 1'b1;
            end
        end
    end

    // RRESP is always OKAY
    assign axi_rresp_o = 2'b00;

    // -------------------------------------------------------------------------
    // GPIO output drive
    // -------------------------------------------------------------------------
    // Output-enable mirrors the direction register: a pin configured as output
    // (DIR=1) drives its pad; input pins tri-state.
    assign gpio_pin_oe = dir_reg;

    // Output data: only drive value for output-configured pins; input pins
    // are forced to 0 to avoid contention.
    assign gpio_pin_o  = out_reg & dir_reg;

endmodule : axi_gpio_top

`default_nettype wire
