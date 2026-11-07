/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Watchdog Timer (Safety Interlock) IP Core
 * File           : axi_wdt_top.v
 * Description    : AXI4-Lite Slave Watchdog Timer — NebuCore Safety Interlock
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 *
 * Overview
 * --------
 * This module implements the hardware safety interlock for the NebuCore SoC.
 * Its primary purpose is to guarantee that the piezoelectric nebulising element
 * CANNOT remain active after a dose is complete or after a firmware fault.
 *
 * The central safety element is wdt_locked — a SET-ONLY flip-flop that:
 *   • Can ONLY be CLEARED by hardware reset (rst_n = 0).
 *   • Can ONLY be SET by a hardware event (wdt_trigger_i or stall timeout).
 *   • CANNOT be cleared by any AXI register write whatsoever.
 *
 * When wdt_locked is set it drives wdt_locked_o HIGH, which connects directly
 * to pwm_force_disable_i in the PWM Generator.  That path is purely
 * combinational — there is zero clock-cycle latency between the watchdog
 * locking and the actuator being silenced.
 *
 * Safety architecture summary
 * ---------------------------
 *
 *   Two independent lock sources (OR'd together):
 *
 *   1. External trigger  (wdt_trigger_i)
 *      The Timer IP asserts this when the prescribed treatment duration expires.
 *      Asserting it for even one clock edge permanently sets wdt_locked.
 *
 *   2. Stall detection   (internal)
 *      When wdt_en (CTRL[0]) is set, a 32-bit prescaler divides the 100 MHz
 *      system clock down to 1-second ticks.  A 16-bit stall_counter increments
 *      every second.  If stall_counter reaches the value in the WINDOW register
 *      without firmware writing to KICK, stall_detected is latched and
 *      wdt_locked is set.  This catches firmware hangs that would otherwise
 *      leave the actuator running indefinitely.
 *
 *   Lock propagation:
 *
 *     wdt_locked_o  ──►  pwm_force_disable_i  (forces pwm_out LOW, comb.)
 *     alarm_out_o   ──►  alarm LED / buzzer    (combinational copy)
 *     wdt_irq_o     ──►  RISC-V interrupt      (wdt_locked AND irq_en)
 *
 *   STATUS register [0] mirrors wdt_locked in read-only silicon.  Firmware
 *   can detect the lock condition and log it, but cannot undo it.
 *
 * Register Map (byte offsets, 32-bit registers)
 * ─────────────────────────────────────────────
 *  0x00  CTRL    [0]    wdt_en   – enables stall-detection counter.
 *                                  Clear to disable stall detection (trigger
 *                                  path is always active regardless of wdt_en).
 *                [1]    irq_en   – enables the wdt_irq_o output.
 *                [31:2] reserved (read as 0, writes ignored)
 *
 *  0x04  WINDOW  [15:0] window   – stall-detection window in whole seconds.
 *                                  Default 5.  A value of 0 disables stall
 *                                  detection even if wdt_en=1.
 *                [31:16] reserved
 *
 *  0x08  KICK    [31:0] (write-only) – writing any value resets the stall
 *                                      counter to zero (firmware heartbeat).
 *                                      Reading returns 0x00000000.
 *
 *  0x0C  STATUS  [0]    wdt_locked       – 1 once locked (read-only, SET-ONLY)
 *                [1]    stall_detected   – 1 if stall timeout triggered the
 *                                         lock (read-only)
 *                [31:2] reserved
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

module axi_wdt_top (
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
    // WDT non-AXI interface
    // -------------------------------------------------------------------------
    input  wire        wdt_trigger_i,   // External lock trigger (e.g. timer_done_o)
                                        // — one clock high permanently sets wdt_locked
    output wire        wdt_locked_o,    // Safety lock (drives pwm_force_disable_i)
    output wire        wdt_irq_o,       // Status IRQ to RISC-V (level, active-high)
    output wire        alarm_out_o      // Alarm LED / buzzer drive (comb. copy of lock)
);

    // -------------------------------------------------------------------------
    // Include register-map defines
    // -------------------------------------------------------------------------
    `include "wdt_defines.vh"

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_DATA_W = `_WDT_AXI_DATA_WIDTH_;   // 32
    localparam AXI_ADDR_W = `_WDT_AXI_ADDR_WIDTH_;   // 4
    localparam AXI_ID_W   = `_WDT_AXI_ID_WIDTH_;     // 12

    localparam REG_CTRL   = `_WDT_REG_CTRL_;          // 4'h0
    localparam REG_WINDOW = `_WDT_REG_WINDOW_;        // 4'h4
    localparam REG_KICK   = `_WDT_REG_KICK_;          // 4'h8
    localparam REG_STATUS = `_WDT_REG_STATUS_;        // 4'hC

    // -------------------------------------------------------------------------
    // Registers (firmware-visible)
    // -------------------------------------------------------------------------
    reg         ctrl_wdt_en;           // CTRL[0]  — enables stall detection
    reg         ctrl_irq_en;           // CTRL[1]  — enables IRQ output
    reg  [15:0] window_reg;            // WINDOW[15:0] — stall window in seconds

    // -------------------------------------------------------------------------
    // Safety-critical state (SET-ONLY flip-flops)
    // -------------------------------------------------------------------------
    // IMPORTANT: wdt_locked may ONLY be set, never cleared by firmware.
    // The only clear path is hardware reset (axi_aresetn_i = 0).
    // stall_detected likewise latches permanently once set.
    reg         wdt_locked;            // STATUS[0] — master safety lock
    reg         stall_detected;        // STATUS[1] — stall caused the lock

    // -------------------------------------------------------------------------
    // Stall-detection internals
    // -------------------------------------------------------------------------
    reg  [31:0] prescaler_cnt;         // counts to _WDT_PRESCALER_ for 1 s tick
    reg  [15:0] stall_counter;         // counts elapsed seconds without a KICK
    reg         tick_1s;               // single-cycle 1-second pulse
    reg         kick_pulse;            // single-cycle strobe on KICK write

    // -------------------------------------------------------------------------
    // AXI write-path latches
    // -------------------------------------------------------------------------
    reg         aw_active;
    reg         w_active;
    reg  [3:0]  aw_addr_lat;
    reg  [11:0] aw_id_lat;
    reg  [31:0] w_data_lat;
    reg  [3:0]  w_strb_lat;

    // =========================================================================
    // AXI write FSM
    // Mirrors axi_pwm_top.v: latch AW and W independently; issue B once both
    // are captured.
    // =========================================================================
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
            ctrl_wdt_en    <= 1'b0;
            ctrl_irq_en    <= 1'b0;
            window_reg     <= `_WDT_WINDOW_RESET_;
            kick_pulse     <= 1'b0;
        end else begin
            kick_pulse <= 1'b0;   // default: no kick this cycle

            // ── Accept write address ──────────────────────────────────────────
            if (axi_awvalid_i && axi_awready_o) begin
                aw_addr_lat   <= axi_awaddr_i;
                aw_id_lat     <= axi_awid_i;
                aw_active     <= 1'b1;
                axi_awready_o <= 1'b0;
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
                            ctrl_wdt_en <= w_data_lat[0];
                            ctrl_irq_en <= w_data_lat[1];
                        end
                    end
                    REG_WINDOW: begin
                        if (w_strb_lat[0]) window_reg[7:0]  <= w_data_lat[7:0];
                        if (w_strb_lat[1]) window_reg[15:8] <= w_data_lat[15:8];
                    end
                    REG_KICK: begin
                        // Writing any value kicks the watchdog (any strobe).
                        // The kick_pulse is consumed by the stall-detection logic.
                        kick_pulse <= (|w_strb_lat);
                    end
                    REG_STATUS: begin
                        // STATUS is read-only; writes are silently ignored.
                        // Attempting to write wdt_locked has no effect —
                        // the safety guarantee is enforced in its own always block.
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

    // =========================================================================
    // AXI read FSM
    // =========================================================================
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            axi_arready_o <= 1'b1;
            axi_rvalid_o  <= 1'b0;
            axi_rid_o     <= 12'h0;
            axi_rdata_o   <= 32'h0;
        end else begin
            if (axi_arvalid_i && axi_arready_o) begin
                axi_rid_o     <= axi_arid_i;
                axi_rvalid_o  <= 1'b1;
                axi_arready_o <= 1'b0;

                case (axi_araddr_i)
                    REG_CTRL:   axi_rdata_o <= {30'h0, ctrl_irq_en, ctrl_wdt_en};
                    REG_WINDOW: axi_rdata_o <= {16'h0, window_reg};
                    REG_KICK:   axi_rdata_o <= 32'h0;   // KICK is write-only; read as 0
                    REG_STATUS: axi_rdata_o <= {30'h0, stall_detected, wdt_locked};
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

    // =========================================================================
    // 1-second tick prescaler
    // Counts from 0 to (_WDT_PRESCALER_ - 1) then pulses tick_1s for one cycle.
    // =========================================================================
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            prescaler_cnt <= 32'h0;
            tick_1s       <= 1'b0;
        end else begin
            if (prescaler_cnt >= (`_WDT_PRESCALER_ - 32'd1)) begin
                prescaler_cnt <= 32'h0;
                tick_1s       <= 1'b1;
            end else begin
                prescaler_cnt <= prescaler_cnt + 32'd1;
                tick_1s       <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Stall counter
    // Increments every second when wdt_en=1.  Reset to 0 on a KICK write or
    // on hardware reset.  Stops incrementing once wdt_locked is set (no point
    // continuing after the lock has been applied).
    // =========================================================================
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            stall_counter <= 16'h0;
        end else begin
            if (kick_pulse || !ctrl_wdt_en || wdt_locked) begin
                // Firmware kicked, stall detection disabled, or already locked:
                // reset the stall counter.
                stall_counter <= 16'h0;
            end else if (tick_1s) begin
                // Count up, saturate at max to avoid wrap-around
                if (stall_counter < 16'hFFFF)
                    stall_counter <= stall_counter + 16'd1;
            end
        end
    end

    // =========================================================================
    // Lock condition — combinational
    // True whenever either trigger source fires.
    // =========================================================================
    wire stall_expired;
    assign stall_expired = ctrl_wdt_en &&
                           (window_reg != 16'h0) &&
                           (stall_counter >= window_reg);

    wire lock_condition;
    assign lock_condition = wdt_trigger_i || stall_expired;

    // =========================================================================
    // wdt_locked — SAFETY-CRITICAL SET-ONLY FLIP-FLOP
    //
    // ONLY rst_n can clear this register.  No AXI write path touches it.
    // The always block deliberately has no `else` branch after the set
    // so that once wdt_locked = 1 it NEVER returns to 0 while the SoC
    // is powered (only hardware reset can clear it).
    // =========================================================================
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i)
            wdt_locked <= 1'b0;
        else if (lock_condition)
            wdt_locked <= 1'b1;
        // NO else: omitting the else branch is intentional.
        // A locked state cannot be overwritten by any other condition.
    end

    // =========================================================================
    // stall_detected — SET-ONLY, latches when stall (not trigger) causes lock
    // =========================================================================
    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i)
            stall_detected <= 1'b0;
        else if (stall_expired)
            stall_detected <= 1'b1;
        // NO else: same safety pattern as wdt_locked.
    end

    // =========================================================================
    // Output assignments — all combinational
    // =========================================================================

    // Safety lock output — drives pwm_force_disable_i directly (zero-latency)
    assign wdt_locked_o = wdt_locked;

    // IRQ to RISC-V — level-sensitive, active-high, gated by irq_en
    assign wdt_irq_o    = wdt_locked & ctrl_irq_en;

    // Alarm output — combinational copy of the lock (drives LED/buzzer)
    assign alarm_out_o  = wdt_locked;

endmodule : axi_wdt_top

`default_nettype wire
