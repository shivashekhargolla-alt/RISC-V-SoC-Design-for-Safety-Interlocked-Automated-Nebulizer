/* -----------------------------------------------------------------------------
 * Project        : AXI-Lite Seven-Segment Display Controller IP Core
 * File           : axi_seg7_top.v
 * Description    : AXI4-Lite Slave Seven-Segment Display Controller (4 digits)
 * Part of        : NebuCore SoC (nebulizer dosage-control system)
 * -----------------------------------------------------------------------------
 *
 * Overview
 * --------
 * This module implements a memory-mapped, 4-digit seven-segment display
 * controller with an AXI4-Lite slave interface.  It is intended to drive the
 * front-panel numeric display in the NebuCore SoC, showing the current dose
 * volume or treatment countdown.
 *
 * Display multiplexing
 * --------------------
 * A hardware time-division multiplexer cycles through the four digit positions
 * (digit0 = rightmost, digit3 = leftmost) at approximately 4 ms per digit
 * (250 Hz refresh), giving a flicker-free appearance at 100 MHz system clock.
 * Only one digit_sel_o bit is asserted at a time (one-hot).
 *
 * 7-segment LUT
 * -------------
 * A 16-entry look-up table converts each 4-bit hex nibble from the DATA
 * register to a 7-bit active-high segment pattern {g,f,e,d,c,b,a}.
 *
 * Blink mode
 * ----------
 * When CTRL.blink_en is set, a 500 ms half-period counter toggles a blink
 * gate that blanks all segments every other 500 ms interval.
 *
 * Brightness
 * ----------
 * The BRIGHT register [3:0] is stored for future use (e.g. by an external
 * PWM-dimmer stage).  It does not modify the segment drive lines directly.
 *
 * Register Map (byte offsets, 32-bit registers)
 * ─────────────────────────────────────────────
 *  0x00  DATA    [3:0]   digit0  – rightmost digit (hex 0–F)
 *                [7:4]   digit1
 *                [11:8]  digit2
 *                [15:12] digit3  – leftmost digit
 *                [31:16] reserved (read as 0, writes ignored)
 *
 *  0x04  CTRL    [0]     disp_en  – 1 = display active, 0 = all segments off
 *                [1]     blink_en – 1 = blink at ~1 Hz
 *                [31:2]  reserved
 *
 *  0x08  STATUS  [3:0]   mux_idx  – current active digit (0–3), read-only
 *                [31:4]  reserved
 *
 *  0x0C  BRIGHT  [3:0]   brightness level (0=off, 15=max), for future PWM use
 *                [31:4]  reserved
 *
 * AXI4-Lite notes
 * ---------------
 *  • Single-beat transfers only (AXI-Lite).
 *  • Write and read channels use independent one-state FSMs (same pattern as
 *    axi_pwm_top.v) so simultaneous read and write are possible.
 *  • BRESP / RRESP are always OKAY (2'b00).
 *  • Out-of-range writes are silently ignored; out-of-range reads return 0.
 *  • axi_aresetn_i is active-low, matching the SoC rst_n.
 *
 * -----------------------------------------------------------------------------
 * Revision History
 *  Revision  | Description
 *  1.0       | Initial version for NebuCore SoC
 * -----------------------------------------------------------------------------
 */

