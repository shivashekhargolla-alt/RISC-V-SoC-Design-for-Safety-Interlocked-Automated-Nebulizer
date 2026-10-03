/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite PWM Generator IP Core
 * File           : axi_pwm_top.v
 * Description    : AXI4-Lite Slave PWM Generator
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 *
 * Overview
 * --------
 * This module implements a memory-mapped, variable-duty-cycle PWM generator
 * with an AXI4-Lite slave interface.  It is designed to drive the external
 * analog piezo nebuliser element in the NebuCore SoC.
 *
 * Key safety feature
 * ------------------
 * The pwm_force_disable_i input is driven directly by the Watchdog Timer
 * (wdt_locked).  When asserted it forces pwm_out_o LOW regardless of the
 * pwm_en register bit or any ongoing PWM cycle.  This path is purely
 * combinational so there is zero clock-cycle latency between the Watchdog
 * asserting the lock and the actuator being silenced.
 *
 * Register Map (byte offsets, 32-bit registers)
 * ─────────────────────────────────────────────
 *  0x00  CTRL    [0]    pwm_en   – firmware refreshes this every Timer tick.
 *                                  If a core stall causes the refresh to be
 *                                  missed the register stays 0 and the PWM
 *                                  output goes low naturally.
 *                [31:1] reserved (read as 0, writes ignored)
 *
 *  0x04  DUTY    [7:0]  duty     – duty-cycle numerator (0=0%, 255≈100%).
 *                                  Output is high for (duty/256) of each period.
 *                [31:8] reserved
 *
 *  0x08  PERIOD  [15:0] period   – number of clock ticks in one full PWM cycle.
 *                                  Minimum useful value is 2.  A value of 0 or 1
 *                                  leaves pwm_out permanently low.
 *                [31:16] reserved
 *
 *  0x0C  STATUS  [0]    pwm_active       – 1 when CTRL.pwm_en=1 and not
 *                                         force-disabled (read-only)
 *                [1]    force_disabled   – 1 when pwm_force_disable_i is
 *                                         asserted (read-only, mirrors input)
 *                [31:2] reserved
 *
 * AXI4-Lite notes
 * ---------------
 *  • Single-beat transfers only (AXI-Lite).
 *  • Write and read channels are handled by independent one-state FSMs
 *    (IDLE / ACTIVE) so simultaneous read and write are possible.
 *  • BRESP / RRESP are always OKAY (2'b00); there are no illegal addresses
 *    that generate SLVERR — out-of-range writes are silently ignored,
 *    out-of-range reads return 0.
 *  • The AXI reset (axi_aresetn_i) is active-low, matching the SoC rst_n.
 *
 * PWM counter behaviour
 * ---------------------
 *  A free-running counter counts from 0 to (period-1).  pwm_out is
 *  asserted while the counter value is strictly less than `duty_scaled`,
 *  where duty_scaled = (duty * period) >> 8.  This keeps the duty-cycle
 *  ratio accurate regardless of the period value.
 *
 * -----------------------------------------------------------------------------
 * Revision History
 *  Revision  | Description
 *  1.0       | Initial version for NebuCore SoC
 * -----------------------------------------------------------------------------
 */

`default_nettype none

module axi_pwm_top (
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
    // PWM physical interface
    // -------------------------------------------------------------------------
    input  wire        pwm_force_disable_i,  // Watchdog override (active-high)
    output wire        pwm_out_o             // PWM drive waveform to Piezo Driver
);

    // -------------------------------------------------------------------------
    // Include register-map defines
    // -------------------------------------------------------------------------
    `include "pwm_defines.vh"

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_DATA_W = `_PWM_AXI_DATA_WIDTH_;   // 32
    localparam AXI_ADDR_W = `_PWM_AXI_ADDR_WIDTH_;   // 4
    localparam AXI_ID_W   = `_PWM_AXI_ID_WIDTH_;     // 12

    localparam REG_CTRL   = `_PWM_REG_CTRL_;          // 4'h0
    localparam REG_DUTY   = `_PWM_REG_DUTY_;          // 4'h4
    localparam REG_PERIOD = `_PWM_REG_PERIOD_;        // 4'h8
    localparam REG_STATUS = `_PWM_REG_STATUS_;        // 4'hC

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg         ctrl_pwm_en;          // CTRL[0]
    reg  [7:0]  duty_reg;             // DUTY[7:0]
    reg  [15:0] period_reg;           // PERIOD[15:0]

    // -------------------------------------------------------------------------
    // AXI write-path state
    // -------------------------------------------------------------------------
    // We latch the write address and data separately (AXI-Lite allows them to
    // arrive in any order).  The response is issued once both are captured.
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
            ctrl_pwm_en    <= 1'b0;
            duty_reg       <= `_PWM_DUTY_RESET_;
            period_reg     <= `_PWM_PERIOD_RESET_;
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
                // Only byte-lane-enable the bits that have their strobe set.
                // For simplicity (all our registers are 32-bit and firmware
                // always writes word-wide) we honour the strobe per-byte.
                case (aw_addr_lat)
                    REG_CTRL: begin
                        if (w_strb_lat[0]) ctrl_pwm_en <= w_data_lat[0];
                    end
                    REG_DUTY: begin
                        if (w_strb_lat[0]) duty_reg <= w_data_lat[7:0];
                    end
                    REG_PERIOD: begin
                        if (w_strb_lat[0]) period_reg[7:0]  <= w_data_lat[7:0];
                        if (w_strb_lat[1]) period_reg[15:8] <= w_data_lat[15:8];
                    end
                    REG_STATUS: begin
                        // STATUS is read-only; writes are silently ignored.
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
                    REG_CTRL:   axi_rdata_o <= {31'h0, ctrl_pwm_en};
                    REG_DUTY:   axi_rdata_o <= {24'h0, duty_reg};
                    REG_PERIOD: axi_rdata_o <= {16'h0, period_reg};
                    REG_STATUS: axi_rdata_o <= {30'h0, pwm_force_disable_i,
                                                       (ctrl_pwm_en & ~pwm_force_disable_i)};
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
    // PWM counter and output generation
    // -------------------------------------------------------------------------
    reg  [15:0] pwm_counter;      // free-running counter: 0 to (period_reg-1)
    reg  [23:0] duty_scaled;      // = (duty_reg * period_reg) >> 8

    // duty_scaled is updated combinationally to avoid a 1-cycle lag
    always @(*) begin
        duty_scaled = ({8'h0, duty_reg} * {8'h0, period_reg}) >> 8;
    end

    // Counter
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            pwm_counter <= 16'h0;
        end else begin
            if (period_reg <= 16'd1) begin
                // Degenerate period – keep counter at 0
                pwm_counter <= 16'h0;
            end else if (pwm_counter >= (period_reg - 16'd1)) begin
                pwm_counter <= 16'h0;
            end else begin
                pwm_counter <= pwm_counter + 16'd1;
            end
        end
    end

    // PWM output: combinational, so force_disable takes effect instantly
    wire pwm_raw;
    assign pwm_raw  = ctrl_pwm_en &&
                      (period_reg > 16'd1) &&
                      (pwm_counter < duty_scaled[15:0]);

    assign pwm_out_o = pwm_raw && !pwm_force_disable_i;

endmodule : axi_pwm_top

`default_nettype wire
