// =============================================================================
// Module: tb_pwm_top
//
// Standalone testbench for the AXI-Lite PWM Generator IP.
//
// DUT hierarchy
// ─────────────
//   tb_pwm_top
//     └─ axi_interconnect_wrap_3x15  (u_interconnect)
//           └─ M04 → axi_width_adapter (u_width_adapt)
//                        └─ axi_pwm_top (u_pwm)
//
// The testbench acts as a single AXI4 master connected to S00 of the
// interconnect.  M04 is mapped to 0x1400_0000 (12-bit window) — the same
// mapping used in soc_top.sv.  All other interconnect master ports
// (M00-M03, M05-M14) carry inline stub slaves that return SLVERR.
//
// Test plan
// ─────────
//  TEST 1 – Register reset defaults
//    Read CTRL, DUTY, PERIOD, STATUS immediately after reset.
//    Expected: CTRL=0x0, DUTY=0x80, PERIOD=0x3E8, STATUS=0x0
//
//  TEST 2 – Write and read back DUTY and PERIOD
//    Write DUTY=0x40 (25 %), PERIOD=0x100 (256 ticks).
//    Read back both registers, check values match.
//
//  TEST 3 – Enable PWM and observe pwm_out
//    Write CTRL.pwm_en=1.  Wait > 1 full period.
//    Check that pwm_out toggles (goes high at least once).
//    Check STATUS.pwm_active=1 and STATUS.force_disabled=0.
//
//  TEST 4 – Force disable override
//    Assert pwm_force_disable externally.
//    Verify pwm_out stays LOW for the entire next period even with
//    pwm_en still set in the register.
//    Read STATUS: force_disabled=1, pwm_active=0.
//
//  TEST 5 – Clear enable and verify output stops
//    De-assert force_disable, write CTRL.pwm_en=0.
//    Verify pwm_out stays LOW.
//
// Pass/Fail
// ─────────
//   The testbench uses assertion-style $display + error counter.
//   At the end it prints "PASS" or "FAIL (N errors)" and calls $finish.
//
// Waveform dump
// ─────────────
//   $fsdbDumpvars — requires Synopsys Verdi.  The $fsdbDumpfile /
//   $fsdbDumpvars calls are guarded by `ifdef FSDB so the TB also
//   compiles cleanly without Verdi (VCD is always written).
//
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_pwm_top;

    // =========================================================================
    // Parameters
    // =========================================================================

    // Clock / reset
    localparam CLK_PERIOD  = 10;    // 10 ns → 100 MHz
    localparam RST_CYCLES  = 20;
    localparam MAX_CYCLES  = 200_000;

    // AXI interconnect widths (master-side)
    localparam IC_DATA_W = 64;
    localparam IC_ADDR_W = 32;
    localparam IC_ID_W   = 8;
    localparam IC_STRB_W = IC_DATA_W / 8;

    // PWM IP widths (slave-side after width adapter)
    localparam PWM_DATA_W = 32;
    localparam PWM_ADDR_W = 4;
    localparam PWM_ID_W   = 12;

    // Address of PWM block at interconnect M04
    localparam [IC_ADDR_W-1:0] PWM_BASE = 32'h1400_0000;

    // PWM register offsets
    localparam [IC_ADDR_W-1:0] REG_CTRL   = PWM_BASE + 32'h0;
    localparam [IC_ADDR_W-1:0] REG_DUTY   = PWM_BASE + 32'h4;
    localparam [IC_ADDR_W-1:0] REG_PERIOD = PWM_BASE + 32'h8;
    localparam [IC_ADDR_W-1:0] REG_STATUS = PWM_BASE + 32'hC;

    // Reset defaults (must match pwm_defines.vh)
    localparam [7:0]  DUTY_RST   = 8'd128;
    localparam [15:0] PERIOD_RST = 16'd1000;

    // =========================================================================
    // Clock and reset
    // =========================================================================

    logic clk;
    logic rst;          // active-high (interconnect convention)
    logic rst_n;        // active-low  (PWM IP convention)

    initial clk = 1'b0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    assign rst_n = ~rst;

    initial begin
        rst = 1'b1;
        repeat (RST_CYCLES) @(posedge clk);
        @(posedge clk); #1;
        rst = 1'b0;
        $display("[TB] Reset de-asserted at %0t ns", $time);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================

    initial begin
        repeat (MAX_CYCLES) @(posedge clk);
        $display("[TB] TIMEOUT after %0d cycles — forcing $finish", MAX_CYCLES);
        $finish;
    end

    // =========================================================================
    // Error counter
    // =========================================================================

    int error_count;
    initial error_count = 0;

    // =========================================================================
    // AXI master signals (single master on S00)
    // =========================================================================

    logic [IC_ID_W-1:0]   m_awid;
    logic [IC_ADDR_W-1:0] m_awaddr;
    logic [7:0]           m_awlen;
    logic [2:0]           m_awsize;
    logic [1:0]           m_awburst;
    logic                 m_awvalid;
    logic                 m_awready;

    logic [IC_DATA_W-1:0] m_wdata;
    logic [IC_STRB_W-1:0] m_wstrb;
    logic                 m_wlast;
    logic                 m_wvalid;
    logic                 m_wready;

    logic [IC_ID_W-1:0]   m_bid;
    logic [1:0]           m_bresp;
    logic                 m_bvalid;
    logic                 m_bready;

    logic [IC_ID_W-1:0]   m_arid;
    logic [IC_ADDR_W-1:0] m_araddr;
    logic [7:0]           m_arlen;
    logic [2:0]           m_arsize;
    logic [1:0]           m_arburst;
    logic                 m_arvalid;
    logic                 m_arready;

    logic [IC_ID_W-1:0]   m_rid;
    logic [IC_DATA_W-1:0] m_rdata;
    logic [1:0]           m_rresp;
    logic                 m_rlast;
    logic                 m_rvalid;
    logic                 m_rready;

    // =========================================================================
    // Stub slave arrays for M00-M03, M05-M14
    // (M04 is wired to the real PWM DUT)
    // =========================================================================

    logic [IC_ID_W-1:0]   sx_awid    [0:14];
    logic [IC_ADDR_W-1:0] sx_awaddr  [0:14];
    logic [7:0]           sx_awlen   [0:14];
    logic [2:0]           sx_awsize  [0:14];
    logic [1:0]           sx_awburst [0:14];
    logic                 sx_awvalid [0:14];
    logic                 sx_awready [0:14];

    logic [IC_DATA_W-1:0] sx_wdata   [0:14];
    logic [IC_STRB_W-1:0] sx_wstrb   [0:14];
    logic                 sx_wlast   [0:14];
    logic                 sx_wvalid  [0:14];
    logic                 sx_wready  [0:14];

    logic [IC_ID_W-1:0]   sx_bid     [0:14];
    logic [1:0]           sx_bresp   [0:14];
    logic                 sx_bvalid  [0:14];
    logic                 sx_bready  [0:14];

    logic [IC_ID_W-1:0]   sx_arid    [0:14];
    logic [IC_ADDR_W-1:0] sx_araddr  [0:14];
    logic [7:0]           sx_arlen   [0:14];
    logic [2:0]           sx_arsize  [0:14];
    logic [1:0]           sx_arburst [0:14];
    logic                 sx_arvalid [0:14];
    logic                 sx_arready [0:14];

    logic [IC_ID_W-1:0]   sx_rid     [0:14];
    logic [IC_DATA_W-1:0] sx_rdata   [0:14];
    logic [1:0]           sx_rresp   [0:14];
    logic                 sx_rlast   [0:14];
    logic                 sx_rvalid  [0:14];
    logic                 sx_rready  [0:14];

    // =========================================================================
    // M04 dedicated wires (interconnect → width adapter → PWM)
    // =========================================================================

    // Interconnect side (64-bit)
    logic [IC_ID_W-1:0]   m04_awid;
    logic [IC_ADDR_W-1:0] m04_awaddr;
    logic [7:0]           m04_awlen;
    logic [2:0]           m04_awsize;
    logic [1:0]           m04_awburst;
    logic                 m04_awlock;
    logic [3:0]           m04_awcache;
    logic [2:0]           m04_awprot;
    logic [3:0]           m04_awqos;
    logic                 m04_awvalid;
    logic                 m04_awready;
    logic [IC_DATA_W-1:0] m04_wdata;
    logic [IC_STRB_W-1:0] m04_wstrb;
    logic                 m04_wlast;
    logic                 m04_wvalid;
    logic                 m04_wready;
    logic [IC_ID_W-1:0]   m04_bid;
    logic [1:0]           m04_bresp;
    logic                 m04_bvalid;
    logic                 m04_bready;
    logic [IC_ID_W-1:0]   m04_arid;
    logic [IC_ADDR_W-1:0] m04_araddr;
    logic [7:0]           m04_arlen;
    logic [2:0]           m04_arsize;
    logic [1:0]           m04_arburst;
    logic                 m04_arlock;
    logic [3:0]           m04_arcache;
    logic [2:0]           m04_arprot;
    logic [3:0]           m04_arqos;
    logic                 m04_arvalid;
    logic                 m04_arready;
    logic [IC_ID_W-1:0]   m04_rid;
    logic [IC_DATA_W-1:0] m04_rdata;
    logic [1:0]           m04_rresp;
    logic                 m04_rlast;
    logic                 m04_rvalid;
    logic                 m04_rready;

    // PWM AXI-Lite side (32-bit)
    logic [PWM_ID_W-1:0]  pwm_awid;
    logic [PWM_ADDR_W-1:0]pwm_awaddr;
    logic                 pwm_awvalid;
    logic                 pwm_awready;
    logic [PWM_DATA_W-1:0]pwm_wdata;
    logic [3:0]           pwm_wstrb;
    logic                 pwm_wvalid;
    logic                 pwm_wready;
    logic [PWM_ID_W-1:0]  pwm_bid;
    logic [1:0]           pwm_bresp;
    logic                 pwm_bvalid;
    logic                 pwm_bready;
    logic [PWM_ID_W-1:0]  pwm_arid;
    logic [PWM_ADDR_W-1:0]pwm_araddr;
    logic                 pwm_arvalid;
    logic                 pwm_arready;
    logic [PWM_ID_W-1:0]  pwm_rid;
    logic [PWM_DATA_W-1:0]pwm_rdata;
    logic [1:0]           pwm_rresp;
    logic                 pwm_rvalid;
    logic                 pwm_rready;

    // PWM physical outputs
    logic                 pwm_force_disable;
    logic                 pwm_out;

    // =========================================================================
    // Stub slave logic (SLVERR for M00-M03, M05-M14)
    // =========================================================================

    genvar g;
    generate
        for (g = 0; g <= 14; g++) begin : GEN_STUB
            if (g != 4) begin : GEN_STUB_ACTIVE

                logic aw_seen_s;
                logic w_seen_s;
                logic [IC_ID_W-1:0] saved_id_s;

                always_comb begin
                    sx_awready[g] = !aw_seen_s && !sx_bvalid[g];
                    sx_wready[g]  = !w_seen_s  && !sx_bvalid[g];
                    sx_arready[g] = !sx_rvalid[g];
                end

                always_ff @(posedge clk) begin
                    if (rst) begin
                        aw_seen_s      <= 1'b0;
                        w_seen_s       <= 1'b0;
                        saved_id_s     <= '0;
                        sx_bvalid[g]   <= 1'b0;
                        sx_bid[g]      <= '0;
                        sx_bresp[g]    <= 2'b10;  // SLVERR
                        sx_rvalid[g]   <= 1'b0;
                        sx_rid[g]      <= '0;
                        sx_rdata[g]    <= '0;
                        sx_rresp[g]    <= 2'b10;
                        sx_rlast[g]    <= 1'b0;
                    end else begin
                        if (sx_awvalid[g] && sx_awready[g]) begin
                            aw_seen_s  <= 1'b1;
                            saved_id_s <= sx_awid[g];
                        end
                        if (sx_wvalid[g] && sx_wready[g])
                            w_seen_s <= 1'b1;
                        if (aw_seen_s && w_seen_s && !sx_bvalid[g]) begin
                            sx_bid[g]    <= saved_id_s;
                            sx_bresp[g]  <= 2'b10;
                            sx_bvalid[g] <= 1'b1;
                            aw_seen_s    <= 1'b0;
                            w_seen_s     <= 1'b0;
                        end
                        if (sx_bvalid[g] && sx_bready[g])
                            sx_bvalid[g] <= 1'b0;
                        if (sx_arvalid[g] && sx_arready[g]) begin
                            sx_rid[g]    <= sx_arid[g];
                            sx_rdata[g]  <= '0;
                            sx_rresp[g]  <= 2'b10;
                            sx_rlast[g]  <= 1'b1;
                            sx_rvalid[g] <= 1'b1;
                        end
                        if (sx_rvalid[g] && sx_rready[g]) begin
                            sx_rvalid[g] <= 1'b0;
                            sx_rlast[g]  <= 1'b0;
                        end
                    end
                end

            end : GEN_STUB_ACTIVE
        end
    endgenerate

    // =========================================================================
    // DUT 1: AXI 3×15 Interconnect
    // =========================================================================

    axi_interconnect_wrap_3x15 #(
        .DATA_WIDTH          (IC_DATA_W),
        .ADDR_WIDTH          (IC_ADDR_W),
        .ID_WIDTH            (IC_ID_W),

        // M04 = PWM @ 0x1400_0000, 12-bit window (4 KiB)
        .M04_BASE_ADDR       (32'h1400_0000),
        .M04_ADDR_WIDTH      ({1{32'd12}}),
        .M04_CONNECT_READ    (3'b001),   // only S00 reaches PWM
        .M04_CONNECT_WRITE   (3'b001)
    ) u_interconnect (
        .clk (clk),
        .rst (rst),

        // ── S00 (our AXI master) ─────────────────────────────────────────
        .s00_axi_awid    (m_awid),
        .s00_axi_awaddr  (m_awaddr),
        .s00_axi_awlen   (m_awlen),
        .s00_axi_awsize  (m_awsize),
        .s00_axi_awburst (m_awburst),
        .s00_axi_awlock  (1'b0),
        .s00_axi_awcache (4'h0),
        .s00_axi_awprot  (3'h0),
        .s00_axi_awqos   (4'h0),
        .s00_axi_awuser  ('0),
        .s00_axi_awvalid (m_awvalid),
        .s00_axi_awready (m_awready),

        .s00_axi_wdata   (m_wdata),
        .s00_axi_wstrb   (m_wstrb),
        .s00_axi_wlast   (m_wlast),
        .s00_axi_wuser   ('0),
        .s00_axi_wvalid  (m_wvalid),
        .s00_axi_wready  (m_wready),

        .s00_axi_bid     (m_bid),
        .s00_axi_bresp   (m_bresp),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (m_bvalid),
        .s00_axi_bready  (m_bready),

        .s00_axi_arid    (m_arid),
        .s00_axi_araddr  (m_araddr),
        .s00_axi_arlen   (m_arlen),
        .s00_axi_arsize  (m_arsize),
        .s00_axi_arburst (m_arburst),
        .s00_axi_arlock  (1'b0),
        .s00_axi_arcache (4'h0),
        .s00_axi_arprot  (3'h0),
        .s00_axi_arqos   (4'h0),
        .s00_axi_aruser  ('0),
        .s00_axi_arvalid (m_arvalid),
        .s00_axi_arready (m_arready),

        .s00_axi_rid     (m_rid),
        .s00_axi_rdata   (m_rdata),
        .s00_axi_rresp   (m_rresp),
        .s00_axi_rlast   (m_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (m_rvalid),
        .s00_axi_rready  (m_rready),

        // ── S01 / S02 (tied off — no second master) ──────────────────────
        .s01_axi_awid    ('0), .s01_axi_awaddr ('0), .s01_axi_awlen  ('0),
        .s01_axi_awsize  ('0), .s01_axi_awburst('0), .s01_axi_awlock ('0),
        .s01_axi_awcache ('0), .s01_axi_awprot ('0), .s01_axi_awqos  ('0),
        .s01_axi_awuser  ('0), .s01_axi_awvalid(1'b0),.s01_axi_awready(),
        .s01_axi_wdata   ('0), .s01_axi_wstrb  ('0), .s01_axi_wlast  ('0),
        .s01_axi_wuser   ('0), .s01_axi_wvalid (1'b0),.s01_axi_wready(),
        .s01_axi_bid     (),   .s01_axi_bresp  (),   .s01_axi_buser  (),
        .s01_axi_bvalid  (),   .s01_axi_bready (1'b1),
        .s01_axi_arid    ('0), .s01_axi_araddr ('0), .s01_axi_arlen  ('0),
        .s01_axi_arsize  ('0), .s01_axi_arburst('0), .s01_axi_arlock ('0),
        .s01_axi_arcache ('0), .s01_axi_arprot ('0), .s01_axi_arqos  ('0),
        .s01_axi_aruser  ('0), .s01_axi_arvalid(1'b0),.s01_axi_arready(),
        .s01_axi_rid     (),   .s01_axi_rdata  (),   .s01_axi_rresp  (),
        .s01_axi_rlast   (),   .s01_axi_ruser  (),   .s01_axi_rvalid (),
        .s01_axi_rready  (1'b1),

        .s02_axi_awid    ('0), .s02_axi_awaddr ('0), .s02_axi_awlen  ('0),
        .s02_axi_awsize  ('0), .s02_axi_awburst('0), .s02_axi_awlock ('0),
        .s02_axi_awcache ('0), .s02_axi_awprot ('0), .s02_axi_awqos  ('0),
        .s02_axi_awuser  ('0), .s02_axi_awvalid(1'b0),.s02_axi_awready(),
        .s02_axi_wdata   ('0), .s02_axi_wstrb  ('0), .s02_axi_wlast  ('0),
        .s02_axi_wuser   ('0), .s02_axi_wvalid (1'b0),.s02_axi_wready(),
        .s02_axi_bid     (),   .s02_axi_bresp  (),   .s02_axi_buser  (),
        .s02_axi_bvalid  (),   .s02_axi_bready (1'b1),
        .s02_axi_arid    ('0), .s02_axi_araddr ('0), .s02_axi_arlen  ('0),
        .s02_axi_arsize  ('0), .s02_axi_arburst('0), .s02_axi_arlock ('0),
        .s02_axi_arcache ('0), .s02_axi_arprot ('0), .s02_axi_arqos  ('0),
        .s02_axi_aruser  ('0), .s02_axi_arvalid(1'b0),.s02_axi_arready(),
        .s02_axi_rid     (),   .s02_axi_rdata  (),   .s02_axi_rresp  (),
        .s02_axi_rlast   (),   .s02_axi_ruser  (),   .s02_axi_rvalid (),
        .s02_axi_rready  (1'b1),

        // ── M00-M03 = stub slaves ─────────────────────────────────────────
        .m00_axi_awid    (sx_awid[0]),  .m00_axi_awaddr (sx_awaddr[0]),
        .m00_axi_awlen   (sx_awlen[0]), .m00_axi_awsize (sx_awsize[0]),
        .m00_axi_awburst (sx_awburst[0]),.m00_axi_awlock(),.m00_axi_awcache(),.m00_axi_awprot(),.m00_axi_awqos(),.m00_axi_awregion(),.m00_axi_awuser(),
        .m00_axi_awvalid (sx_awvalid[0]),.m00_axi_awready(sx_awready[0]),
        .m00_axi_wdata   (sx_wdata[0]), .m00_axi_wstrb  (sx_wstrb[0]),
        .m00_axi_wlast   (sx_wlast[0]), .m00_axi_wuser  (),
        .m00_axi_wvalid  (sx_wvalid[0]),.m00_axi_wready (sx_wready[0]),
        .m00_axi_bid     (sx_bid[0]),   .m00_axi_bresp  (sx_bresp[0]),
        .m00_axi_buser   ('0),          .m00_axi_bvalid (sx_bvalid[0]),
        .m00_axi_bready  (sx_bready[0]),
        .m00_axi_arid    (sx_arid[0]),  .m00_axi_araddr (sx_araddr[0]),
        .m00_axi_arlen   (sx_arlen[0]), .m00_axi_arsize (sx_arsize[0]),
        .m00_axi_arburst (sx_arburst[0]),.m00_axi_arlock(),.m00_axi_arcache(),.m00_axi_arprot(),.m00_axi_arqos(),.m00_axi_arregion(),.m00_axi_aruser(),
        .m00_axi_arvalid (sx_arvalid[0]),.m00_axi_arready(sx_arready[0]),
        .m00_axi_rid     (sx_rid[0]),   .m00_axi_rdata  (sx_rdata[0]),
        .m00_axi_rresp   (sx_rresp[0]), .m00_axi_rlast  (sx_rlast[0]),
        .m00_axi_ruser   ('0),          .m00_axi_rvalid (sx_rvalid[0]),
        .m00_axi_rready  (sx_rready[0]),

        .m01_axi_awid(sx_awid[1]),.m01_axi_awaddr(sx_awaddr[1]),.m01_axi_awlen(sx_awlen[1]),.m01_axi_awsize(sx_awsize[1]),.m01_axi_awburst(sx_awburst[1]),.m01_axi_awlock(),.m01_axi_awcache(),.m01_axi_awprot(),.m01_axi_awqos(),.m01_axi_awregion(),.m01_axi_awuser(),.m01_axi_awvalid(sx_awvalid[1]),.m01_axi_awready(sx_awready[1]),
        .m01_axi_wdata(sx_wdata[1]),.m01_axi_wstrb(sx_wstrb[1]),.m01_axi_wlast(sx_wlast[1]),.m01_axi_wuser(),.m01_axi_wvalid(sx_wvalid[1]),.m01_axi_wready(sx_wready[1]),
        .m01_axi_bid(sx_bid[1]),.m01_axi_bresp(sx_bresp[1]),.m01_axi_buser('0),.m01_axi_bvalid(sx_bvalid[1]),.m01_axi_bready(sx_bready[1]),
        .m01_axi_arid(sx_arid[1]),.m01_axi_araddr(sx_araddr[1]),.m01_axi_arlen(sx_arlen[1]),.m01_axi_arsize(sx_arsize[1]),.m01_axi_arburst(sx_arburst[1]),.m01_axi_arlock(),.m01_axi_arcache(),.m01_axi_arprot(),.m01_axi_arqos(),.m01_axi_arregion(),.m01_axi_aruser(),.m01_axi_arvalid(sx_arvalid[1]),.m01_axi_arready(sx_arready[1]),
        .m01_axi_rid(sx_rid[1]),.m01_axi_rdata(sx_rdata[1]),.m01_axi_rresp(sx_rresp[1]),.m01_axi_rlast(sx_rlast[1]),.m01_axi_ruser('0),.m01_axi_rvalid(sx_rvalid[1]),.m01_axi_rready(sx_rready[1]),

        .m02_axi_awid(sx_awid[2]),.m02_axi_awaddr(sx_awaddr[2]),.m02_axi_awlen(sx_awlen[2]),.m02_axi_awsize(sx_awsize[2]),.m02_axi_awburst(sx_awburst[2]),.m02_axi_awlock(),.m02_axi_awcache(),.m02_axi_awprot(),.m02_axi_awqos(),.m02_axi_awregion(),.m02_axi_awuser(),.m02_axi_awvalid(sx_awvalid[2]),.m02_axi_awready(sx_awready[2]),
        .m02_axi_wdata(sx_wdata[2]),.m02_axi_wstrb(sx_wstrb[2]),.m02_axi_wlast(sx_wlast[2]),.m02_axi_wuser(),.m02_axi_wvalid(sx_wvalid[2]),.m02_axi_wready(sx_wready[2]),
        .m02_axi_bid(sx_bid[2]),.m02_axi_bresp(sx_bresp[2]),.m02_axi_buser('0),.m02_axi_bvalid(sx_bvalid[2]),.m02_axi_bready(sx_bready[2]),
        .m02_axi_arid(sx_arid[2]),.m02_axi_araddr(sx_araddr[2]),.m02_axi_arlen(sx_arlen[2]),.m02_axi_arsize(sx_arsize[2]),.m02_axi_arburst(sx_arburst[2]),.m02_axi_arlock(),.m02_axi_arcache(),.m02_axi_arprot(),.m02_axi_arqos(),.m02_axi_arregion(),.m02_axi_aruser(),.m02_axi_arvalid(sx_arvalid[2]),.m02_axi_arready(sx_arready[2]),
        .m02_axi_rid(sx_rid[2]),.m02_axi_rdata(sx_rdata[2]),.m02_axi_rresp(sx_rresp[2]),.m02_axi_rlast(sx_rlast[2]),.m02_axi_ruser('0),.m02_axi_rvalid(sx_rvalid[2]),.m02_axi_rready(sx_rready[2]),

        .m03_axi_awid(sx_awid[3]),.m03_axi_awaddr(sx_awaddr[3]),.m03_axi_awlen(sx_awlen[3]),.m03_axi_awsize(sx_awsize[3]),.m03_axi_awburst(sx_awburst[3]),.m03_axi_awlock(),.m03_axi_awcache(),.m03_axi_awprot(),.m03_axi_awqos(),.m03_axi_awregion(),.m03_axi_awuser(),.m03_axi_awvalid(sx_awvalid[3]),.m03_axi_awready(sx_awready[3]),
        .m03_axi_wdata(sx_wdata[3]),.m03_axi_wstrb(sx_wstrb[3]),.m03_axi_wlast(sx_wlast[3]),.m03_axi_wuser(),.m03_axi_wvalid(sx_wvalid[3]),.m03_axi_wready(sx_wready[3]),
        .m03_axi_bid(sx_bid[3]),.m03_axi_bresp(sx_bresp[3]),.m03_axi_buser('0),.m03_axi_bvalid(sx_bvalid[3]),.m03_axi_bready(sx_bready[3]),
        .m03_axi_arid(sx_arid[3]),.m03_axi_araddr(sx_araddr[3]),.m03_axi_arlen(sx_arlen[3]),.m03_axi_arsize(sx_arsize[3]),.m03_axi_arburst(sx_arburst[3]),.m03_axi_arlock(),.m03_axi_arcache(),.m03_axi_arprot(),.m03_axi_arqos(),.m03_axi_arregion(),.m03_axi_aruser(),.m03_axi_arvalid(sx_arvalid[3]),.m03_axi_arready(sx_arready[3]),
        .m03_axi_rid(sx_rid[3]),.m03_axi_rdata(sx_rdata[3]),.m03_axi_rresp(sx_rresp[3]),.m03_axi_rlast(sx_rlast[3]),.m03_axi_ruser('0),.m03_axi_rvalid(sx_rvalid[3]),.m03_axi_rready(sx_rready[3]),

        // ── M04 = PWM Generator (real DUT) ───────────────────────────────
        .m04_axi_awid    (m04_awid),    .m04_axi_awaddr  (m04_awaddr),
        .m04_axi_awlen   (m04_awlen),   .m04_axi_awsize  (m04_awsize),
        .m04_axi_awburst (m04_awburst), .m04_axi_awlock  (m04_awlock),
        .m04_axi_awcache (m04_awcache), .m04_axi_awprot  (m04_awprot),
        .m04_axi_awqos   (m04_awqos),   .m04_axi_awregion(),
        .m04_axi_awuser  (),            .m04_axi_awvalid (m04_awvalid),
        .m04_axi_awready (m04_awready),
        .m04_axi_wdata   (m04_wdata),   .m04_axi_wstrb   (m04_wstrb),
        .m04_axi_wlast   (m04_wlast),   .m04_axi_wuser   (),
        .m04_axi_wvalid  (m04_wvalid),  .m04_axi_wready  (m04_wready),
        .m04_axi_bid     (m04_bid),     .m04_axi_bresp   (m04_bresp),
        .m04_axi_buser   ('0),          .m04_axi_bvalid  (m04_bvalid),
        .m04_axi_bready  (m04_bready),
        .m04_axi_arid    (m04_arid),    .m04_axi_araddr  (m04_araddr),
        .m04_axi_arlen   (m04_arlen),   .m04_axi_arsize  (m04_arsize),
        .m04_axi_arburst (m04_arburst), .m04_axi_arlock  (m04_arlock),
        .m04_axi_arcache (m04_arcache), .m04_axi_arprot  (m04_arprot),
        .m04_axi_arqos   (m04_arqos),   .m04_axi_arregion(),
        .m04_axi_aruser  (),            .m04_axi_arvalid (m04_arvalid),
        .m04_axi_arready (m04_arready),
        .m04_axi_rid     (m04_rid),     .m04_axi_rdata   (m04_rdata),
        .m04_axi_rresp   (m04_rresp),   .m04_axi_rlast   (m04_rlast),
        .m04_axi_ruser   ('0),          .m04_axi_rvalid  (m04_rvalid),
        .m04_axi_rready  (m04_rready),

        // ── M05-M14 = stub slaves ─────────────────────────────────────────
        .m05_axi_awid(sx_awid[5]),.m05_axi_awaddr(sx_awaddr[5]),.m05_axi_awlen(sx_awlen[5]),.m05_axi_awsize(sx_awsize[5]),.m05_axi_awburst(sx_awburst[5]),.m05_axi_awlock(),.m05_axi_awcache(),.m05_axi_awprot(),.m05_axi_awqos(),.m05_axi_awregion(),.m05_axi_awuser(),.m05_axi_awvalid(sx_awvalid[5]),.m05_axi_awready(sx_awready[5]),
        .m05_axi_wdata(sx_wdata[5]),.m05_axi_wstrb(sx_wstrb[5]),.m05_axi_wlast(sx_wlast[5]),.m05_axi_wuser(),.m05_axi_wvalid(sx_wvalid[5]),.m05_axi_wready(sx_wready[5]),
        .m05_axi_bid(sx_bid[5]),.m05_axi_bresp(sx_bresp[5]),.m05_axi_buser('0),.m05_axi_bvalid(sx_bvalid[5]),.m05_axi_bready(sx_bready[5]),
        .m05_axi_arid(sx_arid[5]),.m05_axi_araddr(sx_araddr[5]),.m05_axi_arlen(sx_arlen[5]),.m05_axi_arsize(sx_arsize[5]),.m05_axi_arburst(sx_arburst[5]),.m05_axi_arlock(),.m05_axi_arcache(),.m05_axi_arprot(),.m05_axi_arqos(),.m05_axi_arregion(),.m05_axi_aruser(),.m05_axi_arvalid(sx_arvalid[5]),.m05_axi_arready(sx_arready[5]),
        .m05_axi_rid(sx_rid[5]),.m05_axi_rdata(sx_rdata[5]),.m05_axi_rresp(sx_rresp[5]),.m05_axi_rlast(sx_rlast[5]),.m05_axi_ruser('0),.m05_axi_rvalid(sx_rvalid[5]),.m05_axi_rready(sx_rready[5]),

        .m06_axi_awid(sx_awid[6]),.m06_axi_awaddr(sx_awaddr[6]),.m06_axi_awlen(sx_awlen[6]),.m06_axi_awsize(sx_awsize[6]),.m06_axi_awburst(sx_awburst[6]),.m06_axi_awlock(),.m06_axi_awcache(),.m06_axi_awprot(),.m06_axi_awqos(),.m06_axi_awregion(),.m06_axi_awuser(),.m06_axi_awvalid(sx_awvalid[6]),.m06_axi_awready(sx_awready[6]),
        .m06_axi_wdata(sx_wdata[6]),.m06_axi_wstrb(sx_wstrb[6]),.m06_axi_wlast(sx_wlast[6]),.m06_axi_wuser(),.m06_axi_wvalid(sx_wvalid[6]),.m06_axi_wready(sx_wready[6]),
        .m06_axi_bid(sx_bid[6]),.m06_axi_bresp(sx_bresp[6]),.m06_axi_buser('0),.m06_axi_bvalid(sx_bvalid[6]),.m06_axi_bready(sx_bready[6]),
        .m06_axi_arid(sx_arid[6]),.m06_axi_araddr(sx_araddr[6]),.m06_axi_arlen(sx_arlen[6]),.m06_axi_arsize(sx_arsize[6]),.m06_axi_arburst(sx_arburst[6]),.m06_axi_arlock(),.m06_axi_arcache(),.m06_axi_arprot(),.m06_axi_arqos(),.m06_axi_arregion(),.m06_axi_aruser(),.m06_axi_arvalid(sx_arvalid[6]),.m06_axi_arready(sx_arready[6]),
        .m06_axi_rid(sx_rid[6]),.m06_axi_rdata(sx_rdata[6]),.m06_axi_rresp(sx_rresp[6]),.m06_axi_rlast(sx_rlast[6]),.m06_axi_ruser('0),.m06_axi_rvalid(sx_rvalid[6]),.m06_axi_rready(sx_rready[6]),

        .m07_axi_awid(sx_awid[7]),.m07_axi_awaddr(sx_awaddr[7]),.m07_axi_awlen(sx_awlen[7]),.m07_axi_awsize(sx_awsize[7]),.m07_axi_awburst(sx_awburst[7]),.m07_axi_awlock(),.m07_axi_awcache(),.m07_axi_awprot(),.m07_axi_awqos(),.m07_axi_awregion(),.m07_axi_awuser(),.m07_axi_awvalid(sx_awvalid[7]),.m07_axi_awready(sx_awready[7]),
        .m07_axi_wdata(sx_wdata[7]),.m07_axi_wstrb(sx_wstrb[7]),.m07_axi_wlast(sx_wlast[7]),.m07_axi_wuser(),.m07_axi_wvalid(sx_wvalid[7]),.m07_axi_wready(sx_wready[7]),
        .m07_axi_bid(sx_bid[7]),.m07_axi_bresp(sx_bresp[7]),.m07_axi_buser('0),.m07_axi_bvalid(sx_bvalid[7]),.m07_axi_bready(sx_bready[7]),
        .m07_axi_arid(sx_arid[7]),.m07_axi_araddr(sx_araddr[7]),.m07_axi_arlen(sx_arlen[7]),.m07_axi_arsize(sx_arsize[7]),.m07_axi_arburst(sx_arburst[7]),.m07_axi_arlock(),.m07_axi_arcache(),.m07_axi_arprot(),.m07_axi_arqos(),.m07_axi_arregion(),.m07_axi_aruser(),.m07_axi_arvalid(sx_arvalid[7]),.m07_axi_arready(sx_arready[7]),
        .m07_axi_rid(sx_rid[7]),.m07_axi_rdata(sx_rdata[7]),.m07_axi_rresp(sx_rresp[7]),.m07_axi_rlast(sx_rlast[7]),.m07_axi_ruser('0),.m07_axi_rvalid(sx_rvalid[7]),.m07_axi_rready(sx_rready[7]),

        .m08_axi_awid(sx_awid[8]),.m08_axi_awaddr(sx_awaddr[8]),.m08_axi_awlen(sx_awlen[8]),.m08_axi_awsize(sx_awsize[8]),.m08_axi_awburst(sx_awburst[8]),.m08_axi_awlock(),.m08_axi_awcache(),.m08_axi_awprot(),.m08_axi_awqos(),.m08_axi_awregion(),.m08_axi_awuser(),.m08_axi_awvalid(sx_awvalid[8]),.m08_axi_awready(sx_awready[8]),
        .m08_axi_wdata(sx_wdata[8]),.m08_axi_wstrb(sx_wstrb[8]),.m08_axi_wlast(sx_wlast[8]),.m08_axi_wuser(),.m08_axi_wvalid(sx_wvalid[8]),.m08_axi_wready(sx_wready[8]),
        .m08_axi_bid(sx_bid[8]),.m08_axi_bresp(sx_bresp[8]),.m08_axi_buser('0),.m08_axi_bvalid(sx_bvalid[8]),.m08_axi_bready(sx_bready[8]),
        .m08_axi_arid(sx_arid[8]),.m08_axi_araddr(sx_araddr[8]),.m08_axi_arlen(sx_arlen[8]),.m08_axi_arsize(sx_arsize[8]),.m08_axi_arburst(sx_arburst[8]),.m08_axi_arlock(),.m08_axi_arcache(),.m08_axi_arprot(),.m08_axi_arqos(),.m08_axi_arregion(),.m08_axi_aruser(),.m08_axi_arvalid(sx_arvalid[8]),.m08_axi_arready(sx_arready[8]),
        .m08_axi_rid(sx_rid[8]),.m08_axi_rdata(sx_rdata[8]),.m08_axi_rresp(sx_rresp[8]),.m08_axi_rlast(sx_rlast[8]),.m08_axi_ruser('0),.m08_axi_rvalid(sx_rvalid[8]),.m08_axi_rready(sx_rready[8]),

        .m09_axi_awid(sx_awid[9]),.m09_axi_awaddr(sx_awaddr[9]),.m09_axi_awlen(sx_awlen[9]),.m09_axi_awsize(sx_awsize[9]),.m09_axi_awburst(sx_awburst[9]),.m09_axi_awlock(),.m09_axi_awcache(),.m09_axi_awprot(),.m09_axi_awqos(),.m09_axi_awregion(),.m09_axi_awuser(),.m09_axi_awvalid(sx_awvalid[9]),.m09_axi_awready(sx_awready[9]),
        .m09_axi_wdata(sx_wdata[9]),.m09_axi_wstrb(sx_wstrb[9]),.m09_axi_wlast(sx_wlast[9]),.m09_axi_wuser(),.m09_axi_wvalid(sx_wvalid[9]),.m09_axi_wready(sx_wready[9]),
        .m09_axi_bid(sx_bid[9]),.m09_axi_bresp(sx_bresp[9]),.m09_axi_buser('0),.m09_axi_bvalid(sx_bvalid[9]),.m09_axi_bready(sx_bready[9]),
        .m09_axi_arid(sx_arid[9]),.m09_axi_araddr(sx_araddr[9]),.m09_axi_arlen(sx_arlen[9]),.m09_axi_arsize(sx_arsize[9]),.m09_axi_arburst(sx_arburst[9]),.m09_axi_arlock(),.m09_axi_arcache(),.m09_axi_arprot(),.m09_axi_arqos(),.m09_axi_arregion(),.m09_axi_aruser(),.m09_axi_arvalid(sx_arvalid[9]),.m09_axi_arready(sx_arready[9]),
        .m09_axi_rid(sx_rid[9]),.m09_axi_rdata(sx_rdata[9]),.m09_axi_rresp(sx_rresp[9]),.m09_axi_rlast(sx_rlast[9]),.m09_axi_ruser('0),.m09_axi_rvalid(sx_rvalid[9]),.m09_axi_rready(sx_rready[9]),

        .m10_axi_awid(sx_awid[10]),.m10_axi_awaddr(sx_awaddr[10]),.m10_axi_awlen(sx_awlen[10]),.m10_axi_awsize(sx_awsize[10]),.m10_axi_awburst(sx_awburst[10]),.m10_axi_awlock(),.m10_axi_awcache(),.m10_axi_awprot(),.m10_axi_awqos(),.m10_axi_awregion(),.m10_axi_awuser(),.m10_axi_awvalid(sx_awvalid[10]),.m10_axi_awready(sx_awready[10]),
        .m10_axi_wdata(sx_wdata[10]),.m10_axi_wstrb(sx_wstrb[10]),.m10_axi_wlast(sx_wlast[10]),.m10_axi_wuser(),.m10_axi_wvalid(sx_wvalid[10]),.m10_axi_wready(sx_wready[10]),
        .m10_axi_bid(sx_bid[10]),.m10_axi_bresp(sx_bresp[10]),.m10_axi_buser('0),.m10_axi_bvalid(sx_bvalid[10]),.m10_axi_bready(sx_bready[10]),
        .m10_axi_arid(sx_arid[10]),.m10_axi_araddr(sx_araddr[10]),.m10_axi_arlen(sx_arlen[10]),.m10_axi_arsize(sx_arsize[10]),.m10_axi_arburst(sx_arburst[10]),.m10_axi_arlock(),.m10_axi_arcache(),.m10_axi_arprot(),.m10_axi_arqos(),.m10_axi_arregion(),.m10_axi_aruser(),.m10_axi_arvalid(sx_arvalid[10]),.m10_axi_arready(sx_arready[10]),
        .m10_axi_rid(sx_rid[10]),.m10_axi_rdata(sx_rdata[10]),.m10_axi_rresp(sx_rresp[10]),.m10_axi_rlast(sx_rlast[10]),.m10_axi_ruser('0),.m10_axi_rvalid(sx_rvalid[10]),.m10_axi_rready(sx_rready[10]),

        .m11_axi_awid(sx_awid[11]),.m11_axi_awaddr(sx_awaddr[11]),.m11_axi_awlen(sx_awlen[11]),.m11_axi_awsize(sx_awsize[11]),.m11_axi_awburst(sx_awburst[11]),.m11_axi_awlock(),.m11_axi_awcache(),.m11_axi_awprot(),.m11_axi_awqos(),.m11_axi_awregion(),.m11_axi_awuser(),.m11_axi_awvalid(sx_awvalid[11]),.m11_axi_awready(sx_awready[11]),
        .m11_axi_wdata(sx_wdata[11]),.m11_axi_wstrb(sx_wstrb[11]),.m11_axi_wlast(sx_wlast[11]),.m11_axi_wuser(),.m11_axi_wvalid(sx_wvalid[11]),.m11_axi_wready(sx_wready[11]),
        .m11_axi_bid(sx_bid[11]),.m11_axi_bresp(sx_bresp[11]),.m11_axi_buser('0),.m11_axi_bvalid(sx_bvalid[11]),.m11_axi_bready(sx_bready[11]),
        .m11_axi_arid(sx_arid[11]),.m11_axi_araddr(sx_araddr[11]),.m11_axi_arlen(sx_arlen[11]),.m11_axi_arsize(sx_arsize[11]),.m11_axi_arburst(sx_arburst[11]),.m11_axi_arlock(),.m11_axi_arcache(),.m11_axi_arprot(),.m11_axi_arqos(),.m11_axi_arregion(),.m11_axi_aruser(),.m11_axi_arvalid(sx_arvalid[11]),.m11_axi_arready(sx_arready[11]),
        .m11_axi_rid(sx_rid[11]),.m11_axi_rdata(sx_rdata[11]),.m11_axi_rresp(sx_rresp[11]),.m11_axi_rlast(sx_rlast[11]),.m11_axi_ruser('0),.m11_axi_rvalid(sx_rvalid[11]),.m11_axi_rready(sx_rready[11]),

        .m12_axi_awid(sx_awid[12]),.m12_axi_awaddr(sx_awaddr[12]),.m12_axi_awlen(sx_awlen[12]),.m12_axi_awsize(sx_awsize[12]),.m12_axi_awburst(sx_awburst[12]),.m12_axi_awlock(),.m12_axi_awcache(),.m12_axi_awprot(),.m12_axi_awqos(),.m12_axi_awregion(),.m12_axi_awuser(),.m12_axi_awvalid(sx_awvalid[12]),.m12_axi_awready(sx_awready[12]),
        .m12_axi_wdata(sx_wdata[12]),.m12_axi_wstrb(sx_wstrb[12]),.m12_axi_wlast(sx_wlast[12]),.m12_axi_wuser(),.m12_axi_wvalid(sx_wvalid[12]),.m12_axi_wready(sx_wready[12]),
        .m12_axi_bid(sx_bid[12]),.m12_axi_bresp(sx_bresp[12]),.m12_axi_buser('0),.m12_axi_bvalid(sx_bvalid[12]),.m12_axi_bready(sx_bready[12]),
        .m12_axi_arid(sx_arid[12]),.m12_axi_araddr(sx_araddr[12]),.m12_axi_arlen(sx_arlen[12]),.m12_axi_arsize(sx_arsize[12]),.m12_axi_arburst(sx_arburst[12]),.m12_axi_arlock(),.m12_axi_arcache(),.m12_axi_arprot(),.m12_axi_arqos(),.m12_axi_arregion(),.m12_axi_aruser(),.m12_axi_arvalid(sx_arvalid[12]),.m12_axi_arready(sx_arready[12]),
        .m12_axi_rid(sx_rid[12]),.m12_axi_rdata(sx_rdata[12]),.m12_axi_rresp(sx_rresp[12]),.m12_axi_rlast(sx_rlast[12]),.m12_axi_ruser('0),.m12_axi_rvalid(sx_rvalid[12]),.m12_axi_rready(sx_rready[12]),

        .m13_axi_awid(sx_awid[13]),.m13_axi_awaddr(sx_awaddr[13]),.m13_axi_awlen(sx_awlen[13]),.m13_axi_awsize(sx_awsize[13]),.m13_axi_awburst(sx_awburst[13]),.m13_axi_awlock(),.m13_axi_awcache(),.m13_axi_awprot(),.m13_axi_awqos(),.m13_axi_awregion(),.m13_axi_awuser(),.m13_axi_awvalid(sx_awvalid[13]),.m13_axi_awready(sx_awready[13]),
        .m13_axi_wdata(sx_wdata[13]),.m13_axi_wstrb(sx_wstrb[13]),.m13_axi_wlast(sx_wlast[13]),.m13_axi_wuser(),.m13_axi_wvalid(sx_wvalid[13]),.m13_axi_wready(sx_wready[13]),
        .m13_axi_bid(sx_bid[13]),.m13_axi_bresp(sx_bresp[13]),.m13_axi_buser('0),.m13_axi_bvalid(sx_bvalid[13]),.m13_axi_bready(sx_bready[13]),
        .m13_axi_arid(sx_arid[13]),.m13_axi_araddr(sx_araddr[13]),.m13_axi_arlen(sx_arlen[13]),.m13_axi_arsize(sx_arsize[13]),.m13_axi_arburst(sx_arburst[13]),.m13_axi_arlock(),.m13_axi_arcache(),.m13_axi_arprot(),.m13_axi_arqos(),.m13_axi_arregion(),.m13_axi_aruser(),.m13_axi_arvalid(sx_arvalid[13]),.m13_axi_arready(sx_arready[13]),
        .m13_axi_rid(sx_rid[13]),.m13_axi_rdata(sx_rdata[13]),.m13_axi_rresp(sx_rresp[13]),.m13_axi_rlast(sx_rlast[13]),.m13_axi_ruser('0),.m13_axi_rvalid(sx_rvalid[13]),.m13_axi_rready(sx_rready[13]),

        .m14_axi_awid(sx_awid[14]),.m14_axi_awaddr(sx_awaddr[14]),.m14_axi_awlen(sx_awlen[14]),.m14_axi_awsize(sx_awsize[14]),.m14_axi_awburst(sx_awburst[14]),.m14_axi_awlock(),.m14_axi_awcache(),.m14_axi_awprot(),.m14_axi_awqos(),.m14_axi_awregion(),.m14_axi_awuser(),.m14_axi_awvalid(sx_awvalid[14]),.m14_axi_awready(sx_awready[14]),
        .m14_axi_wdata(sx_wdata[14]),.m14_axi_wstrb(sx_wstrb[14]),.m14_axi_wlast(sx_wlast[14]),.m14_axi_wuser(),.m14_axi_wvalid(sx_wvalid[14]),.m14_axi_wready(sx_wready[14]),
        .m14_axi_bid(sx_bid[14]),.m14_axi_bresp(sx_bresp[14]),.m14_axi_buser('0),.m14_axi_bvalid(sx_bvalid[14]),.m14_axi_bready(sx_bready[14]),
        .m14_axi_arid(sx_arid[14]),.m14_axi_araddr(sx_araddr[14]),.m14_axi_arlen(sx_arlen[14]),.m14_axi_arsize(sx_arsize[14]),.m14_axi_arburst(sx_arburst[14]),.m14_axi_arlock(),.m14_axi_arcache(),.m14_axi_arprot(),.m14_axi_arqos(),.m14_axi_arregion(),.m14_axi_aruser(),.m14_axi_arvalid(sx_arvalid[14]),.m14_axi_arready(sx_arready[14]),
        .m14_axi_rid(sx_rid[14]),.m14_axi_rdata(sx_rdata[14]),.m14_axi_rresp(sx_rresp[14]),.m14_axi_rlast(sx_rlast[14]),.m14_axi_ruser('0),.m14_axi_rvalid(sx_rvalid[14]),.m14_axi_rready(sx_rready[14])
    );

    // =========================================================================
    // DUT 2: AXI Width Adapter (M04 64-bit → PWM 32-bit)
    // =========================================================================

    axi_width_adapter #(
        .IC_DATA_WIDTH (IC_DATA_W),
        .IC_ADDR_WIDTH (IC_ADDR_W),
        .IC_ID_WIDTH   (IC_ID_W),
        .SL_DATA_WIDTH (PWM_DATA_W),
        .SL_ADDR_WIDTH (PWM_ADDR_W),
        .SL_ID_WIDTH   (PWM_ID_W)
    ) u_width_adapt (
        .ic_awid    (m04_awid),    .ic_awaddr  (m04_awaddr),
        .ic_awlen   (m04_awlen),   .ic_awsize  (m04_awsize),
        .ic_awburst (m04_awburst), .ic_awlock  (m04_awlock),
        .ic_awcache (m04_awcache), .ic_awprot  (m04_awprot),
        .ic_awqos   (m04_awqos),   .ic_awvalid (m04_awvalid),
        .ic_awready (m04_awready),
        .ic_wdata   (m04_wdata),   .ic_wstrb   (m04_wstrb),
        .ic_wlast   (m04_wlast),   .ic_wvalid  (m04_wvalid),
        .ic_wready  (m04_wready),
        .ic_bid     (m04_bid),     .ic_bresp   (m04_bresp),
        .ic_bvalid  (m04_bvalid),  .ic_bready  (m04_bready),
        .ic_arid    (m04_arid),    .ic_araddr  (m04_araddr),
        .ic_arlen   (m04_arlen),   .ic_arsize  (m04_arsize),
        .ic_arburst (m04_arburst), .ic_arlock  (m04_arlock),
        .ic_arcache (m04_arcache), .ic_arprot  (m04_arprot),
        .ic_arqos   (m04_arqos),   .ic_arvalid (m04_arvalid),
        .ic_arready (m04_arready),
        .ic_rid     (m04_rid),     .ic_rdata   (m04_rdata),
        .ic_rresp   (m04_rresp),   .ic_rlast   (m04_rlast),
        .ic_rvalid  (m04_rvalid),  .ic_rready  (m04_rready),

        .sl_awid    (pwm_awid),    .sl_awaddr  (pwm_awaddr),
        .sl_awvalid (pwm_awvalid), .sl_awready (pwm_awready),
        .sl_wdata   (pwm_wdata),   .sl_wstrb   (pwm_wstrb),
        .sl_wvalid  (pwm_wvalid),  .sl_wready  (pwm_wready),
        .sl_bid     (pwm_bid),     .sl_bresp   (pwm_bresp),
        .sl_bvalid  (pwm_bvalid),  .sl_bready  (pwm_bready),
        .sl_arid    (pwm_arid),    .sl_araddr  (pwm_araddr),
        .sl_arvalid (pwm_arvalid), .sl_arready (pwm_arready),
        .sl_rid     (pwm_rid),     .sl_rdata   (pwm_rdata),
        .sl_rresp   (pwm_rresp),   .sl_rvalid  (pwm_rvalid),
        .sl_rready  (pwm_rready)
    );

    // =========================================================================
    // DUT 3: AXI-Lite PWM Generator
    // =========================================================================

    axi_pwm_top u_pwm (
        .axi_aclk_i    (clk),
        .axi_aresetn_i (rst_n),

        .axi_awid_i    (pwm_awid),    .axi_awaddr_i  (pwm_awaddr),
        .axi_awvalid_i (pwm_awvalid), .axi_awready_o (pwm_awready),
        .axi_wdata_i   (pwm_wdata),   .axi_wstrb_i   (pwm_wstrb),
        .axi_wvalid_i  (pwm_wvalid),  .axi_wready_o  (pwm_wready),
        .axi_bid_o     (pwm_bid),     .axi_bresp_o   (pwm_bresp),
        .axi_bvalid_o  (pwm_bvalid),  .axi_bready_i  (pwm_bready),

        .axi_arid_i    (pwm_arid),    .axi_araddr_i  (pwm_araddr),
        .axi_arvalid_i (pwm_arvalid), .axi_arready_o (pwm_arready),
        .axi_rid_o     (pwm_rid),     .axi_rdata_o   (pwm_rdata),
        .axi_rresp_o   (pwm_rresp),   .axi_rvalid_o  (pwm_rvalid),
        .axi_rready_i  (pwm_rready),

        .pwm_force_disable_i (pwm_force_disable),
        .pwm_out_o           (pwm_out)
    );

    // =========================================================================
    // Idle / initialise master bus signals
    // =========================================================================

    initial begin
        m_awid    = '0;  m_awaddr  = '0;  m_awlen   = 8'h0;
        m_awsize  = 3'h2; m_awburst = 2'b01; m_awvalid = 1'b0;
        m_wdata   = '0;  m_wstrb   = '0;  m_wlast   = 1'b0;  m_wvalid  = 1'b0;
        m_bready  = 1'b1;
        m_arid    = '0;  m_araddr  = '0;  m_arlen   = 8'h0;
        m_arsize  = 3'h2; m_arburst = 2'b01; m_arvalid = 1'b0;
        m_rready  = 1'b1;
        pwm_force_disable = 1'b0;
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        $dumpfile("tb_pwm_top.vcd");
        $dumpvars(0, tb_pwm_top);
    end

`ifdef FSDB
    initial begin
        $fsdbDumpfile("tb_pwm_top.fsdb");
        $fsdbDumpvars(0, tb_pwm_top);
    end
`endif

    // =========================================================================
    // AXI master tasks
    // =========================================================================

    // -- Single-beat AXI write -----------------------------------------------
    // addr  : 32-bit byte address (M04 must be in 0x1400_0000 range)
    // data  : 32-bit payload (placed in lower word; upper word zeroed)
    // strb  : 4-bit byte strobe (lower 4 bits of the 8-bit IC strobe)
    task automatic axi_write(
        input  [IC_ADDR_W-1:0] addr,
        input  [31:0]          data,
        input  [3:0]           strb
    );
        // Drive AW and W in the same cycle (AXI-Lite style)
        @(posedge clk); #1;
        m_awaddr  <= addr;
        m_awlen   <= 8'h0;          // single beat
        m_awsize  <= 3'h2;          // 4-byte transfer (lower word)
        m_awburst <= 2'b01;
        m_awvalid <= 1'b1;
        m_wdata   <= {32'h0, data}; // data in lower 32 bits
        m_wstrb   <= {4'h0, strb};  // strobe in lower 4 bits
        m_wlast   <= 1'b1;
        m_wvalid  <= 1'b1;

        // Wait for both AW and W handshakes
        fork
            begin @(posedge clk iff (m_awvalid && m_awready)); m_awvalid <= 1'b0; end
            begin @(posedge clk iff (m_wvalid  && m_wready));  m_wvalid  <= 1'b0; m_wlast <= 1'b0; end
        join

        // Wait for B response (m_bready is permanently high)
        @(posedge clk iff m_bvalid);
        @(posedge clk); #1;
    endtask

    // -- Single-beat AXI read ------------------------------------------------
    task automatic axi_read(
        input  [IC_ADDR_W-1:0] addr,
        output [31:0]          data
    );
        @(posedge clk); #1;
        m_araddr  <= addr;
        m_arlen   <= 8'h0;
        m_arsize  <= 3'h2;
        m_arburst <= 2'b01;
        m_arvalid <= 1'b1;

        @(posedge clk iff (m_arvalid && m_arready)); #1;
        m_arvalid <= 1'b0;

        // Wait for R response (m_rready is permanently high)
        @(posedge clk iff m_rvalid);
        data = m_rdata[31:0];   // lower 32 bits from 64-bit bus
        @(posedge clk); #1;
    endtask

    // -- Check helper --------------------------------------------------------
    task automatic check_eq(
        input string    test_name,
        input [31:0]    got,
        input [31:0]    expected
    );
        if (got !== expected) begin
            $display("[FAIL] %s : got 0x%08h, expected 0x%08h",
                     test_name, got, expected);
            error_count++;
        end else begin
            $display("[PASS] %s : 0x%08h", test_name, got);
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================

    logic [31:0] rdata;
    logic        saw_high;
    int          sample;

    initial begin
        // ── Wait for reset to de-assert ──────────────────────────────────────
        @(negedge rst);
        repeat (5) @(posedge clk);

        $display("");
        $display("========================================");
        $display("  PWM Generator Testbench");
        $display("  DUT: axi_pwm_top via interconnect M04");
        $display("========================================");

        // ────────────────────────────────────────────────────────────────────
        // TEST 1 — Reset defaults
        // ────────────────────────────────────────────────────────────────────
        $display("\n[TEST 1] Reset defaults");

        axi_read(REG_CTRL,   rdata); check_eq("CTRL  reset", rdata, 32'h0000_0000);
        axi_read(REG_DUTY,   rdata); check_eq("DUTY  reset", rdata, {24'h0, DUTY_RST});
        axi_read(REG_PERIOD, rdata); check_eq("PERIOD reset", rdata, {16'h0, PERIOD_RST});
        axi_read(REG_STATUS, rdata); check_eq("STATUS reset", rdata, 32'h0000_0000);

        // ────────────────────────────────────────────────────────────────────
        // TEST 2 — Write DUTY and PERIOD, read back
        // ────────────────────────────────────────────────────────────────────
        $display("\n[TEST 2] Write DUTY=0x40, PERIOD=0x100 and read back");

        axi_write(REG_DUTY,   32'h0000_0040, 4'hF);
        axi_write(REG_PERIOD, 32'h0000_0100, 4'hF);

        axi_read(REG_DUTY,   rdata); check_eq("DUTY  WR/RD", rdata, 32'h0000_0040);
        axi_read(REG_PERIOD, rdata); check_eq("PERIOD WR/RD", rdata, 32'h0000_0100);

        // ────────────────────────────────────────────────────────────────────
        // TEST 3 — Enable PWM, observe pwm_out toggling
        // ────────────────────────────────────────────────────────────────────
        $display("\n[TEST 3] Enable PWM, observe pwm_out and STATUS");

        axi_write(REG_CTRL, 32'h0000_0001, 4'hF);  // pwm_en = 1

        // Wait just over 2 full periods (PERIOD=256 ticks × 2 = 512 cycles)
        saw_high = 1'b0;
        for (sample = 0; sample < 600; sample++) begin
            @(posedge clk);
            if (pwm_out) saw_high = 1'b1;
        end

        if (!saw_high) begin
            $display("[FAIL] TEST3: pwm_out never went HIGH in 600 cycles");
            error_count++;
        end else begin
            $display("[PASS] TEST3: pwm_out toggled high as expected");
        end

        axi_read(REG_STATUS, rdata);
        check_eq("STATUS.pwm_active=1,force_dis=0", rdata, 32'h0000_0001);

        // ────────────────────────────────────────────────────────────────────
        // TEST 4 — Force disable overrides pwm_en
        // ────────────────────────────────────────────────────────────────────
        $display("\n[TEST 4] Assert pwm_force_disable — output must stay LOW");

        @(posedge clk); #1;
        pwm_force_disable = 1'b1;   // Watchdog asserts

        // pwm_out must be low combinationally immediately
        @(posedge clk);
        if (pwm_out !== 1'b0) begin
            $display("[FAIL] TEST4: pwm_out not LOW one cycle after force_disable");
            error_count++;
        end else begin
            $display("[PASS] TEST4a: pwm_out is LOW after force_disable");
        end

        // Confirm it stays low across an entire period
        saw_high = 1'b0;
        for (sample = 0; sample < 300; sample++) begin
            @(posedge clk);
            if (pwm_out) saw_high = 1'b1;
        end
        if (saw_high) begin
            $display("[FAIL] TEST4b: pwm_out went HIGH while force_disable asserted");
            error_count++;
        end else begin
            $display("[PASS] TEST4b: pwm_out stayed LOW for 300 cycles");
        end

        // Check STATUS: force_disabled=1 (bit[1]), pwm_active=0 (bit[0])
        axi_read(REG_STATUS, rdata);
        check_eq("STATUS.force_disabled=1,active=0", rdata, 32'h0000_0002);

        // ────────────────────────────────────────────────────────────────────
        // TEST 5 — Clear pwm_en; de-assert force_disable; output stays LOW
        // ────────────────────────────────────────────────────────────────────
        $display("\n[TEST 5] Clear pwm_en and de-assert force_disable");

        axi_write(REG_CTRL, 32'h0000_0000, 4'hF);  // pwm_en = 0
        @(posedge clk); #1;
        pwm_force_disable = 1'b0;

        saw_high = 1'b0;
        for (sample = 0; sample < 300; sample++) begin
            @(posedge clk);
            if (pwm_out) saw_high = 1'b1;
        end
        if (saw_high) begin
            $display("[FAIL] TEST5: pwm_out went HIGH after pwm_en cleared");
            error_count++;
        end else begin
            $display("[PASS] TEST5: pwm_out stays LOW with pwm_en=0");
        end

        axi_read(REG_STATUS, rdata);
        check_eq("STATUS both 0 after disable", rdata, 32'h0000_0000);

        // ────────────────────────────────────────────────────────────────────
        // Final result
        // ────────────────────────────────────────────────────────────────────
        $display("");
        $display("========================================");
        if (error_count == 0)
            $display("  RESULT : PASS  (all tests passed)");
        else
            $display("  RESULT : FAIL  (%0d error(s))", error_count);
        $display("========================================");
        $display("");

        $finish;
    end

endmodule : tb_pwm_top

`default_nettype wire
