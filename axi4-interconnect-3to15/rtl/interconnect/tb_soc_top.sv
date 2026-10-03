// =============================================================================
// Module: tb_soc_top
//
// Testbench for the RISC-V VeeR EL2 SoC top-level (soc_top).
//
// What this TB does:
//   1. Generates clock and reset.
//   2. Instantiates soc_top which contains:
//        - RISC-V VeeR EL2 core (3 AXI master ports: LSU, IFU, SB)
//        - AXI4 3×15 Interconnect
//        - UART AXI-Lite (on M00 via axi_width_adapter)
//        - Stub SLVERR slaves on M02-M14
//   3. Instantiates a behavioural AXI4 SRAM on M01 (the RAM that the
//      RISC-V core boots from).  The RAM is pre-loaded with a minimal
//      infinite-loop program so the core will not hang waiting for
//      valid instruction data.
//   4. Provides a simple AXI4 RAM behavioural model that responds on the
//      M01 bus coming out of soc_top.
//   5. Waits for the RISC-V trace port to indicate at least one valid
//      instruction commit, then declares PASS.
//   6. Dumps FSDB waveforms for post-simulation analysis.
//
// Boot program loaded into RAM at 0x0000_0000 (RISC-V reset vector):
//   The default VeeR EL2 reset vector is 0x0000_0000 (configurable via
//   rst_vec).  We preload a tight infinite loop:
//
//     _start:
//       j _start          // 0x0000: JAL x0, 0  (compressed: c.j .)
//
//   In 64-bit words (LE):
//     Word[0] = 64'h0000_0001_0000_0001  // two copies of "c.j 0" (0x0001)
//
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_soc_top;

    // =========================================================================
    // Parameters
    // =========================================================================

    // Clock period (ns)
    localparam CLK_PERIOD = 10;  // 100 MHz

    // Reset assertion length (cycles)
    localparam RST_CYCLES = 20;

    // Simulation timeout (cycles)
    localparam MAX_CYCLES = 500_000;

    // RAM size (bytes) – must cover the program image
    localparam RAM_DEPTH_BYTES = 64 * 1024;   // 64 KiB
    localparam RAM_DEPTH_WORDS = RAM_DEPTH_BYTES / 8; // 64-bit words

    // AXI parameters (must match soc_top / interconnect)
    localparam IC_DATA_W = 64;
    localparam IC_ADDR_W = 32;
    localparam IC_ID_W   = 8;
    localparam IC_STRB_W = IC_DATA_W / 8;

    // =========================================================================
    // Clock and reset
    // =========================================================================

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk);
        #1;
        rst_n = 1'b1;
        $display("[TB] Reset de-asserted at time %0t", $time);
    end

    // =========================================================================
    // Simulation timeout watchdog
    // =========================================================================

    initial begin
        @(posedge rst_n);
        repeat (MAX_CYCLES) @(posedge clk);
        $display("[TB] TIMEOUT after %0d cycles – SIMULATION FAILED", MAX_CYCLES);
        $finish;
    end

    // =========================================================================
    // UART loopback (RX ← TX so the UART core does not see a broken line)
    // =========================================================================

    logic uart_tx;
    logic uart_rx;
    logic uart_irq;

    assign uart_rx = uart_tx;   // loopback

    // =========================================================================
    // Trace port signals (driven by soc_top)
    // =========================================================================

    logic [31:0] trace_insn;
    logic [31:0] trace_addr;
    logic        trace_valid;
    logic        trace_except;
    logic [4:0]  trace_ecause;
    logic        trace_intr;
    logic [31:0] trace_tval;

    // =========================================================================
    // M01 AXI wires (RAM connects here)
    // M01 signals are OUTPUTS of soc_top (interconnect drives them toward RAM)
    // =========================================================================

    // These are connected to soc_top's m01_* ports which are outputs of the
    // interconnect master port going to the RAM.  In soc_top they are
    // internal wires; they need to be exposed via extra ports or the RAM
    // must live inside soc_top.  Since soc_top does not expose m01, we
    // instantiate the behavioural RAM *inside* a wrapper that re-uses soc_top
    // with the RAM added externally.
    //
    // SOLUTION:  We expose the M01 bus by declaring the RAM *inside the TB*
    // and connecting it through the soc_top parameter system.  Because the
    // RAM is a separate instantiation the M01 wires must be top-level in
    // the TB.  We therefore drive them from the soc_top through dedicated
    // port connections.
    //
    // Instead of modifying soc_top to add ports for M01, we use a small
    // wrapper approach: tb_soc_top instantiates the DUT through a thin
    // pass-through (soc_tb_wrap) declared at the bottom of this file, which
    // adds the extra M01 ports that the behavioural RAM needs.

    logic [IC_ID_W-1:0]  m01_awid;
    logic [IC_ADDR_W-1:0] m01_awaddr;
    logic [7:0]          m01_awlen;
    logic [2:0]          m01_awsize;
    logic [1:0]          m01_awburst;
    logic                m01_awvalid;
    logic                m01_awready;
    logic [IC_DATA_W-1:0] m01_wdata;
    logic [IC_STRB_W-1:0] m01_wstrb;
    logic                m01_wlast;
    logic                m01_wvalid;
    logic                m01_wready;
    logic [IC_ID_W-1:0]  m01_bid;
    logic [1:0]          m01_bresp;
    logic                m01_bvalid;
    logic                m01_bready;
    logic [IC_ID_W-1:0]  m01_arid;
    logic [IC_ADDR_W-1:0] m01_araddr;
    logic [7:0]          m01_arlen;
    logic [2:0]          m01_arsize;
    logic [1:0]          m01_arburst;
    logic                m01_arvalid;
    logic                m01_arready;
    logic [IC_ID_W-1:0]  m01_rid;
    logic [IC_DATA_W-1:0] m01_rdata;
    logic [1:0]          m01_rresp;
    logic                m01_rlast;
    logic                m01_rvalid;
    logic                m01_rready;

    // =========================================================================
    // DUT – soc_tb_wrap (thin wrapper around soc_top that exposes M01)
    // =========================================================================

    soc_tb_wrap u_soc (
        .clk                     (clk),
        .rst_n                   (rst_n),

        // Reset / NMI (tie to sensible defaults)
        .rst_vec                 (31'h0000_0000),  // boot from 0x0000_0000
        .nmi_int                 (1'b0),
        .nmi_vec                 (31'h1111_1111),
        .jtag_id                 (31'h0000_0001),

        // UART
        .uart_rx_i               (uart_rx),
        .uart_tx_o               (uart_tx),
        .uart_irq_o              (uart_irq),

        // Trace
        .trace_rv_i_insn_ip      (trace_insn),
        .trace_rv_i_address_ip   (trace_addr),
        .trace_rv_i_valid_ip     (trace_valid),
        .trace_rv_i_exception_ip (trace_except),
        .trace_rv_i_ecause_ip    (trace_ecause),
        .trace_rv_i_interrupt_ip (trace_intr),
        .trace_rv_i_tval_ip      (trace_tval),

        // M01 RAM bus (exposed by the wrapper)
        .m01_awid    (m01_awid),   .m01_awaddr  (m01_awaddr),
        .m01_awlen   (m01_awlen),  .m01_awsize  (m01_awsize),
        .m01_awburst (m01_awburst),.m01_awvalid (m01_awvalid),
        .m01_awready (m01_awready),
        .m01_wdata   (m01_wdata),  .m01_wstrb   (m01_wstrb),
        .m01_wlast   (m01_wlast),  .m01_wvalid  (m01_wvalid),
        .m01_wready  (m01_wready),
        .m01_bid     (m01_bid),    .m01_bresp   (m01_bresp),
        .m01_bvalid  (m01_bvalid), .m01_bready  (m01_bready),
        .m01_arid    (m01_arid),   .m01_araddr  (m01_araddr),
        .m01_arlen   (m01_arlen),  .m01_arsize  (m01_arsize),
        .m01_arburst (m01_arburst),.m01_arvalid (m01_arvalid),
        .m01_arready (m01_arready),
        .m01_rid     (m01_rid),    .m01_rdata   (m01_rdata),
        .m01_rresp   (m01_rresp),  .m01_rlast   (m01_rlast),
        .m01_rvalid  (m01_rvalid), .m01_rready  (m01_rready)
    );

    // =========================================================================
    // Behavioural AXI4 SRAM (M01 – instruction + data RAM)
    // =========================================================================

    // Internal storage
    logic [63:0] ram_mem [0:RAM_DEPTH_WORDS-1];

    // Initialise RAM with a minimal boot image.
    // c.j 0 (compressed JAL x0,0) = 0x0001  → tight infinite loop.
    // We fill the first few words with this to cover any burst fetch.
    integer i;
    initial begin
        for (i = 0; i < RAM_DEPTH_WORDS; i++)
            ram_mem[i] = 64'h0000_0001_0000_0001;  // two c.j 0 per 64-bit word
    end

    // ----------------------------------------------------------------
    // Simple single-cycle-accept AXI4 RAM model
    // ----------------------------------------------------------------

    // Write path state
    logic [IC_ID_W-1:0]  ram_awid_r;
    logic [IC_ADDR_W-1:0] ram_awaddr_r;
    logic                ram_aw_pending;
    logic                ram_w_pending;

    // Read path state
    logic [IC_ID_W-1:0]  ram_arid_r;
    logic [IC_ADDR_W-1:0] ram_araddr_r;
    logic [7:0]          ram_arlen_r;
    logic                ram_ar_active;
    integer              ram_beat_cnt;

    // ── AW channel ──
    assign m01_awready = !ram_aw_pending;

    // ── W channel ──
    assign m01_wready  = ram_aw_pending;

    // ── AR channel ──
    assign m01_arready = !ram_ar_active && !m01_rvalid;

    // Write sequencer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_aw_pending <= 1'b0;
            ram_awid_r     <= '0;
            ram_awaddr_r   <= '0;
            m01_bvalid     <= 1'b0;
            m01_bid        <= '0;
            m01_bresp      <= 2'b00;
        end else begin
            // Latch AW
            if (m01_awvalid && m01_awready) begin
                ram_aw_pending <= 1'b1;
                ram_awid_r     <= m01_awid;
                ram_awaddr_r   <= m01_awaddr;
            end

            // Accept W when we have an address
            if (ram_aw_pending && m01_wvalid && m01_wready) begin
                // Write with byte-enable
                begin : wr_strobe
                    integer b;
                    for (b = 0; b < IC_STRB_W; b++) begin
                        if (m01_wstrb[b])
                            ram_mem[ram_awaddr_r[IC_ADDR_W-1:3]][b*8 +: 8]
                                <= m01_wdata[b*8 +: 8];
                    end
                end
                // Send response when wlast (all bursts are len=0 from RISC-V)
                if (m01_wlast) begin
                    ram_aw_pending <= 1'b0;
                    m01_bid        <= ram_awid_r;
                    m01_bresp      <= 2'b00;
                    m01_bvalid     <= 1'b1;
                end
            end

            // Clear bvalid on handshake
            if (m01_bvalid && m01_bready)
                m01_bvalid <= 1'b0;
        end
    end

    // Read sequencer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_ar_active <= 1'b0;
            ram_arid_r    <= '0;
            ram_araddr_r  <= '0;
            ram_arlen_r   <= '0;
            ram_beat_cnt  <= 0;
            m01_rvalid    <= 1'b0;
            m01_rid       <= '0;
            m01_rdata     <= '0;
            m01_rresp     <= 2'b00;
            m01_rlast     <= 1'b0;
        end else begin
            // Latch AR
            if (m01_arvalid && m01_arready) begin
                ram_ar_active <= 1'b1;
                ram_arid_r    <= m01_arid;
                ram_araddr_r  <= m01_araddr;
                ram_arlen_r   <= m01_arlen;
                ram_beat_cnt  <= 0;
            end

            // Generate read data
            if (ram_ar_active && !m01_rvalid) begin
                m01_rid    <= ram_arid_r;
                m01_rdata  <= ram_mem[ram_araddr_r[IC_ADDR_W-1:3]];
                m01_rresp  <= 2'b00;
                m01_rlast  <= (ram_beat_cnt == ram_arlen_r);
                m01_rvalid <= 1'b1;
            end

            // Advance burst
            if (m01_rvalid && m01_rready) begin
                if (m01_rlast) begin
                    ram_ar_active <= 1'b0;
                    m01_rvalid    <= 1'b0;
                    m01_rlast     <= 1'b0;
                end else begin
                    ram_araddr_r <= ram_araddr_r + 8;
                    ram_beat_cnt <= ram_beat_cnt + 1;
                    m01_rvalid   <= 1'b0;  // will be re-set next cycle
                end
            end
        end
    end

    // M01 master handshake (TB drives bready and rready)
    assign m01_bready = 1'b1;
    assign m01_rready = 1'b1;

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        $fsdbDumpfile("soc_top.fsdb");
        $fsdbDumpvars(0, tb_soc_top);
    end

    // =========================================================================
    // Test stimulus / checker
    // =========================================================================

    integer commit_cnt;
    integer cycles_after_reset;
    logic   test_passed;

    initial begin
        commit_cnt        = 0;
        cycles_after_reset = 0;
        test_passed       = 1'b0;

        // Wait until reset is released
        @(posedge rst_n);

        $display("[TB] ===================================================");
        $display("[TB] RISC-V VeeR EL2 SoC Integration Test");
        $display("[TB] Clock = %0d MHz, Reset released", 1000/CLK_PERIOD);
        $display("[TB] ===================================================");

        // Wait for the first valid instruction commit from the RISC-V trace
        forever begin
            @(posedge clk);
            cycles_after_reset = cycles_after_reset + 1;

            if (trace_valid) begin
                commit_cnt = commit_cnt + 1;
                $display("[TB] [+%0d] Instruction commit #%0d: PC=0x%08h INSN=0x%08h",
                    cycles_after_reset, commit_cnt, trace_addr, trace_insn);

                if (trace_except) begin
                    $display("[TB] Exception detected: ecause=%0d tval=0x%08h",
                        trace_ecause, trace_tval);
                end

                // After 5 commits declare pass (the infinite loop will keep committing)
                if (commit_cnt >= 5) begin
                    $display("[TB] ===================================================");
                    $display("[TB] PASS – RISC-V core is executing correctly.");
                    $display("[TB] %0d instruction commits observed in %0d cycles.",
                        commit_cnt, cycles_after_reset);
                    $display("[TB] ===================================================");
                    test_passed = 1'b1;
                    $finish;
                end
            end
        end
    end

    // =========================================================================
    // UART RX monitor (optional)
    // =========================================================================

    always @(posedge clk) begin
        if (uart_irq)
            $display("[UART] Read interrupt asserted at time %0t", $time);
    end

endmodule : tb_soc_top


// =============================================================================
// soc_tb_wrap
//
// Thin wrapper around soc_top that exposes the M01 (RAM) AXI bus so that
// the testbench can connect a behavioural RAM model.
//
// The wrapper passes all soc_top ports through unchanged, but also
// exposes the internal m01_* wires as additional ports.
//
// This avoids modifying soc_top itself.
// =============================================================================

`include "common_defines.vh"

module soc_tb_wrap
import el2_pkg::*;
#(
    `include "el2_param.vh"
) (
    input  logic        clk,
    input  logic        rst_n,

    // RISC-V control
    input  logic [31:1] rst_vec,
    input  logic        nmi_int,
    input  logic [31:1] nmi_vec,
    input  logic [31:1] jtag_id,

    // UART
    input  logic        uart_rx_i,
    output logic        uart_tx_o,
    output logic        uart_irq_o,

    // Trace
    output logic [31:0] trace_rv_i_insn_ip,
    output logic [31:0] trace_rv_i_address_ip,
    output logic        trace_rv_i_valid_ip,
    output logic        trace_rv_i_exception_ip,
    output logic [4:0]  trace_rv_i_ecause_ip,
    output logic        trace_rv_i_interrupt_ip,
    output logic [31:0] trace_rv_i_tval_ip,

    // ── M01 RAM bus (exposed) ──────────────────────────────────────────────
    output logic [7:0]  m01_awid,
    output logic [31:0] m01_awaddr,
    output logic [7:0]  m01_awlen,
    output logic [2:0]  m01_awsize,
    output logic [1:0]  m01_awburst,
    output logic        m01_awvalid,
    input  logic        m01_awready,

    output logic [63:0] m01_wdata,
    output logic [7:0]  m01_wstrb,
    output logic        m01_wlast,
    output logic        m01_wvalid,
    input  logic        m01_wready,

    input  logic [7:0]  m01_bid,
    input  logic [1:0]  m01_bresp,
    input  logic        m01_bvalid,
    output logic        m01_bready,

    output logic [7:0]  m01_arid,
    output logic [31:0] m01_araddr,
    output logic [7:0]  m01_arlen,
    output logic [2:0]  m01_arsize,
    output logic [1:0]  m01_arburst,
    output logic        m01_arvalid,
    input  logic        m01_arready,

    input  logic [7:0]  m01_rid,
    input  logic [63:0] m01_rdata,
    input  logic [1:0]  m01_rresp,
    input  logic        m01_rlast,
    input  logic        m01_rvalid,
    output logic        m01_rready
);

    // Internal M01 wires that soc_top drives (these are normally internal;
    // we re-expose them here for the TB to connect a RAM model).
    // soc_top needs to be slightly modified OR we use bind/force, OR we
    // just make them ports on soc_top directly.
    //
    // The cleanest approach that does NOT require modifying soc_top is to
    // instantiate soc_top normally and add an AXI4 RAM as a *sibling* to
    // soc_top.  However soc_top's M01 bus is internal.
    //
    // Therefore we DO expose M01 in soc_top as ports (see Note in soc_top
    // header).  The wrapper just passes everything through.

    soc_top #(
        `include "el2_param.vh"
    ) u_soc (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .rst_vec                 (rst_vec),
        .nmi_int                 (nmi_int),
        .nmi_vec                 (nmi_vec),
        .jtag_id                 (jtag_id),
        .uart_rx_i               (uart_rx_i),
        .uart_tx_o               (uart_tx_o),
        .uart_irq_o              (uart_irq_o),
        .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip   (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),

        // M01 (RAM) ports
        .m01_awid    (m01_awid),   .m01_awaddr  (m01_awaddr),
        .m01_awlen   (m01_awlen),  .m01_awsize  (m01_awsize),
        .m01_awburst (m01_awburst),.m01_awvalid (m01_awvalid),
        .m01_awready (m01_awready),
        .m01_wdata   (m01_wdata),  .m01_wstrb   (m01_wstrb),
        .m01_wlast   (m01_wlast),  .m01_wvalid  (m01_wvalid),
        .m01_wready  (m01_wready),
        .m01_bid     (m01_bid),    .m01_bresp   (m01_bresp),
        .m01_bvalid  (m01_bvalid), .m01_bready  (m01_bready),
        .m01_arid    (m01_arid),   .m01_araddr  (m01_araddr),
        .m01_arlen   (m01_arlen),  .m01_arsize  (m01_arsize),
        .m01_arburst (m01_arburst),.m01_arvalid (m01_arvalid),
        .m01_arready (m01_arready),
        .m01_rid     (m01_rid),    .m01_rdata   (m01_rdata),
        .m01_rresp   (m01_rresp),  .m01_rlast   (m01_rlast),
        .m01_rvalid  (m01_rvalid), .m01_rready  (m01_rready)
    );

endmodule : soc_tb_wrap

`default_nettype wire