`default_nettype none

module axi_seg7_top (
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
    // Seven-segment display physical interface
    // -------------------------------------------------------------------------
    output wire [6:0]  seg_out_o,      // segment lines {g,f,e,d,c,b,a}, active-high
    output wire [3:0]  digit_sel_o     // one-hot digit select (digit3..digit0)
);

    // -------------------------------------------------------------------------
    // Include register-map defines
    // -------------------------------------------------------------------------
    `include "seg7_defines.vh"

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam AXI_DATA_W  = `_SEG7_AXI_DATA_WIDTH_;   // 32
    localparam AXI_ADDR_W  = `_SEG7_AXI_ADDR_WIDTH_;   //  4
    localparam AXI_ID_W    = `_SEG7_AXI_ID_WIDTH_;     // 12

    localparam REG_DATA    = `_SEG7_REG_DATA_;           // 4'h0
    localparam REG_CTRL    = `_SEG7_REG_CTRL_;           // 4'h4
    localparam REG_STATUS  = `_SEG7_REG_STATUS_;         // 4'h8
    localparam REG_BRIGHT  = `_SEG7_REG_BRIGHT_;         // 4'hC

    localparam MUX_MAX     = 20'd400_000 - 20'd1;        // 4 ms per digit @ 100 MHz
    localparam BLINK_MAX   = 26'd50_000_000 - 26'd1;     // 500 ms half-period

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg  [15:0] data_reg;             // DATA[15:0]  — four packed BCD nibbles
    reg         ctrl_disp_en;         // CTRL[0]
    reg         ctrl_blink_en;        // CTRL[1]
    reg  [3:0]  bright_reg;           // BRIGHT[3:0]

    // -------------------------------------------------------------------------
    // AXI write-path state
    // (Same latch-then-commit pattern as axi_pwm_top.v)
    // -------------------------------------------------------------------------
    reg         aw_active;
    reg         w_active;
    reg  [3:0]  aw_addr_lat;
    reg  [11:0] aw_id_lat;
    reg  [31:0] w_data_lat;
    reg  [3:0]  w_strb_lat;

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
            data_reg       <= `_SEG7_DATA_RESET_;
            ctrl_disp_en   <= 1'b0;
            ctrl_blink_en  <= 1'b0;
            bright_reg     <= `_SEG7_BRIGHT_RESET_;
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
                w_data_lat   <= axi_wdata_i;
                w_strb_lat   <= axi_wstrb_i;
                w_active     <= 1'b1;
                axi_wready_o <= 1'b0;
            end

            // ── Perform register write once both address and data are captured ─
            if (aw_active && w_active && !axi_bvalid_o) begin
                case (aw_addr_lat)
                    REG_DATA: begin
                        if (w_strb_lat[0]) data_reg[7:0]  <= w_data_lat[7:0];
                        if (w_strb_lat[1]) data_reg[15:8] <= w_data_lat[15:8];
                        // [31:16] reserved — writes ignored
                    end
                    REG_CTRL: begin
                        if (w_strb_lat[0]) begin
                            ctrl_disp_en  <= w_data_lat[0];
                            ctrl_blink_en <= w_data_lat[1];
                        end
                    end
                    REG_STATUS: begin
                        // STATUS is read-only; writes are silently ignored.
                    end
                    REG_BRIGHT: begin
                        if (w_strb_lat[0]) bright_reg <= w_data_lat[3:0];
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
                axi_rid_o     <= axi_arid_i;
                axi_rvalid_o  <= 1'b1;
                axi_arready_o <= 1'b0;

                case (axi_araddr_i)
                    REG_DATA:   axi_rdata_o <= {16'h0, data_reg};
                    REG_CTRL:   axi_rdata_o <= {30'h0, ctrl_blink_en, ctrl_disp_en};
                    REG_STATUS: axi_rdata_o <= {28'h0, mux_idx};
                    REG_BRIGHT: axi_rdata_o <= {28'h0, bright_reg};
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
    // Display multiplexer — prescaler and 2-bit digit index
    // -------------------------------------------------------------------------
    reg  [19:0] mux_prescaler;    // counts 0 to MUX_MAX (400,000-1)
    reg  [1:0]  mux_idx;          // current digit index 0–3

    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            mux_prescaler <= 20'd0;
            mux_idx       <= 2'd0;
        end else begin
            if (mux_prescaler >= MUX_MAX) begin
                mux_prescaler <= 20'd0;
                mux_idx       <= mux_idx + 2'd1;  // wraps 3→0 automatically
            end else begin
                mux_prescaler <= mux_prescaler + 20'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Blink counter (~500 ms half-period)
    // -------------------------------------------------------------------------
    reg  [25:0] blink_counter;
    reg         blink_gate;       // 0 = blanked, 1 = visible

    always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
        if (!axi_aresetn_i) begin
            blink_counter <= 26'd0;
            blink_gate    <= 1'b1;
        end else begin
            if (ctrl_blink_en) begin
                if (blink_counter >= BLINK_MAX) begin
                    blink_counter <= 26'd0;
                    blink_gate    <= ~blink_gate;
                end else begin
                    blink_counter <= blink_counter + 26'd1;
                end
            end else begin
                // Not blinking — keep gate open and reset counter so blink
                // starts from a clean state if re-enabled later.
                blink_counter <= 26'd0;
                blink_gate    <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Current digit nibble (selected by mux_idx)
    // -------------------------------------------------------------------------
    reg [3:0] current_nibble;

    always @(*) begin
        case (mux_idx)
            2'd0: current_nibble = data_reg[3:0];    // digit0 (rightmost)
            2'd1: current_nibble = data_reg[7:4];    // digit1
            2'd2: current_nibble = data_reg[11:8];   // digit2
            2'd3: current_nibble = data_reg[15:12];  // digit3 (leftmost)
            default: current_nibble = 4'h0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 7-Segment LUT — 16 entries, {g,f,e,d,c,b,a} active-high
    // -------------------------------------------------------------------------
    reg [6:0] seg_lut;

    always @(*) begin
        case (current_nibble)
            4'h0: seg_lut = 7'h3F;  // 0  — 0b0111111
            4'h1: seg_lut = 7'h06;  // 1  — 0b0000110
            4'h2: seg_lut = 7'h5B;  // 2  — 0b1011011
            4'h3: seg_lut = 7'h4F;  // 3  — 0b1001111
            4'h4: seg_lut = 7'h66;  // 4  — 0b1100110
            4'h5: seg_lut = 7'h6D;  // 5  — 0b1101101
            4'h6: seg_lut = 7'h7D;  // 6  — 0b1111101
            4'h7: seg_lut = 7'h07;  // 7  — 0b0000111
            4'h8: seg_lut = 7'h7F;  // 8  — 0b1111111
            4'h9: seg_lut = 7'h6F;  // 9  — 0b1101111
            4'hA: seg_lut = 7'h77;  // A  — 0b1110111
            4'hB: seg_lut = 7'h7C;  // b  — 0b1111100
            4'hC: seg_lut = 7'h39;  // C  — 0b0111001
            4'hD: seg_lut = 7'h5E;  // d  — 0b1011110  (donE)
            4'hE: seg_lut = 7'h79;  // E  — 0b1111001
            4'hF: seg_lut = 7'h37;  // n  — 0b0110111  (blank/off marker)
            default: seg_lut = 7'h00;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output drive — combine disp_en + blink_gate
    // -------------------------------------------------------------------------
    wire display_on;
    assign display_on = ctrl_disp_en && blink_gate;

    // Segment outputs: drive LUT result when display is on, else all zeros
    assign seg_out_o   = display_on ? seg_lut       : 7'h00;

    // Digit select: one-hot, active-high; all off when display is disabled
    assign digit_sel_o = display_on ? (4'b0001 << mux_idx) : 4'b0000;

endmodule : axi_seg7_top

`default_nettype wire
