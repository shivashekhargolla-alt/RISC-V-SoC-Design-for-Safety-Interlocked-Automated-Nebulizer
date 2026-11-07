// =============================================================================
// Top-Level UVM Testbench Module for NebuCore SoC (tb_top_uvm)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

import uvm_pkg::*;
`include "uvm_macros.svh"

import uart_pkg::*;
import gpio_pkg::*;
import pwm_pkg::*;
import seg7_pkg::*;
import soc_core_pkg::*;
import axi4_pkg::*;
import axi_lite_pkg::*;
import soc_env_pkg::*;
import soc_uvm_pkg::*;

module tb_top_uvm;

    // ── Parameters ───────────────────────────────────────────────────────────
    localparam CLK_PERIOD       = 10;                // 100 MHz
    localparam RST_CYCLES       = 20;
    localparam RAM_DEPTH_BYTES  = 64 * 1024;         // 64 KiB
    localparam RAM_DEPTH_WORDS  = RAM_DEPTH_BYTES / 8; // 64-bit words

    localparam IC_DATA_W        = 64;
    localparam IC_ADDR_W        = 32;
    localparam IC_ID_W          = 8;
    localparam IC_STRB_W        = IC_DATA_W / 8;

    // ── Clock & Reset ────────────────────────────────────────────────────────
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (RST_CYCLES) @(posedge clk);
        #1;
        rst_n = 1'b1;
        `uvm_info("TB_TOP", "Reset de-asserted, SoC starting...", UVM_LOW)
    end

    // ── VIP Interfaces ───────────────────────────────────────────────────────
    uart_if     u_uart_if    (.clk(clk), .rst_n(rst_n));
    gpio_if     u_gpio_if    (.clk(clk), .rst_n(rst_n));
    pwm_if      u_pwm_if     (.clk(clk), .rst_n(rst_n));
    seg7_if     u_seg7_if    (.clk(clk), .rst_n(rst_n));
    soc_core_if u_core_if    (.clk(clk), .rst_n(rst_n));
    axi4_if     u_axi4_if    (.clk(clk), .rst_n(rst_n));
    axi_lite_if u_axi_lite_if(.clk(clk), .rst_n(rst_n));

    // ── M01 AXI Bus Wires ────────────────────────────────────────────────────
    logic [IC_ID_W-1:0]   m01_awid;
    logic [IC_ADDR_W-1:0] m01_awaddr;
    logic [7:0]           m01_awlen;
    logic [2:0]           m01_awsize;
    logic [1:0]           m01_awburst;
    logic                 m01_awvalid;
    logic                 m01_awready;

    logic [IC_DATA_W-1:0] m01_wdata;
    logic [IC_STRB_W-1:0] m01_wstrb;
    logic                 m01_wlast;
    logic                 m01_wvalid;
    logic                 m01_wready;

    logic [IC_ID_W-1:0]   m01_bid;
    logic [1:0]           m01_bresp;
    logic                 m01_bvalid;
    logic                 m01_bready;

    logic [IC_ID_W-1:0]   m01_arid;
    logic [IC_ADDR_W-1:0] m01_araddr;
    logic [7:0]           m01_arlen;
    logic [2:0]           m01_arsize;
    logic [1:0]           m01_arburst;
    logic                 m01_arvalid;
    logic                 m01_arready;

    logic [IC_ID_W-1:0]   m01_rid;
    logic [IC_DATA_W-1:0] m01_rdata;
    logic [1:0]           m01_rresp;
    logic                 m01_rlast;
    logic                 m01_rvalid;
    logic                 m01_rready;

    // Connect AXI4 VIP monitor to M01 bus wires for fabric observation
    assign u_axi4_if.awid    = m01_awid;
    assign u_axi4_if.awaddr  = m01_awaddr;
    assign u_axi4_if.awlen   = m01_awlen;
    assign u_axi4_if.awsize  = m01_awsize;
    assign u_axi4_if.awburst = m01_awburst;
    assign u_axi4_if.awvalid = m01_awvalid;
    assign u_axi4_if.awready = m01_awready;
    assign u_axi4_if.wdata   = m01_wdata;
    assign u_axi4_if.wstrb   = m01_wstrb;
    assign u_axi4_if.wlast   = m01_wlast;
    assign u_axi4_if.wvalid  = m01_wvalid;
    assign u_axi4_if.wready  = m01_wready;
    assign u_axi4_if.bid     = m01_bid;
    assign u_axi4_if.bresp   = m01_bresp;
    assign u_axi4_if.bvalid  = m01_bvalid;
    assign u_axi4_if.bready  = m01_bready;
    assign u_axi4_if.arid    = m01_arid;
    assign u_axi4_if.araddr  = m01_araddr;
    assign u_axi4_if.arlen   = m01_arlen;
    assign u_axi4_if.arsize  = m01_arsize;
    assign u_axi4_if.arburst = m01_arburst;
    assign u_axi4_if.arvalid = m01_arvalid;
    assign u_axi4_if.arready = m01_arready;
    assign u_axi4_if.rid     = m01_rid;
    assign u_axi4_if.rdata   = m01_rdata;
    assign u_axi4_if.rresp   = m01_rresp;
    assign u_axi4_if.rlast   = m01_rlast;
    assign u_axi4_if.rvalid  = m01_rvalid;
    assign u_axi4_if.rready  = m01_rready;

    // ── Behavioural AXI4 SRAM ────────────────────────────────────────────────
    logic [63:0] ram_mem [0:RAM_DEPTH_WORDS-1];
    string fw_file;

    initial begin
        for (int i = 0; i < RAM_DEPTH_WORDS; i++) begin
            ram_mem[i] = 64'h0;
        end
        if (!$value$plusargs("fw_hex=%s", fw_file)) begin
            fw_file = "firmware/soc_uvm_test.hex";
        end
        $readmemh(fw_file, ram_mem);
        `uvm_info("TB_TOP", $sformatf("RAM loaded with firmware hex: %s", fw_file), UVM_LOW)
    end

    // RAM completion marker connection
    assign u_core_if.completion_marker = ram_mem[32'h1000 >> 3][31:0];

    // Synchronize test mode to RAM[0x1004]
    always @(u_core_if.test_mode) begin
        ram_mem[32'h1004 >> 3][63:32] = u_core_if.test_mode;
    end

    // ----------------------------------------------------------------
    // Simple single-cycle-accept AXI4 RAM model
    // ----------------------------------------------------------------

    // Write path state
    logic [IC_ID_W-1:0]   ram_awid_r;
    logic [IC_ADDR_W-1:0] ram_awaddr_r;
    logic                 ram_aw_pending;

    // Read path state
    logic [IC_ID_W-1:0]   ram_arid_r;
    logic [IC_ADDR_W-1:0] ram_araddr_r;
    logic [7:0]           ram_arlen_r;
    logic                 ram_ar_active;
    integer               ram_beat_cnt;

    // ── AW channel ──
    assign m01_awready = !ram_aw_pending;

    // ── W channel ──
    assign m01_wready  = ram_aw_pending;

    // ── AR channel ──
    assign m01_arready = !ram_ar_active && !m01_rvalid;

    // Write sequencer
    always @(posedge clk or negedge rst_n) begin
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
                    m01_rvalid   <= 1'b0;
                end
            end
        end
    end

    // ── DUT Instantiation (soc_tb_wrap) ──────────────────────────────────────
    soc_tb_wrap u_soc (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .rst_vec                 (31'h0000_0000),
        .nmi_int                 (1'b0),
        .nmi_vec                 (31'h0000_0000),
        .jtag_id                 (31'h0000_0000),

        // UART
        .uart_rx_i               (u_uart_if.uart_rx_i),
        .uart_tx_o               (u_uart_if.uart_tx_o),
        .uart_irq_o              (u_uart_if.uart_irq_o),

        // GPIO
        .gpio_pin_i              (u_gpio_if.gpio_pin_i),
        .gpio_pin_o              (u_gpio_if.gpio_pin_o),
        .gpio_pin_oe             (u_gpio_if.gpio_pin_oe),
        .gpio_irq_o              (u_gpio_if.gpio_irq_o),

        // PWM & Safety
        .pwm_force_disable_i     (u_pwm_if.pwm_force_disable_i),
        .pwm_out_o               (u_pwm_if.pwm_out_o),

        // Seven-Segment
        .seg_out_o               (u_seg7_if.seg_out_o),
        .digit_sel_o             (u_seg7_if.digit_sel_o),

        // Timer & WDT
        .timer_irq_o             (),
        .timer_done_o            (),
        .wdt_trigger_i           (1'b0),
        .wdt_locked_o            (),
        .wdt_irq_o               (),
        .alarm_out_o             (),

        // RISC-V Trace
        .trace_rv_i_insn_ip      (u_core_if.trace_insn),
        .trace_rv_i_address_ip   (u_core_if.trace_addr),
        .trace_rv_i_valid_ip     (u_core_if.trace_valid),
        .trace_rv_i_exception_ip (u_core_if.trace_except),
        .trace_rv_i_ecause_ip    (u_core_if.trace_ecause),
        .trace_rv_i_interrupt_ip (u_core_if.trace_intr),
        .trace_rv_i_tval_ip      (u_core_if.trace_tval),

        // AXI M01 RAM
        .m01_awid                (m01_awid),
        .m01_awaddr              (m01_awaddr),
        .m01_awlen               (m01_awlen),
        .m01_awsize              (m01_awsize),
        .m01_awburst             (m01_awburst),
        .m01_awvalid             (m01_awvalid),
        .m01_awready             (m01_awready),
        .m01_wdata               (m01_wdata),
        .m01_wstrb               (m01_wstrb),
        .m01_wlast               (m01_wlast),
        .m01_wvalid              (m01_wvalid),
        .m01_wready              (m01_wready),
        .m01_bid                 (m01_bid),
        .m01_bresp               (m01_bresp),
        .m01_bvalid              (m01_bvalid),
        .m01_bready              (m01_bready),
        .m01_arid                (m01_arid),
        .m01_araddr              (m01_araddr),
        .m01_arlen               (m01_arlen),
        .m01_arsize              (m01_arsize),
        .m01_arburst             (m01_arburst),
        .m01_arvalid             (m01_arvalid),
        .m01_arready             (m01_arready),
        .m01_rid                 (m01_rid),
        .m01_rdata               (m01_rdata),
        .m01_rresp               (m01_rresp),
        .m01_rlast               (m01_rlast),
        .m01_rvalid              (m01_rvalid),
        .m01_rready              (m01_rready)
    );

    // ── Dedicated Real-Time Probes for Verdi & Simulation Log ─────────────────
    logic [7:0]  cpu_read_uart_data;
    logic        cpu_read_uart_valid;
    logic [31:0] ram_write_data;
    logic [31:0] ram_write_addr;
    logic        ram_write_valid;

    assign cpu_read_uart_valid = (u_soc.u_soc.uart_araddr[4:0] == 5'h00) && 
                                 u_soc.u_soc.uart_rvalid && u_soc.u_soc.uart_rready;
    assign cpu_read_uart_data  = cpu_read_uart_valid ? u_soc.u_soc.uart_rdata[7:0] : 8'h00;

    assign ram_write_valid     = (u_axi4_if.awaddr == 32'h0000_2000) && 
                                 u_axi4_if.wvalid && u_axi4_if.wready;
    assign ram_write_addr      = u_axi4_if.awaddr;
    assign ram_write_data      = ram_write_valid ? u_axi4_if.wdata[31:0] : 32'h0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (cpu_read_uart_valid) begin
                `uvm_info("DATA_MONITOR", $sformatf(">>> [CPU AXI READ] RISC-V Core read UART byte: 0x%02h ('%c') from UART_RBR via AXI4",
                          cpu_read_uart_data, cpu_read_uart_data), UVM_NONE)
            end
            if (ram_write_valid) begin
                `uvm_info("DATA_MONITOR", $sformatf(">>> [RAM AXI WRITE] RISC-V Core wrote word: 0x%08h (\"RISC\") into RAM[0x2000]",
                          ram_write_data), UVM_NONE)
            end
        end
    end

    // ── UART TX Console Mirror ───────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && u_soc.u_soc.u_uart.tx_fifo_push_int) begin
            $write("%c", u_soc.u_soc.u_uart.tx_fifo_data_in_int);
        end
    end

    // ── Waveform Dump for Verdi ──────────────────────────────────────────────
    `ifdef FSDB
    initial begin
        $display("[UVM-TB] Enabling full FSDB waveform dumping for Verdi...");
        $fsdbDumpfile("soc_top.fsdb");
        $fsdbDumpvars(0, tb_top_uvm, "+all", "+mda", "+struct", "+parameter");
        $fsdbDumpflush;
    end
    `endif

    // ── UVM Test Start ───────────────────────────────────────────────────────
    initial begin
        // Set virtual interfaces in config db
        uvm_config_db #(virtual uart_if)::set(null, "*", "uart_vif", u_uart_if);
        uvm_config_db #(virtual gpio_if)::set(null, "*", "gpio_vif", u_gpio_if);
        uvm_config_db #(virtual pwm_if)::set(null, "*", "pwm_vif", u_pwm_if);
        uvm_config_db #(virtual seg7_if)::set(null, "*", "seg7_vif", u_seg7_if);
        uvm_config_db #(virtual soc_core_if)::set(null, "*", "core_vif", u_core_if);
        uvm_config_db #(virtual axi4_if)::set(null, "*", "axi4_vif", u_axi4_if);
        uvm_config_db #(virtual axi_lite_if)::set(null, "*", "axi_lite_vif", u_axi_lite_if);

        // Run selected UVM test (defaulting to soc_all_test)
        run_test("soc_all_test");
    end

endmodule

`default_nettype wire
