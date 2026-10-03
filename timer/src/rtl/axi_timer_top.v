/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Countdown Timer IP Core
 * File           : axi_timer_top.v
 * Description    : AXI4-Lite Slave Countdown Timer
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 *
 * Overview
 * --------
 * This module implements a memory-mapped, second-resolution countdown timer
 * with an AXI4-Lite slave interface.  It is designed to enforce the treatment
 * duration in the NebuCore SoC: firmware loads the dose time (in seconds),
 * enables the timer, and when COUNT reaches zero the timer asserts
 * timer_done_o to trigger the Watchdog and timer_irq_o to interrupt the CPU.
 *
 * Operation
 * ---------
 *  1. Firmware writes the desired duration to LOAD (in seconds) — this also
 *     reloads COUNT and clears the done/irq_pending flags.
 *  2. Firmware sets CTRL[0]=1 (timer_en) and optionally CTRL[1]=1 (irq_en).
 *  3. An internal 32-bit prescaler divides the 100 MHz clock down to a 1 Hz
 *     tick.  On each tick, COUNT is decremented by 1 while COUNT > 0.
 *  4. When COUNT hits 0: done=1 is latched, timer_done_o is asserted
 *     (combinational), and timer_irq_o is asserted if irq_en=1.
 *  5. Firmware clears the interrupt by writing 1 to STATUS[0] (W1C).
 *  6. Writing LOAD again at any time reloads and restarts the countdown.
 *
 * Register Map (byte offsets, 32-bit registers)
 * ─────────────────────────────────────────────
 *  0x00  CTRL    [0]    timer_en  – enable countdown; de-asserting freezes COUNT
 *                [1]    irq_en    – allow timer_irq_o to be asserted on done
 *                [31:2] reserved (read as 0, writes ignored)
 *
 *  0x04  LOAD    [15:0] load      – countdown initial value in seconds.
 *                                   Writing this register immediately reloads
 *                                   COUNT and clears done and irq_pending.
 *                [31:16] reserved
 *
 *  0x08  COUNT   [15:0] count     – current countdown value (read-only).
 *                                   Decremented by 1 each second when timer_en=1
 *                                   and COUNT > 0.
 *                [31:16] reserved
 *
 *  0x0C  STATUS  [0]    irq_pending – set when COUNT hits 0 and irq_en=1.
 *                                     Write 1 to clear (W1C).
 *                [1]    done        – set when COUNT hits 0 (read-only).
 *                                     Cleared on next LOAD write.
 *                [31:2] reserved
 *
 * Non-AXI outputs
 * ───────────────
 *  timer_irq_o  → RISC-V VeeR EL2 PIC (external interrupt).
 *  timer_done_o → Watchdog Timer wdt_trigger input (combinational).
 *
 * AXI4-Lite notes
 * ---------------
 *  • Single-beat transfers only (AXI-Lite).
 *  • Write and read channels are handled by independent one-state FSMs
 *    (IDLE / ACTIVE) so simultaneous read and write are possible.
 *  • BRESP / RRESP are always OKAY (2'b00); out-of-range writes are silently
 *    ignored, out-of-range reads return 0.
 *  • The AXI reset (axi_aresetn_i) is active-low, matching the SoC rst_n.
 *
 * -----------------------------------------------------------------------------
 * Revision History
 *  Revision  | Description
 *  1.0       | Initial version for NebuCore SoC
 * -----------------------------------------------------------------------------
 */

`default_nettype none

module axi_timer_top (
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
    // Timer functional interface
    // -------------------------------------------------------------------------
    output wire        timer_irq_o,     // to RISC-V VeeR EL2 PIC
    output wire        timer_done_o     // to Watchdog wdt_trigger (combinational)
);

    // -------------------------------------------------------------------------
    // Include register-map defines
    // -------------------------------------------------------------------------
    `include "timer_defines.vh"

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_DATA_W    = `_TIMER_AXI_DATA_WIDTH_;  // 32
    localparam AXI_ADDR_W    = `_TIMER_AXI_ADDR_WIDTH_;  // 4
    localparam AXI_ID_W      = `_TIMER_AXI_ID_WIDTH_;    // 12

    localparam REG_CTRL      = `_TIMER_REG_CTRL_;        // 4'h0
    localparam REG_LOAD      = `_TIMER_REG_LOAD_;        // 4'h4
    localparam REG_COUNT     = `_TIMER_REG_COUNT_;       // 4'h8
    localparam REG_STATUS    = `_TIMER_REG_STATUS_;      // 4'hC

    localparam PRESCALER_MAX = `_TIMER_PRESCALER_;       // 100_000_000

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg         ctrl_timer_en;       // CTRL[0]
    reg         ctrl_irq_en;         // CTRL[1]
    reg  [15:0] load_reg;            // LOAD[15:0]
    reg  [15:0] count_reg;           // COUNT[15:0]  (live countdown)
    reg         irq_pending;         // STATUS[0]    (W1C)
    reg         done_reg;            // STATUS[1]

    // -------------------------------------------------------------------------
    // Prescaler
    // -------------------------------------------------------------------------
    reg  [31:0] prescaler;           // counts PRESCALER_MAX-1 down to 0
    wire        tick;                // 1-cycle pulse once per second

    assign tick = (prescaler == 32'd0);

    // -------------------------------------------------------------------------
    // AXI write-path state
    // -------------------------------------------------------------------------
    reg         aw_active;       // write-address handshake done
    reg         w_active;        // write-data  handshake done
    reg  [3:0]  aw_addr_lat;     // latched write address
    reg  [11:0] aw_id_lat;       // latched write ID
    reg  [31:0] w_data_lat;      // latched write data
    reg  [3:0]  w_strb_lat;      // latched write strobe

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
            ctrl_timer_en  <= 1'b0;
            ctrl_irq_en    <= 1'b0;
            load_reg       <= 16'h0;
            count_reg      <= 16'h0;
            irq_pending    <= 1'b0;
            done_reg       <= 1'b0;
        end else begin
            // ── Accept write address ──────────────────────────────────────────
            if (axi_awvalid_i && axi_awready_o) begin
                aw_addr_lat   <= axi_awaddr_i;
                aw_id_lat     <= axi_awid_i;
                aw_active     <= 1'b1;
                axi_awready_o <= 1'b0;  // de-assert until response is done
            end

            // ── Accept write data ─────────────────────────────────────────────
            if (axi_wvalid_i && axi_wready_o) begin
                w_data_lat    <= axi_wdata_i;
                w_strb_lat    <= axi_wstrb_i;
                w_active      <= 1'b1;
                axi_wready_o  <= 1'b0;
            end

            // ── Perform register write once both address and data are captured ─
            if (aw_active && w_active && !axi_bvalid_o) begin
                case (aw_addr_lat)
                    REG_CTRL: begin
                        if (w_strb_lat[0]) begin
                            ctrl_timer_en <= w_data_lat[0];
                            ctrl_irq_en   <= w_data_lat[1];
                        end
                    end
                    REG_LOAD: begin
                        // Writing LOAD reloads COUNT and clears status flags.
                        // Build the full new value from the byte strobes and
                        // update load_reg, count_reg, and status atomically.
                        if (w_strb_lat[0]) load_reg[7:0]  <= w_data_lat[7:0];
                        if (w_strb_lat[1]) load_reg[15:8] <= w_data_lat[15:8];
                        count_reg   <= {(w_strb_lat[1] ? w_data_lat[15:8] : load_reg[15:8]),
                                        (w_strb_lat[0] ? w_data_lat[7:0]  : load_reg[7:0])};
                        done_reg    <= 1'b0;
                        irq_pending <= 1'b0;
                    end
                    REG_COUNT: begin
                        // COUNT is read-only; writes are silently ignored.
                    end
                    REG_STATUS: begin
                        // STATUS[0] = irq_pending is W1C; [1] = done is read-only.
                        if (w_strb_lat[0] && w_data_lat[0]) irq_pending <= 1'b0;
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

            // ── Timer countdown logic ──────────────────────────────────────────
            // Prescaler: free-runs from PRESCALER_MAX-1 down to 0 then reloads.
            if (prescaler == 32'd0) begin
                prescaler <= PRESCALER_MAX - 32'd1;
            end else begin
                prescaler <= prescaler - 32'd1;
            end

            // On each 1-second tick, decrement count if timer is enabled and
            // not yet done.
            if (tick && ctrl_timer_en && (count_reg > 16'd0)) begin
                count_reg <= count_reg - 16'd1;
            end

            // Reload COUNT when LOAD is written (handled inside the REG_LOAD
            // case above via count_reg <= ... so no duplicate assignment here).

            // Latch done and irq_pending when count reaches 0 on a tick.
            // We detect the final step by checking count_reg == 1 because the
            // decrement to 0 happens in the same clock edge.
            if (tick && ctrl_timer_en && (count_reg == 16'd1)) begin
                done_reg    <= 1'b1;
                if (ctrl_irq_en) irq_pending <= 1'b1;
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
                    REG_CTRL:   axi_rdata_o <= {30'h0, ctrl_irq_en, ctrl_timer_en};
                    REG_LOAD:   axi_rdata_o <= {16'h0, load_reg};
                    REG_COUNT:  axi_rdata_o <= {16'h0, count_reg};
                    REG_STATUS: axi_rdata_o <= {30'h0, done_reg, irq_pending};
                    default:    axi_rdata_o <= 32'h0;
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
    // Non-AXI output assignments (combinational)
    // -------------------------------------------------------------------------
    // timer_done_o is a combinational feed to the Watchdog wdt_trigger so the
    // Watchdog locks the actuator with zero clock-cycle latency.
    assign timer_done_o = done_reg;

    // timer_irq_o stays asserted until firmware clears irq_pending via W1C.
    assign timer_irq_o  = irq_pending;

endmodule : axi_timer_top

`default_nettype wire
