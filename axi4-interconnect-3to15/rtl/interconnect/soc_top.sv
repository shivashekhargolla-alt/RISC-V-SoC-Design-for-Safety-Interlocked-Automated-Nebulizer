// =============================================================================
// Module: soc_top
//
// Description:
//   Top-level SoC integration.
//
//   Components:
//     1. RISC-V VeeR EL2 (el2_veer_wrapper)
//          - LSU AXI  → Interconnect S00  (data load/store bus)
//          - IFU AXI  → Interconnect S01  (instruction fetch bus)
//          - SB  AXI  → Interconnect S02  (system bus / debug)
//          - DMA AXI  ← Interconnect M02  (not connected here; tied off)
//
//     2. AXI4 3×15 Interconnect (axi_interconnect_wrap_3x15)
//          DATA=64, ADDR=32, ID=8
//          S00 = RISC-V LSU bus  (master 0)
//          S01 = RISC-V IFU bus  (master 1)
//          S02 = RISC-V SB  bus  (master 2)
//          M00 = UART   (0x1000_0000, 24-bit window) ← via axi_width_adapter
//          M01 = DRAM / instruction+data memory (0x0000_0000, 30-bit window)
//          M04 = PWM Generator (0x1400_0000, 12-bit window) ← via axi_width_adapter
//          M02-M03, M05-M14 = unused (tied off internally via AXI error slaves)
//
//     3. UART AXI-Lite (axi_uart_top)
//          DATA=32, ADDR=5, ID=12
//          Connected via axi_width_adapter on Interconnect M00
//
//     4. PWM Generator AXI-Lite (axi_pwm_top)
//          DATA=32, ADDR=4, ID=12
//          Connected via axi_width_adapter on Interconnect M04
//          pwm_force_disable_i ← Watchdog Timer wdt_locked (future)
//
// Address map (as seen by the RISC-V cores):
//   0x0000_0000 - 0x3FFF_FFFF : RAM (M01, 30-bit window, 1 GiB)
//   0x1000_0000 - 0x10FF_FFFF : UART registers (M00, 24-bit window)
//   0x1400_0000 - 0x1400_0FFF : PWM Generator registers (M04, 12-bit window)
//
// NOTE:
//   - The RISC-V AXI bus IDs are 4-bit (LSU_BUS_TAG=4, IFU_BUS_TAG=4,
//     SB_BUS_TAG=4).  The interconnect uses 8-bit IDs.  The adapter is a
//     simple zero-extension; the MSBs that the interconnect appends are
//     stripped on the response path by truncating back to 4-bit.
//   - The RISC-V core uses `RV_BUILD_AXI4; the RISC-V source must be
//     compiled with +define+RV_BUILD_AXI4 (handled in the Makefile).
//
// Author: Auto-generated for RISC-V VeeR EL2 SoC integration
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

`include "common_defines.vh"   // provides `RV_BUILD_AXI4 etc.

module soc_top
import el2_pkg::*;
#(
    `include "el2_param.vh"
) (
    // -------------------------------------------------------------------------
    // Clock / reset (active-high synchronous reset)
    // -------------------------------------------------------------------------
    input  logic        clk,
    input  logic        rst_n,    // active-low reset (common to AXI world)

    // -------------------------------------------------------------------------
    // RISC-V control/debug
    // -------------------------------------------------------------------------
    input  logic [31:1] rst_vec,           // reset vector (tie to desired boot addr)
    input  logic        nmi_int,
    input  logic [31:1] nmi_vec,
    input  logic [31:1] jtag_id,

    // -------------------------------------------------------------------------
    // UART physical interface
    // -------------------------------------------------------------------------
    input  logic        uart_rx_i,
    output logic        uart_tx_o,
    output logic        uart_irq_o,

    // -------------------------------------------------------------------------
    // PWM Generator physical interface
    // -------------------------------------------------------------------------
    input  logic        pwm_force_disable_i, // Watchdog override → force pwm_out low
    output logic        pwm_out_o,           // PWM waveform to Piezo Driver

    // -------------------------------------------------------------------------
    // Trace (optional, may be left unconnected in the testbench)
    // -------------------------------------------------------------------------
    output logic [31:0] trace_rv_i_insn_ip,
    output logic [31:0] trace_rv_i_address_ip,
    output logic        trace_rv_i_valid_ip,
    output logic        trace_rv_i_exception_ip,
    output logic [4:0]  trace_rv_i_ecause_ip,
    output logic        trace_rv_i_interrupt_ip,
    output logic [31:0] trace_rv_i_tval_ip,

    // -------------------------------------------------------------------------
    // M01 RAM bus (exposed so testbench can connect a behavioural RAM model)
    // -------------------------------------------------------------------------
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

    // =========================================================================
    // Local parameters
    // =========================================================================

    // Interconnect parameters
    localparam IC_DATA_W = 64;
    localparam IC_ADDR_W = 32;
    localparam IC_ID_W   = 8;
    localparam IC_STRB_W = IC_DATA_W / 8;   // 8

    // RISC-V AXI bus tag widths (must match el2_veer_wrapper port widths)
    // Default config: LSU=4, IFU=4, SB=4, DMA=4
    localparam LSU_TAG = pt.LSU_BUS_TAG;
    localparam IFU_TAG = pt.IFU_BUS_TAG;
    localparam SB_TAG  = pt.SB_BUS_TAG;
    localparam DMA_TAG = pt.DMA_BUS_TAG;

    // UART parameters
    localparam UART_DATA_W = 32;
    localparam UART_ADDR_W = 5;
    localparam UART_ID_W   = 12;

    // PWM Generator parameters
    localparam PWM_DATA_W = 32;
    localparam PWM_ADDR_W = 4;
    localparam PWM_ID_W   = 12;

    // =========================================================================
    // Internal active-high reset for RISC-V (active-low rst_n → active-high)
    // =========================================================================
    logic rst_l;            // active-low reset for VeeR (same as rst_n)
    assign rst_l = rst_n;

    // =========================================================================
    // ─────────────────────────────────────────────────────────────────────────
    //  RISC-V ↔ Interconnect (S00/S01/S02) AXI wires
    // ─────────────────────────────────────────────────────────────────────────
    // Widths are at the interconnect side (IC_ID_W=8, IC_DATA_W=64).
    // RISC-V tag bits are narrower (4-bit); zero-extend on the request path
    // and truncate on the response path.
    // =========================================================================

    // ------------------------------------------------------------------
    // S00 – LSU bus
    // ------------------------------------------------------------------
    // AW
    logic [LSU_TAG-1:0]     rv_lsu_awid;
    logic [31:0]            rv_lsu_awaddr;
    logic [7:0]             rv_lsu_awlen;
    logic [2:0]             rv_lsu_awsize;
    logic [1:0]             rv_lsu_awburst;
    logic                   rv_lsu_awlock;
    logic [3:0]             rv_lsu_awcache;
    logic [2:0]             rv_lsu_awprot;
    logic [3:0]             rv_lsu_awqos;
    logic [3:0]             rv_lsu_awregion;
    logic                   rv_lsu_awvalid;
    logic                   rv_lsu_awready;
    // W
    logic [63:0]            rv_lsu_wdata;
    logic [7:0]             rv_lsu_wstrb;
    logic                   rv_lsu_wlast;
    logic                   rv_lsu_wvalid;
    logic                   rv_lsu_wready;
    // B
    logic                   rv_lsu_bvalid;
    logic                   rv_lsu_bready;
    logic [1:0]             rv_lsu_bresp;
    logic [LSU_TAG-1:0]     rv_lsu_bid;
    // AR
    logic [LSU_TAG-1:0]     rv_lsu_arid;
    logic [31:0]            rv_lsu_araddr;
    logic [3:0]             rv_lsu_arregion;
    logic [7:0]             rv_lsu_arlen;
    logic [2:0]             rv_lsu_arsize;
    logic [1:0]             rv_lsu_arburst;
    logic                   rv_lsu_arlock;
    logic [3:0]             rv_lsu_arcache;
    logic [2:0]             rv_lsu_arprot;
    logic [3:0]             rv_lsu_arqos;
    logic                   rv_lsu_arvalid;
    logic                   rv_lsu_arready;
    // R
    logic                   rv_lsu_rvalid;
    logic                   rv_lsu_rready;
    logic [LSU_TAG-1:0]     rv_lsu_rid;
    logic [63:0]            rv_lsu_rdata;
    logic [1:0]             rv_lsu_rresp;
    logic                   rv_lsu_rlast;

    // Wires at IC_ID_W for S00
    logic [IC_ID_W-1:0]     s00_awid;
    logic [IC_ID_W-1:0]     s00_bid;
    logic [IC_ID_W-1:0]     s00_arid;
    logic [IC_ID_W-1:0]     s00_rid;

    // Zero-extend RISC-V ID to interconnect width
    assign s00_awid        = {{(IC_ID_W-LSU_TAG){1'b0}}, rv_lsu_awid};
    assign s00_arid        = {{(IC_ID_W-LSU_TAG){1'b0}}, rv_lsu_arid};
    // Truncate interconnect response IDs back to RISC-V width
    assign rv_lsu_bid      = s00_bid[LSU_TAG-1:0];
    assign rv_lsu_rid      = s00_rid[LSU_TAG-1:0];

    // ------------------------------------------------------------------
    // S01 – IFU bus
    // ------------------------------------------------------------------
    // AW (IFU never uses write – tied to 0 / ignored)
    logic [IFU_TAG-1:0]     rv_ifu_awid;
    logic [31:0]            rv_ifu_awaddr;
    logic [7:0]             rv_ifu_awlen;
    logic [2:0]             rv_ifu_awsize;
    logic [1:0]             rv_ifu_awburst;
    logic                   rv_ifu_awlock;
    logic [3:0]             rv_ifu_awcache;
    logic [2:0]             rv_ifu_awprot;
    logic [3:0]             rv_ifu_awqos;
    logic [3:0]             rv_ifu_awregion;
    logic                   rv_ifu_awvalid;
    logic                   rv_ifu_awready;
    // W
    logic [63:0]            rv_ifu_wdata;
    logic [7:0]             rv_ifu_wstrb;
    logic                   rv_ifu_wlast;
    logic                   rv_ifu_wvalid;
    logic                   rv_ifu_wready;
    // B
    logic                   rv_ifu_bvalid;
    logic                   rv_ifu_bready;
    logic [1:0]             rv_ifu_bresp;
    logic [IFU_TAG-1:0]     rv_ifu_bid;
    // AR
    logic [IFU_TAG-1:0]     rv_ifu_arid;
    logic [31:0]            rv_ifu_araddr;
    logic [3:0]             rv_ifu_arregion;
    logic [7:0]             rv_ifu_arlen;
    logic [2:0]             rv_ifu_arsize;
    logic [1:0]             rv_ifu_arburst;
    logic                   rv_ifu_arlock;
    logic [3:0]             rv_ifu_arcache;
    logic [2:0]             rv_ifu_arprot;
    logic [3:0]             rv_ifu_arqos;
    logic                   rv_ifu_arvalid;
    logic                   rv_ifu_arready;
    // R
    logic                   rv_ifu_rvalid;
    logic                   rv_ifu_rready;
    logic [IFU_TAG-1:0]     rv_ifu_rid;
    logic [63:0]            rv_ifu_rdata;
    logic [1:0]             rv_ifu_rresp;
    logic                   rv_ifu_rlast;

    logic [IC_ID_W-1:0]     s01_awid;
    logic [IC_ID_W-1:0]     s01_bid;
    logic [IC_ID_W-1:0]     s01_arid;
    logic [IC_ID_W-1:0]     s01_rid;

    assign s01_awid        = {{(IC_ID_W-IFU_TAG){1'b0}}, rv_ifu_awid};
    assign s01_arid        = {{(IC_ID_W-IFU_TAG){1'b0}}, rv_ifu_arid};
    assign rv_ifu_bid      = s01_bid[IFU_TAG-1:0];
    assign rv_ifu_rid      = s01_rid[IFU_TAG-1:0];

    // ------------------------------------------------------------------
    // S02 – SB bus (debug system bus)
    // ------------------------------------------------------------------
    logic [SB_TAG-1:0]      rv_sb_awid;
    logic [31:0]            rv_sb_awaddr;
    logic [7:0]             rv_sb_awlen;
    logic [2:0]             rv_sb_awsize;
    logic [1:0]             rv_sb_awburst;
    logic                   rv_sb_awlock;
    logic [3:0]             rv_sb_awcache;
    logic [2:0]             rv_sb_awprot;
    logic [3:0]             rv_sb_awqos;
    logic [3:0]             rv_sb_awregion;
    logic                   rv_sb_awvalid;
    logic                   rv_sb_awready;
    logic [63:0]            rv_sb_wdata;
    logic [7:0]             rv_sb_wstrb;
    logic                   rv_sb_wlast;
    logic                   rv_sb_wvalid;
    logic                   rv_sb_wready;
    logic                   rv_sb_bvalid;
    logic                   rv_sb_bready;
    logic [1:0]             rv_sb_bresp;
    logic [SB_TAG-1:0]      rv_sb_bid;
    logic [SB_TAG-1:0]      rv_sb_arid;
    logic [31:0]            rv_sb_araddr;
    logic [3:0]             rv_sb_arregion;
    logic [7:0]             rv_sb_arlen;
    logic [2:0]             rv_sb_arsize;
    logic [1:0]             rv_sb_arburst;
    logic                   rv_sb_arlock;
    logic [3:0]             rv_sb_arcache;
    logic [2:0]             rv_sb_arprot;
    logic [3:0]             rv_sb_arqos;
    logic                   rv_sb_arvalid;
    logic                   rv_sb_arready;
    logic                   rv_sb_rvalid;
    logic                   rv_sb_rready;
    logic [SB_TAG-1:0]      rv_sb_rid;
    logic [63:0]            rv_sb_rdata;
    logic [1:0]             rv_sb_rresp;
    logic                   rv_sb_rlast;

    logic [IC_ID_W-1:0]     s02_awid;
    logic [IC_ID_W-1:0]     s02_bid;
    logic [IC_ID_W-1:0]     s02_arid;
    logic [IC_ID_W-1:0]     s02_rid;

    assign s02_awid        = {{(IC_ID_W-SB_TAG){1'b0}}, rv_sb_awid};
    assign s02_arid        = {{(IC_ID_W-SB_TAG){1'b0}}, rv_sb_arid};
    assign rv_sb_bid       = s02_bid[SB_TAG-1:0];
    assign rv_sb_rid       = s02_rid[SB_TAG-1:0];

    // =========================================================================
    // Interconnect M00 → axi_width_adapter → UART wires
    // =========================================================================

    // M00 (IC side, 64-bit)
    logic [IC_ID_W-1:0]     m00_awid;
    logic [IC_ADDR_W-1:0]   m00_awaddr;
    logic [7:0]             m00_awlen;
    logic [2:0]             m00_awsize;
    logic [1:0]             m00_awburst;
    logic                   m00_awlock;
    logic [3:0]             m00_awcache;
    logic [2:0]             m00_awprot;
    logic [3:0]             m00_awqos;
    logic                   m00_awvalid;
    logic                   m00_awready;
    logic [IC_DATA_W-1:0]   m00_wdata;
    logic [IC_STRB_W-1:0]   m00_wstrb;
    logic                   m00_wlast;
    logic                   m00_wvalid;
    logic                   m00_wready;
    logic [IC_ID_W-1:0]     m00_bid;
    logic [1:0]             m00_bresp;
    logic                   m00_bvalid;
    logic                   m00_bready;
    logic [IC_ID_W-1:0]     m00_arid;
    logic [IC_ADDR_W-1:0]   m00_araddr;
    logic [7:0]             m00_arlen;
    logic [2:0]             m00_arsize;
    logic [1:0]             m00_arburst;
    logic                   m00_arlock;
    logic [3:0]             m00_arcache;
    logic [2:0]             m00_arprot;
    logic [3:0]             m00_arqos;
    logic                   m00_arvalid;
    logic                   m00_arready;
    logic [IC_ID_W-1:0]     m00_rid;
    logic [IC_DATA_W-1:0]   m00_rdata;
    logic [1:0]             m00_rresp;
    logic                   m00_rlast;
    logic                   m00_rvalid;
    logic                   m00_rready;

    // UART AXI-Lite wires (32-bit data, 5-bit addr, 12-bit ID)
    logic [UART_ID_W-1:0]   uart_awid;
    logic [UART_ADDR_W-1:0] uart_awaddr;
    logic                   uart_awvalid;
    logic                   uart_awready;
    logic [UART_DATA_W-1:0] uart_wdata;
    logic [3:0]             uart_wstrb;
    logic                   uart_wvalid;
    logic                   uart_wready;
    logic [UART_ID_W-1:0]   uart_bid;
    logic [1:0]             uart_bresp;
    logic                   uart_bvalid;
    logic                   uart_bready;
    logic [UART_ID_W-1:0]   uart_arid;
    logic [UART_ADDR_W-1:0] uart_araddr;
    logic                   uart_arvalid;
    logic                   uart_arready;
    logic [UART_ID_W-1:0]   uart_rid;
    logic [UART_DATA_W-1:0] uart_rdata;
    logic [1:0]             uart_rresp;
    logic                   uart_rvalid;
    logic                   uart_rready;

    // =========================================================================
    // Interconnect M04 → axi_width_adapter → PWM Generator wires
    // =========================================================================

    // M04 (IC side, 64-bit)
    logic [IC_ID_W-1:0]     m04_awid;
    logic [IC_ADDR_W-1:0]   m04_awaddr;
    logic [7:0]             m04_awlen;
    logic [2:0]             m04_awsize;
    logic [1:0]             m04_awburst;
    logic                   m04_awlock;
    logic [3:0]             m04_awcache;
    logic [2:0]             m04_awprot;
    logic [3:0]             m04_awqos;
    logic                   m04_awvalid;
    logic                   m04_awready;
    logic [IC_DATA_W-1:0]   m04_wdata;
    logic [IC_STRB_W-1:0]   m04_wstrb;
    logic                   m04_wlast;
    logic                   m04_wvalid;
    logic                   m04_wready;
    logic [IC_ID_W-1:0]     m04_bid;
    logic [1:0]             m04_bresp;
    logic                   m04_bvalid;
    logic                   m04_bready;
    logic [IC_ID_W-1:0]     m04_arid;
    logic [IC_ADDR_W-1:0]   m04_araddr;
    logic [7:0]             m04_arlen;
    logic [2:0]             m04_arsize;
    logic [1:0]             m04_arburst;
    logic                   m04_arlock;
    logic [3:0]             m04_arcache;
    logic [2:0]             m04_arprot;
    logic [3:0]             m04_arqos;
    logic                   m04_arvalid;
    logic                   m04_arready;
    logic [IC_ID_W-1:0]     m04_rid;
    logic [IC_DATA_W-1:0]   m04_rdata;
    logic [1:0]             m04_rresp;
    logic                   m04_rlast;
    logic                   m04_rvalid;
    logic                   m04_rready;

    // PWM AXI-Lite wires (32-bit data, 4-bit addr, 12-bit ID)
    logic [PWM_ID_W-1:0]    pwm_awid;
    logic [PWM_ADDR_W-1:0]  pwm_awaddr;
    logic                   pwm_awvalid;
    logic                   pwm_awready;
    logic [PWM_DATA_W-1:0]  pwm_wdata;
    logic [3:0]             pwm_wstrb;
    logic                   pwm_wvalid;
    logic                   pwm_wready;
    logic [PWM_ID_W-1:0]    pwm_bid;
    logic [1:0]             pwm_bresp;
    logic                   pwm_bvalid;
    logic                   pwm_bready;
    logic [PWM_ID_W-1:0]    pwm_arid;
    logic [PWM_ADDR_W-1:0]  pwm_araddr;
    logic                   pwm_arvalid;
    logic                   pwm_arready;
    logic [PWM_ID_W-1:0]    pwm_rid;
    logic [PWM_DATA_W-1:0]  pwm_rdata;
    logic [1:0]             pwm_rresp;
    logic                   pwm_rvalid;
    logic                   pwm_rready;

    // =========================================================================
    // Interconnect M01 → On-chip RAM
    // M01 bus is exposed as module ports (see port list above) so that
    // the testbench can connect a behavioural RAM model externally.
    // The following signals are therefore PORTS, not local wires.
    // =========================================================================

    // Supplementary internal signals for M01 that are not exported as ports
    // (lock / cache / prot / qos – not needed externally)
    logic                   m01_awlock;
    logic [3:0]             m01_awcache;
    logic [2:0]             m01_awprot;
    logic [3:0]             m01_awqos;
    logic                   m01_arlock;
    logic [3:0]             m01_arcache;
    logic [2:0]             m01_arprot;
    logic [3:0]             m01_arqos;

    // =========================================================================
    // DMA bus tie-off (RISC-V DMA slave port – not used in this SoC)
    // =========================================================================
    // DMA is an AXI slave on the RISC-V side; nothing drives it here.
    logic                   dma_awvalid;
    logic                   dma_awready;
    logic [DMA_TAG-1:0]     dma_awid;
    logic [31:0]            dma_awaddr;
    logic [2:0]             dma_awsize;
    logic [2:0]             dma_awprot;
    logic [7:0]             dma_awlen;
    logic [1:0]             dma_awburst;
    logic                   dma_wvalid;
    logic                   dma_wready;
    logic [63:0]            dma_wdata;
    logic [7:0]             dma_wstrb;
    logic                   dma_wlast;
    logic                   dma_bvalid;
    logic                   dma_bready;
    logic [1:0]             dma_bresp;
    logic [DMA_TAG-1:0]     dma_bid;
    logic                   dma_arvalid;
    logic                   dma_arready;
    logic [DMA_TAG-1:0]     dma_arid;
    logic [31:0]            dma_araddr;
    logic [2:0]             dma_arsize;
    logic [2:0]             dma_arprot;
    logic [7:0]             dma_arlen;
    logic [1:0]             dma_arburst;
    logic                   dma_rvalid;
    logic                   dma_rready;
    logic [DMA_TAG-1:0]     dma_rid;
    logic [63:0]            dma_rdata;
    logic [1:0]             dma_rresp;
    logic                   dma_rlast;

    // Tie DMA inputs to zero (DMA port not used)
    assign dma_awvalid = 1'b0;
    assign dma_awid    = '0;
    assign dma_awaddr  = '0;
    assign dma_awsize  = '0;
    assign dma_awprot  = '0;
    assign dma_awlen   = '0;
    assign dma_awburst = '0;
    assign dma_wvalid  = 1'b0;
    assign dma_wdata   = '0;
    assign dma_wstrb   = '0;
    assign dma_wlast   = 1'b0;
    assign dma_bready  = 1'b1;
    assign dma_arvalid = 1'b0;
    assign dma_arid    = '0;
    assign dma_araddr  = '0;
    assign dma_arsize  = '0;
    assign dma_arprot  = '0;
    assign dma_arlen   = '0;
    assign dma_arburst = '0;
    assign dma_rready  = 1'b1;

    // =========================================================================
    // ─────────────────────────────────────────────────────────────────────────
    //  Interconnect M02-M14 tie-off wires (unused slave ports)
    // ─────────────────────────────────────────────────────────────────────────
    // These wires are driven from the interconnect master outputs; the IC
    // asserts valid on these ports when an unmapped address is used.  We
    // accept all AW/AR immediately and return SLVERR to prevent deadlock.
    // =========================================================================

    // Generate stub termination for M02-M14 is done inside the
    // axi_slave_stub_array module defined at the bottom of this file.
    // Declare the arrays here; the generate block below drives them.

    logic [IC_ID_W-1:0]     mx_awid    [2:14];
    logic [IC_ADDR_W-1:0]   mx_awaddr  [2:14];
    logic [7:0]             mx_awlen   [2:14];
    logic [2:0]             mx_awsize  [2:14];
    logic [1:0]             mx_awburst [2:14];
    logic                   mx_awvalid [2:14];
    logic                   mx_awready [2:14];
    logic [IC_DATA_W-1:0]   mx_wdata   [2:14];
    logic [IC_STRB_W-1:0]   mx_wstrb   [2:14];
    logic                   mx_wlast   [2:14];
    logic                   mx_wvalid  [2:14];
    logic                   mx_wready  [2:14];
    logic [IC_ID_W-1:0]     mx_bid     [2:14];
    logic [1:0]             mx_bresp   [2:14];
    logic                   mx_bvalid  [2:14];
    logic                   mx_bready  [2:14];
    logic [IC_ID_W-1:0]     mx_arid    [2:14];
    logic [IC_ADDR_W-1:0]   mx_araddr  [2:14];
    logic [7:0]             mx_arlen   [2:14];
    logic [2:0]             mx_arsize  [2:14];
    logic [1:0]             mx_arburst [2:14];
    logic                   mx_arvalid [2:14];
    logic                   mx_arready [2:14];
    logic [IC_ID_W-1:0]     mx_rid     [2:14];
    logic [IC_DATA_W-1:0]   mx_rdata   [2:14];
    logic [1:0]             mx_rresp   [2:14];
    logic                   mx_rlast   [2:14];
    logic                   mx_rvalid  [2:14];
    logic                   mx_rready  [2:14];

    // =========================================================================
    // ─────────────────────────────────────────────────────────────────────────
    //  Sub-module instantiations
    // ─────────────────────────────────────────────────────────────────────────
    // =========================================================================

    // =========================================================================
    //  1. RISC-V VeeR EL2 Core
    // =========================================================================

    el2_veer_wrapper #(
        `include "el2_param.vh"
    ) u_veer (
        .clk            (clk),
        .rst_l          (rst_l),
        .dbg_rst_l      (rst_l),
        .rst_vec        (rst_vec),
        .nmi_int        (nmi_int),
        .nmi_vec        (nmi_vec),
        .jtag_id        (jtag_id),

        // Trace
        .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip   (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),

`ifdef RV_BUILD_AXI4
        // ─── LSU AXI (S00) ───────────────────────────────────────────────
        .lsu_axi_awvalid  (rv_lsu_awvalid),
        .lsu_axi_awready  (rv_lsu_awready),
        .lsu_axi_awid     (rv_lsu_awid),
        .lsu_axi_awaddr   (rv_lsu_awaddr),
        .lsu_axi_awregion (rv_lsu_awregion),
        .lsu_axi_awlen    (rv_lsu_awlen),
        .lsu_axi_awsize   (rv_lsu_awsize),
        .lsu_axi_awburst  (rv_lsu_awburst),
        .lsu_axi_awlock   (rv_lsu_awlock),
        .lsu_axi_awcache  (rv_lsu_awcache),
        .lsu_axi_awprot   (rv_lsu_awprot),
        .lsu_axi_awqos    (rv_lsu_awqos),
        .lsu_axi_wvalid   (rv_lsu_wvalid),
        .lsu_axi_wready   (rv_lsu_wready),
        .lsu_axi_wdata    (rv_lsu_wdata),
        .lsu_axi_wstrb    (rv_lsu_wstrb),
        .lsu_axi_wlast    (rv_lsu_wlast),
        .lsu_axi_bvalid   (rv_lsu_bvalid),
        .lsu_axi_bready   (rv_lsu_bready),
        .lsu_axi_bresp    (rv_lsu_bresp),
        .lsu_axi_bid      (rv_lsu_bid),
        .lsu_axi_arvalid  (rv_lsu_arvalid),
        .lsu_axi_arready  (rv_lsu_arready),
        .lsu_axi_arid     (rv_lsu_arid),
        .lsu_axi_araddr   (rv_lsu_araddr),
        .lsu_axi_arregion (rv_lsu_arregion),
        .lsu_axi_arlen    (rv_lsu_arlen),
        .lsu_axi_arsize   (rv_lsu_arsize),
        .lsu_axi_arburst  (rv_lsu_arburst),
        .lsu_axi_arlock   (rv_lsu_arlock),
        .lsu_axi_arcache  (rv_lsu_arcache),
        .lsu_axi_arprot   (rv_lsu_arprot),
        .lsu_axi_arqos    (rv_lsu_arqos),
        .lsu_axi_rvalid   (rv_lsu_rvalid),
        .lsu_axi_rready   (rv_lsu_rready),
        .lsu_axi_rid      (rv_lsu_rid),
        .lsu_axi_rdata    (rv_lsu_rdata),
        .lsu_axi_rresp    (rv_lsu_rresp),
        .lsu_axi_rlast    (rv_lsu_rlast),

        // ─── IFU AXI (S01) ───────────────────────────────────────────────
        .ifu_axi_awvalid  (rv_ifu_awvalid),
        .ifu_axi_awready  (rv_ifu_awready),
        .ifu_axi_awid     (rv_ifu_awid),
        .ifu_axi_awaddr   (rv_ifu_awaddr),
        .ifu_axi_awregion (rv_ifu_awregion),
        .ifu_axi_awlen    (rv_ifu_awlen),
        .ifu_axi_awsize   (rv_ifu_awsize),
        .ifu_axi_awburst  (rv_ifu_awburst),
        .ifu_axi_awlock   (rv_ifu_awlock),
        .ifu_axi_awcache  (rv_ifu_awcache),
        .ifu_axi_awprot   (rv_ifu_awprot),
        .ifu_axi_awqos    (rv_ifu_awqos),
        .ifu_axi_wvalid   (rv_ifu_wvalid),
        .ifu_axi_wready   (rv_ifu_wready),
        .ifu_axi_wdata    (rv_ifu_wdata),
        .ifu_axi_wstrb    (rv_ifu_wstrb),
        .ifu_axi_wlast    (rv_ifu_wlast),
        .ifu_axi_bvalid   (rv_ifu_bvalid),
        .ifu_axi_bready   (rv_ifu_bready),
        .ifu_axi_bresp    (rv_ifu_bresp),
        .ifu_axi_bid      (rv_ifu_bid),
        .ifu_axi_arvalid  (rv_ifu_arvalid),
        .ifu_axi_arready  (rv_ifu_arready),
        .ifu_axi_arid     (rv_ifu_arid),
        .ifu_axi_araddr   (rv_ifu_araddr),
        .ifu_axi_arregion (rv_ifu_arregion),
        .ifu_axi_arlen    (rv_ifu_arlen),
        .ifu_axi_arsize   (rv_ifu_arsize),
        .ifu_axi_arburst  (rv_ifu_arburst),
        .ifu_axi_arlock   (rv_ifu_arlock),
        .ifu_axi_arcache  (rv_ifu_arcache),
        .ifu_axi_arprot   (rv_ifu_arprot),
        .ifu_axi_arqos    (rv_ifu_arqos),
        .ifu_axi_rvalid   (rv_ifu_rvalid),
        .ifu_axi_rready   (rv_ifu_rready),
        .ifu_axi_rid      (rv_ifu_rid),
        .ifu_axi_rdata    (rv_ifu_rdata),
        .ifu_axi_rresp    (rv_ifu_rresp),
        .ifu_axi_rlast    (rv_ifu_rlast),

        // ─── SB AXI (S02) ────────────────────────────────────────────────
        .sb_axi_awvalid  (rv_sb_awvalid),
        .sb_axi_awready  (rv_sb_awready),
        .sb_axi_awid     (rv_sb_awid),
        .sb_axi_awaddr   (rv_sb_awaddr),
        .sb_axi_awregion (rv_sb_awregion),
        .sb_axi_awlen    (rv_sb_awlen),
        .sb_axi_awsize   (rv_sb_awsize),
        .sb_axi_awburst  (rv_sb_awburst),
        .sb_axi_awlock   (rv_sb_awlock),
        .sb_axi_awcache  (rv_sb_awcache),
        .sb_axi_awprot   (rv_sb_awprot),
        .sb_axi_awqos    (rv_sb_awqos),
        .sb_axi_wvalid   (rv_sb_wvalid),
        .sb_axi_wready   (rv_sb_wready),
        .sb_axi_wdata    (rv_sb_wdata),
        .sb_axi_wstrb    (rv_sb_wstrb),
        .sb_axi_wlast    (rv_sb_wlast),
        .sb_axi_bvalid   (rv_sb_bvalid),
        .sb_axi_bready   (rv_sb_bready),
        .sb_axi_bresp    (rv_sb_bresp),
        .sb_axi_bid      (rv_sb_bid),
        .sb_axi_arvalid  (rv_sb_arvalid),
        .sb_axi_arready  (rv_sb_arready),
        .sb_axi_arid     (rv_sb_arid),
        .sb_axi_araddr   (rv_sb_araddr),
        .sb_axi_arregion (rv_sb_arregion),
        .sb_axi_arlen    (rv_sb_arlen),
        .sb_axi_arsize   (rv_sb_arsize),
        .sb_axi_arburst  (rv_sb_arburst),
        .sb_axi_arlock   (rv_sb_arlock),
        .sb_axi_arcache  (rv_sb_arcache),
        .sb_axi_arprot   (rv_sb_arprot),
        .sb_axi_arqos    (rv_sb_arqos),
        .sb_axi_rvalid   (rv_sb_rvalid),
        .sb_axi_rready   (rv_sb_rready),
        .sb_axi_rid      (rv_sb_rid),
        .sb_axi_rdata    (rv_sb_rdata),
        .sb_axi_rresp    (rv_sb_rresp),
        .sb_axi_rlast    (rv_sb_rlast),

        // ─── DMA AXI (not used) ──────────────────────────────────────────
        .dma_axi_awvalid (dma_awvalid),
        .dma_axi_awready (dma_awready),
        .dma_axi_awid    (dma_awid),
        .dma_axi_awaddr  (dma_awaddr),
        .dma_axi_awsize  (dma_awsize),
        .dma_axi_awprot  (dma_awprot),
        .dma_axi_awlen   (dma_awlen),
        .dma_axi_awburst (dma_awburst),
        .dma_axi_wvalid  (dma_wvalid),
        .dma_axi_wready  (dma_wready),
        .dma_axi_wdata   (dma_wdata),
        .dma_axi_wstrb   (dma_wstrb),
        .dma_axi_wlast   (dma_wlast),
        .dma_axi_bvalid  (dma_bvalid),
        .dma_axi_bready  (dma_bready),
        .dma_axi_bresp   (dma_bresp),
        .dma_axi_bid     (dma_bid),
        .dma_axi_arvalid (dma_arvalid),
        .dma_axi_arready (dma_arready),
        .dma_axi_arid    (dma_arid),
        .dma_axi_araddr  (dma_araddr),
        .dma_axi_arsize  (dma_arsize),
        .dma_axi_arprot  (dma_arprot),
        .dma_axi_arlen   (dma_arlen),
        .dma_axi_arburst (dma_arburst),
        .dma_axi_rvalid  (dma_rvalid),
        .dma_axi_rready  (dma_rready),
        .dma_axi_rid     (dma_rid),
        .dma_axi_rdata   (dma_rdata),
        .dma_axi_rresp   (dma_rresp),
        .dma_axi_rlast   (dma_rlast),
`endif // RV_BUILD_AXI4

        // ─── Miscellaneous ────────────────────────────────────────────────
        .lsu_bus_clk_en (1'b1),
        .ifu_bus_clk_en (1'b1),
        .dbg_bus_clk_en (1'b1),
        .dma_bus_clk_en (1'b1),

        // Interrupt controller (no external PIC in this SoC)
        .extintsrc_req  ('0),
        .timer_int      (1'b0),
        .soft_int       (1'b0),

        // MPC debug (tie off)
        .mpc_debug_halt_req (1'b0),
        .mpc_debug_run_req  (1'b1),
        .mpc_debug_halt_ack (),
        .mpc_debug_run_ack  (),

        // CPU halt/run (tie off)
        .i_cpu_halt_req (1'b0),
        .i_cpu_run_req  (1'b0),
        .o_cpu_halt_ack     (),
        .o_cpu_halt_status  (),
        .o_cpu_run_ack      (),
        .o_debug_mode_status(),

        .core_id        ('0),
        .scan_mode      (1'b0),
        .mbist_mode     (1'b0)
    );

    // =========================================================================
    //  2. AXI4 3×15 Interconnect
    // =========================================================================

    axi_interconnect_wrap_3x15 #(
        // Bus parameters
        .DATA_WIDTH (IC_DATA_W),
        .ADDR_WIDTH (IC_ADDR_W),
        .ID_WIDTH   (IC_ID_W),

        // M00 = UART  @ 0x1000_0000, 24-bit window (16 MiB)
        .M00_BASE_ADDR  (32'h1000_0000),
        .M00_ADDR_WIDTH ({1{32'd24}}),
        .M00_CONNECT_READ  (3'b111),
        .M00_CONNECT_WRITE (3'b111),

        // M01 = RAM   @ 0x0000_0000, 30-bit window (1 GiB)
        .M01_BASE_ADDR  (32'h0000_0000),
        .M01_ADDR_WIDTH ({1{32'd30}}),
        .M01_CONNECT_READ  (3'b111),
        .M01_CONNECT_WRITE (3'b111),

        // M04 = PWM Generator @ 0x1400_0000, 12-bit window (4 KiB)
        .M04_BASE_ADDR  (32'h1400_0000),
        .M04_ADDR_WIDTH ({1{32'd12}}),
        .M04_CONNECT_READ  (3'b111),
        .M04_CONNECT_WRITE (3'b111)

        // M02-M03, M05-M14: defaults (base=0, width=24) are fine;
        // they will never be reached in normal operation.
    ) u_interconnect (
        .clk (clk),
        .rst (~rst_n),   // interconnect uses active-high reset

        // ─── S00 = RISC-V LSU ─────────────────────────────────────────────
        .s00_axi_awid    (s00_awid),
        .s00_axi_awaddr  (rv_lsu_awaddr),
        .s00_axi_awlen   (rv_lsu_awlen),
        .s00_axi_awsize  (rv_lsu_awsize),
        .s00_axi_awburst (rv_lsu_awburst),
        .s00_axi_awlock  (rv_lsu_awlock),
        .s00_axi_awcache (rv_lsu_awcache),
        .s00_axi_awprot  (rv_lsu_awprot),
        .s00_axi_awqos   (rv_lsu_awqos),
        .s00_axi_awuser  ('0),
        .s00_axi_awvalid (rv_lsu_awvalid),
        .s00_axi_awready (rv_lsu_awready),
        .s00_axi_wdata   (rv_lsu_wdata),
        .s00_axi_wstrb   (rv_lsu_wstrb),
        .s00_axi_wlast   (rv_lsu_wlast),
        .s00_axi_wuser   ('0),
        .s00_axi_wvalid  (rv_lsu_wvalid),
        .s00_axi_wready  (rv_lsu_wready),
        .s00_axi_bid     (s00_bid),
        .s00_axi_bresp   (rv_lsu_bresp),
        .s00_axi_buser   (),
        .s00_axi_bvalid  (rv_lsu_bvalid),
        .s00_axi_bready  (rv_lsu_bready),
        .s00_axi_arid    (s00_arid),
        .s00_axi_araddr  (rv_lsu_araddr),
        .s00_axi_arlen   (rv_lsu_arlen),
        .s00_axi_arsize  (rv_lsu_arsize),
        .s00_axi_arburst (rv_lsu_arburst),
        .s00_axi_arlock  (rv_lsu_arlock),
        .s00_axi_arcache (rv_lsu_arcache),
        .s00_axi_arprot  (rv_lsu_arprot),
        .s00_axi_arqos   (rv_lsu_arqos),
        .s00_axi_aruser  ('0),
        .s00_axi_arvalid (rv_lsu_arvalid),
        .s00_axi_arready (rv_lsu_arready),
        .s00_axi_rid     (s00_rid),
        .s00_axi_rdata   (rv_lsu_rdata),
        .s00_axi_rresp   (rv_lsu_rresp),
        .s00_axi_rlast   (rv_lsu_rlast),
        .s00_axi_ruser   (),
        .s00_axi_rvalid  (rv_lsu_rvalid),
        .s00_axi_rready  (rv_lsu_rready),

        // ─── S01 = RISC-V IFU ─────────────────────────────────────────────
        .s01_axi_awid    (s01_awid),
        .s01_axi_awaddr  (rv_ifu_awaddr),
        .s01_axi_awlen   (rv_ifu_awlen),
        .s01_axi_awsize  (rv_ifu_awsize),
        .s01_axi_awburst (rv_ifu_awburst),
        .s01_axi_awlock  (rv_ifu_awlock),
        .s01_axi_awcache (rv_ifu_awcache),
        .s01_axi_awprot  (rv_ifu_awprot),
        .s01_axi_awqos   (rv_ifu_awqos),
        .s01_axi_awuser  ('0),
        .s01_axi_awvalid (rv_ifu_awvalid),
        .s01_axi_awready (rv_ifu_awready),
        .s01_axi_wdata   (rv_ifu_wdata),
        .s01_axi_wstrb   (rv_ifu_wstrb),
        .s01_axi_wlast   (rv_ifu_wlast),
        .s01_axi_wuser   ('0),
        .s01_axi_wvalid  (rv_ifu_wvalid),
        .s01_axi_wready  (rv_ifu_wready),
        .s01_axi_bid     (s01_bid),
        .s01_axi_bresp   (rv_ifu_bresp),
        .s01_axi_buser   (),
        .s01_axi_bvalid  (rv_ifu_bvalid),
        .s01_axi_bready  (rv_ifu_bready),
        .s01_axi_arid    (s01_arid),
        .s01_axi_araddr  (rv_ifu_araddr),
        .s01_axi_arlen   (rv_ifu_arlen),
        .s01_axi_arsize  (rv_ifu_arsize),
        .s01_axi_arburst (rv_ifu_arburst),
        .s01_axi_arlock  (rv_ifu_arlock),
        .s01_axi_arcache (rv_ifu_arcache),
        .s01_axi_arprot  (rv_ifu_arprot),
        .s01_axi_arqos   (rv_ifu_arqos),
        .s01_axi_aruser  ('0),
        .s01_axi_arvalid (rv_ifu_arvalid),
        .s01_axi_arready (rv_ifu_arready),
        .s01_axi_rid     (s01_rid),
        .s01_axi_rdata   (rv_ifu_rdata),
        .s01_axi_rresp   (rv_ifu_rresp),
        .s01_axi_rlast   (rv_ifu_rlast),
        .s01_axi_ruser   (),
        .s01_axi_rvalid  (rv_ifu_rvalid),
        .s01_axi_rready  (rv_ifu_rready),

        // ─── S02 = RISC-V SB ──────────────────────────────────────────────
        .s02_axi_awid    (s02_awid),
        .s02_axi_awaddr  (rv_sb_awaddr),
        .s02_axi_awlen   (rv_sb_awlen),
        .s02_axi_awsize  (rv_sb_awsize),
        .s02_axi_awburst (rv_sb_awburst),
        .s02_axi_awlock  (rv_sb_awlock),
        .s02_axi_awcache (rv_sb_awcache),
        .s02_axi_awprot  (rv_sb_awprot),
        .s02_axi_awqos   (rv_sb_awqos),
        .s02_axi_awuser  ('0),
        .s02_axi_awvalid (rv_sb_awvalid),
        .s02_axi_awready (rv_sb_awready),
        .s02_axi_wdata   (rv_sb_wdata),
        .s02_axi_wstrb   (rv_sb_wstrb),
        .s02_axi_wlast   (rv_sb_wlast),
        .s02_axi_wuser   ('0),
        .s02_axi_wvalid  (rv_sb_wvalid),
        .s02_axi_wready  (rv_sb_wready),
        .s02_axi_bid     (s02_bid),
        .s02_axi_bresp   (rv_sb_bresp),
        .s02_axi_buser   (),
        .s02_axi_bvalid  (rv_sb_bvalid),
        .s02_axi_bready  (rv_sb_bready),
        .s02_axi_arid    (s02_arid),
        .s02_axi_araddr  (rv_sb_araddr),
        .s02_axi_arlen   (rv_sb_arlen),
        .s02_axi_arsize  (rv_sb_arsize),
        .s02_axi_arburst (rv_sb_arburst),
        .s02_axi_arlock  (rv_sb_arlock),
        .s02_axi_arcache (rv_sb_arcache),
        .s02_axi_arprot  (rv_sb_arprot),
        .s02_axi_arqos   (rv_sb_arqos),
        .s02_axi_aruser  ('0),
        .s02_axi_arvalid (rv_sb_arvalid),
        .s02_axi_arready (rv_sb_arready),
        .s02_axi_rid     (s02_rid),
        .s02_axi_rdata   (rv_sb_rdata),
        .s02_axi_rresp   (rv_sb_rresp),
        .s02_axi_rlast   (rv_sb_rlast),
        .s02_axi_ruser   (),
        .s02_axi_rvalid  (rv_sb_rvalid),
        .s02_axi_rready  (rv_sb_rready),

        // ─── M00 = UART (via axi_width_adapter) ───────────────────────────
        .m00_axi_awid    (m00_awid),
        .m00_axi_awaddr  (m00_awaddr),
        .m00_axi_awlen   (m00_awlen),
        .m00_axi_awsize  (m00_awsize),
        .m00_axi_awburst (m00_awburst),
        .m00_axi_awlock  (m00_awlock),
        .m00_axi_awcache (m00_awcache),
        .m00_axi_awprot  (m00_awprot),
        .m00_axi_awqos   (m00_awqos),
        .m00_axi_awregion(),
        .m00_axi_awuser  (),
        .m00_axi_awvalid (m00_awvalid),
        .m00_axi_awready (m00_awready),
        .m00_axi_wdata   (m00_wdata),
        .m00_axi_wstrb   (m00_wstrb),
        .m00_axi_wlast   (m00_wlast),
        .m00_axi_wuser   (),
        .m00_axi_wvalid  (m00_wvalid),
        .m00_axi_wready  (m00_wready),
        .m00_axi_bid     (m00_bid),
        .m00_axi_bresp   (m00_bresp),
        .m00_axi_buser   ('0),
        .m00_axi_bvalid  (m00_bvalid),
        .m00_axi_bready  (m00_bready),
        .m00_axi_arid    (m00_arid),
        .m00_axi_araddr  (m00_araddr),
        .m00_axi_arlen   (m00_arlen),
        .m00_axi_arsize  (m00_arsize),
        .m00_axi_arburst (m00_arburst),
        .m00_axi_arlock  (m00_arlock),
        .m00_axi_arcache (m00_arcache),
        .m00_axi_arprot  (m00_arprot),
        .m00_axi_arqos   (m00_arqos),
        .m00_axi_arregion(),
        .m00_axi_aruser  (),
        .m00_axi_arvalid (m00_arvalid),
        .m00_axi_arready (m00_arready),
        .m00_axi_rid     (m00_rid),
        .m00_axi_rdata   (m00_rdata),
        .m00_axi_rresp   (m00_rresp),
        .m00_axi_rlast   (m00_rlast),
        .m00_axi_ruser   ('0),
        .m00_axi_rvalid  (m00_rvalid),
        .m00_axi_rready  (m00_rready),

        // ─── M01 = On-chip RAM ────────────────────────────────────────────
        .m01_axi_awid    (m01_awid),
        .m01_axi_awaddr  (m01_awaddr),
        .m01_axi_awlen   (m01_awlen),
        .m01_axi_awsize  (m01_awsize),
        .m01_axi_awburst (m01_awburst),
        .m01_axi_awlock  (m01_awlock),
        .m01_axi_awcache (m01_awcache),
        .m01_axi_awprot  (m01_awprot),
        .m01_axi_awqos   (m01_awqos),
        .m01_axi_awregion(),
        .m01_axi_awuser  (),
        .m01_axi_awvalid (m01_awvalid),
        .m01_axi_awready (m01_awready),
        .m01_axi_wdata   (m01_wdata),
        .m01_axi_wstrb   (m01_wstrb),
        .m01_axi_wlast   (m01_wlast),
        .m01_axi_wuser   (),
        .m01_axi_wvalid  (m01_wvalid),
        .m01_axi_wready  (m01_wready),
        .m01_axi_bid     (m01_bid),
        .m01_axi_bresp   (m01_bresp),
        .m01_axi_buser   ('0),
        .m01_axi_bvalid  (m01_bvalid),
        .m01_axi_bready  (m01_bready),
        .m01_axi_arid    (m01_arid),
        .m01_axi_araddr  (m01_araddr),
        .m01_axi_arlen   (m01_arlen),
        .m01_axi_arsize  (m01_arsize),
        .m01_axi_arburst (m01_arburst),
        .m01_axi_arlock  (m01_arlock),
        .m01_axi_arcache (m01_arcache),
        .m01_axi_arprot  (m01_arprot),
        .m01_axi_arqos   (m01_arqos),
        .m01_axi_arregion(),
        .m01_axi_aruser  (),
        .m01_axi_arvalid (m01_arvalid),
        .m01_axi_arready (m01_arready),
        .m01_axi_rid     (m01_rid),
        .m01_axi_rdata   (m01_rdata),
        .m01_axi_rresp   (m01_rresp),
        .m01_axi_rlast   (m01_rlast),
        .m01_axi_ruser   ('0),
        .m01_axi_rvalid  (m01_rvalid),
        .m01_axi_rready  (m01_rready),

        // ─── M02-M14 = stub slaves (tie off) ──────────────────────────────
        .m02_axi_awid    (mx_awid[2]),   .m02_axi_awaddr (mx_awaddr[2]),
        .m02_axi_awlen   (mx_awlen[2]),  .m02_axi_awsize (mx_awsize[2]),
        .m02_axi_awburst (mx_awburst[2]),.m02_axi_awlock (),
        .m02_axi_awcache (),.m02_axi_awprot (),.m02_axi_awqos (),
        .m02_axi_awregion(),.m02_axi_awuser (),.m02_axi_awvalid(mx_awvalid[2]),.m02_axi_awready(mx_awready[2]),
        .m02_axi_wdata(mx_wdata[2]),.m02_axi_wstrb(mx_wstrb[2]),.m02_axi_wlast(mx_wlast[2]),.m02_axi_wuser(),.m02_axi_wvalid(mx_wvalid[2]),.m02_axi_wready(mx_wready[2]),
        .m02_axi_bid(mx_bid[2]),.m02_axi_bresp(mx_bresp[2]),.m02_axi_buser('0),.m02_axi_bvalid(mx_bvalid[2]),.m02_axi_bready(mx_bready[2]),
        .m02_axi_arid(mx_arid[2]),.m02_axi_araddr(mx_araddr[2]),.m02_axi_arlen(mx_arlen[2]),.m02_axi_arsize(mx_arsize[2]),.m02_axi_arburst(mx_arburst[2]),.m02_axi_arlock(),.m02_axi_arcache(),.m02_axi_arprot(),.m02_axi_arqos(),.m02_axi_arregion(),.m02_axi_aruser(),.m02_axi_arvalid(mx_arvalid[2]),.m02_axi_arready(mx_arready[2]),
        .m02_axi_rid(mx_rid[2]),.m02_axi_rdata(mx_rdata[2]),.m02_axi_rresp(mx_rresp[2]),.m02_axi_rlast(mx_rlast[2]),.m02_axi_ruser('0),.m02_axi_rvalid(mx_rvalid[2]),.m02_axi_rready(mx_rready[2]),

        .m03_axi_awid(mx_awid[3]),.m03_axi_awaddr(mx_awaddr[3]),.m03_axi_awlen(mx_awlen[3]),.m03_axi_awsize(mx_awsize[3]),.m03_axi_awburst(mx_awburst[3]),.m03_axi_awlock(),.m03_axi_awcache(),.m03_axi_awprot(),.m03_axi_awqos(),.m03_axi_awregion(),.m03_axi_awuser(),.m03_axi_awvalid(mx_awvalid[3]),.m03_axi_awready(mx_awready[3]),
        .m03_axi_wdata(mx_wdata[3]),.m03_axi_wstrb(mx_wstrb[3]),.m03_axi_wlast(mx_wlast[3]),.m03_axi_wuser(),.m03_axi_wvalid(mx_wvalid[3]),.m03_axi_wready(mx_wready[3]),
        .m03_axi_bid(mx_bid[3]),.m03_axi_bresp(mx_bresp[3]),.m03_axi_buser('0),.m03_axi_bvalid(mx_bvalid[3]),.m03_axi_bready(mx_bready[3]),
        .m03_axi_arid(mx_arid[3]),.m03_axi_araddr(mx_araddr[3]),.m03_axi_arlen(mx_arlen[3]),.m03_axi_arsize(mx_arsize[3]),.m03_axi_arburst(mx_arburst[3]),.m03_axi_arlock(),.m03_axi_arcache(),.m03_axi_arprot(),.m03_axi_arqos(),.m03_axi_arregion(),.m03_axi_aruser(),.m03_axi_arvalid(mx_arvalid[3]),.m03_axi_arready(mx_arready[3]),
        .m03_axi_rid(mx_rid[3]),.m03_axi_rdata(mx_rdata[3]),.m03_axi_rresp(mx_rresp[3]),.m03_axi_rlast(mx_rlast[3]),.m03_axi_ruser('0),.m03_axi_rvalid(mx_rvalid[3]),.m03_axi_rready(mx_rready[3]),

        .m04_axi_awid    (m04_awid),   .m04_axi_awaddr  (m04_awaddr),
        .m04_axi_awlen   (m04_awlen),  .m04_axi_awsize  (m04_awsize),
        .m04_axi_awburst (m04_awburst),.m04_axi_awlock  (m04_awlock),
        .m04_axi_awcache (m04_awcache),.m04_axi_awprot  (m04_awprot),
        .m04_axi_awqos   (m04_awqos),  .m04_axi_awregion(),
        .m04_axi_awuser  (),           .m04_axi_awvalid (m04_awvalid),
        .m04_axi_awready (m04_awready),
        .m04_axi_wdata   (m04_wdata),  .m04_axi_wstrb   (m04_wstrb),
        .m04_axi_wlast   (m04_wlast),  .m04_axi_wuser   (),
        .m04_axi_wvalid  (m04_wvalid), .m04_axi_wready  (m04_wready),
        .m04_axi_bid     (m04_bid),    .m04_axi_bresp   (m04_bresp),
        .m04_axi_buser   ('0),         .m04_axi_bvalid  (m04_bvalid),
        .m04_axi_bready  (m04_bready),
        .m04_axi_arid    (m04_arid),   .m04_axi_araddr  (m04_araddr),
        .m04_axi_arlen   (m04_arlen),  .m04_axi_arsize  (m04_arsize),
        .m04_axi_arburst (m04_arburst),.m04_axi_arlock  (m04_arlock),
        .m04_axi_arcache (m04_arcache),.m04_axi_arprot  (m04_arprot),
        .m04_axi_arqos   (m04_arqos),  .m04_axi_arregion(),
        .m04_axi_aruser  (),           .m04_axi_arvalid (m04_arvalid),
        .m04_axi_arready (m04_arready),
        .m04_axi_rid     (m04_rid),    .m04_axi_rdata   (m04_rdata),
        .m04_axi_rresp   (m04_rresp),  .m04_axi_rlast   (m04_rlast),
        .m04_axi_ruser   ('0),         .m04_axi_rvalid  (m04_rvalid),
        .m04_axi_rready  (m04_rready),

        .m05_axi_awid(mx_awid[5]),.m05_axi_awaddr(mx_awaddr[5]),.m05_axi_awlen(mx_awlen[5]),.m05_axi_awsize(mx_awsize[5]),.m05_axi_awburst(mx_awburst[5]),.m05_axi_awlock(),.m05_axi_awcache(),.m05_axi_awprot(),.m05_axi_awqos(),.m05_axi_awregion(),.m05_axi_awuser(),.m05_axi_awvalid(mx_awvalid[5]),.m05_axi_awready(mx_awready[5]),
        .m05_axi_wdata(mx_wdata[5]),.m05_axi_wstrb(mx_wstrb[5]),.m05_axi_wlast(mx_wlast[5]),.m05_axi_wuser(),.m05_axi_wvalid(mx_wvalid[5]),.m05_axi_wready(mx_wready[5]),
        .m05_axi_bid(mx_bid[5]),.m05_axi_bresp(mx_bresp[5]),.m05_axi_buser('0),.m05_axi_bvalid(mx_bvalid[5]),.m05_axi_bready(mx_bready[5]),
        .m05_axi_arid(mx_arid[5]),.m05_axi_araddr(mx_araddr[5]),.m05_axi_arlen(mx_arlen[5]),.m05_axi_arsize(mx_arsize[5]),.m05_axi_arburst(mx_arburst[5]),.m05_axi_arlock(),.m05_axi_arcache(),.m05_axi_arprot(),.m05_axi_arqos(),.m05_axi_arregion(),.m05_axi_aruser(),.m05_axi_arvalid(mx_arvalid[5]),.m05_axi_arready(mx_arready[5]),
        .m05_axi_rid(mx_rid[5]),.m05_axi_rdata(mx_rdata[5]),.m05_axi_rresp(mx_rresp[5]),.m05_axi_rlast(mx_rlast[5]),.m05_axi_ruser('0),.m05_axi_rvalid(mx_rvalid[5]),.m05_axi_rready(mx_rready[5]),

        .m06_axi_awid(mx_awid[6]),.m06_axi_awaddr(mx_awaddr[6]),.m06_axi_awlen(mx_awlen[6]),.m06_axi_awsize(mx_awsize[6]),.m06_axi_awburst(mx_awburst[6]),.m06_axi_awlock(),.m06_axi_awcache(),.m06_axi_awprot(),.m06_axi_awqos(),.m06_axi_awregion(),.m06_axi_awuser(),.m06_axi_awvalid(mx_awvalid[6]),.m06_axi_awready(mx_awready[6]),
        .m06_axi_wdata(mx_wdata[6]),.m06_axi_wstrb(mx_wstrb[6]),.m06_axi_wlast(mx_wlast[6]),.m06_axi_wuser(),.m06_axi_wvalid(mx_wvalid[6]),.m06_axi_wready(mx_wready[6]),
        .m06_axi_bid(mx_bid[6]),.m06_axi_bresp(mx_bresp[6]),.m06_axi_buser('0),.m06_axi_bvalid(mx_bvalid[6]),.m06_axi_bready(mx_bready[6]),
        .m06_axi_arid(mx_arid[6]),.m06_axi_araddr(mx_araddr[6]),.m06_axi_arlen(mx_arlen[6]),.m06_axi_arsize(mx_arsize[6]),.m06_axi_arburst(mx_arburst[6]),.m06_axi_arlock(),.m06_axi_arcache(),.m06_axi_arprot(),.m06_axi_arqos(),.m06_axi_arregion(),.m06_axi_aruser(),.m06_axi_arvalid(mx_arvalid[6]),.m06_axi_arready(mx_arready[6]),
        .m06_axi_rid(mx_rid[6]),.m06_axi_rdata(mx_rdata[6]),.m06_axi_rresp(mx_rresp[6]),.m06_axi_rlast(mx_rlast[6]),.m06_axi_ruser('0),.m06_axi_rvalid(mx_rvalid[6]),.m06_axi_rready(mx_rready[6]),

        .m07_axi_awid(mx_awid[7]),.m07_axi_awaddr(mx_awaddr[7]),.m07_axi_awlen(mx_awlen[7]),.m07_axi_awsize(mx_awsize[7]),.m07_axi_awburst(mx_awburst[7]),.m07_axi_awlock(),.m07_axi_awcache(),.m07_axi_awprot(),.m07_axi_awqos(),.m07_axi_awregion(),.m07_axi_awuser(),.m07_axi_awvalid(mx_awvalid[7]),.m07_axi_awready(mx_awready[7]),
        .m07_axi_wdata(mx_wdata[7]),.m07_axi_wstrb(mx_wstrb[7]),.m07_axi_wlast(mx_wlast[7]),.m07_axi_wuser(),.m07_axi_wvalid(mx_wvalid[7]),.m07_axi_wready(mx_wready[7]),
        .m07_axi_bid(mx_bid[7]),.m07_axi_bresp(mx_bresp[7]),.m07_axi_buser('0),.m07_axi_bvalid(mx_bvalid[7]),.m07_axi_bready(mx_bready[7]),
        .m07_axi_arid(mx_arid[7]),.m07_axi_araddr(mx_araddr[7]),.m07_axi_arlen(mx_arlen[7]),.m07_axi_arsize(mx_arsize[7]),.m07_axi_arburst(mx_arburst[7]),.m07_axi_arlock(),.m07_axi_arcache(),.m07_axi_arprot(),.m07_axi_arqos(),.m07_axi_arregion(),.m07_axi_aruser(),.m07_axi_arvalid(mx_arvalid[7]),.m07_axi_arready(mx_arready[7]),
        .m07_axi_rid(mx_rid[7]),.m07_axi_rdata(mx_rdata[7]),.m07_axi_rresp(mx_rresp[7]),.m07_axi_rlast(mx_rlast[7]),.m07_axi_ruser('0),.m07_axi_rvalid(mx_rvalid[7]),.m07_axi_rready(mx_rready[7]),

        .m08_axi_awid(mx_awid[8]),.m08_axi_awaddr(mx_awaddr[8]),.m08_axi_awlen(mx_awlen[8]),.m08_axi_awsize(mx_awsize[8]),.m08_axi_awburst(mx_awburst[8]),.m08_axi_awlock(),.m08_axi_awcache(),.m08_axi_awprot(),.m08_axi_awqos(),.m08_axi_awregion(),.m08_axi_awuser(),.m08_axi_awvalid(mx_awvalid[8]),.m08_axi_awready(mx_awready[8]),
        .m08_axi_wdata(mx_wdata[8]),.m08_axi_wstrb(mx_wstrb[8]),.m08_axi_wlast(mx_wlast[8]),.m08_axi_wuser(),.m08_axi_wvalid(mx_wvalid[8]),.m08_axi_wready(mx_wready[8]),
        .m08_axi_bid(mx_bid[8]),.m08_axi_bresp(mx_bresp[8]),.m08_axi_buser('0),.m08_axi_bvalid(mx_bvalid[8]),.m08_axi_bready(mx_bready[8]),
        .m08_axi_arid(mx_arid[8]),.m08_axi_araddr(mx_araddr[8]),.m08_axi_arlen(mx_arlen[8]),.m08_axi_arsize(mx_arsize[8]),.m08_axi_arburst(mx_arburst[8]),.m08_axi_arlock(),.m08_axi_arcache(),.m08_axi_arprot(),.m08_axi_arqos(),.m08_axi_arregion(),.m08_axi_aruser(),.m08_axi_arvalid(mx_arvalid[8]),.m08_axi_arready(mx_arready[8]),
        .m08_axi_rid(mx_rid[8]),.m08_axi_rdata(mx_rdata[8]),.m08_axi_rresp(mx_rresp[8]),.m08_axi_rlast(mx_rlast[8]),.m08_axi_ruser('0),.m08_axi_rvalid(mx_rvalid[8]),.m08_axi_rready(mx_rready[8]),

        .m09_axi_awid(mx_awid[9]),.m09_axi_awaddr(mx_awaddr[9]),.m09_axi_awlen(mx_awlen[9]),.m09_axi_awsize(mx_awsize[9]),.m09_axi_awburst(mx_awburst[9]),.m09_axi_awlock(),.m09_axi_awcache(),.m09_axi_awprot(),.m09_axi_awqos(),.m09_axi_awregion(),.m09_axi_awuser(),.m09_axi_awvalid(mx_awvalid[9]),.m09_axi_awready(mx_awready[9]),
        .m09_axi_wdata(mx_wdata[9]),.m09_axi_wstrb(mx_wstrb[9]),.m09_axi_wlast(mx_wlast[9]),.m09_axi_wuser(),.m09_axi_wvalid(mx_wvalid[9]),.m09_axi_wready(mx_wready[9]),
        .m09_axi_bid(mx_bid[9]),.m09_axi_bresp(mx_bresp[9]),.m09_axi_buser('0),.m09_axi_bvalid(mx_bvalid[9]),.m09_axi_bready(mx_bready[9]),
        .m09_axi_arid(mx_arid[9]),.m09_axi_araddr(mx_araddr[9]),.m09_axi_arlen(mx_arlen[9]),.m09_axi_arsize(mx_arsize[9]),.m09_axi_arburst(mx_arburst[9]),.m09_axi_arlock(),.m09_axi_arcache(),.m09_axi_arprot(),.m09_axi_arqos(),.m09_axi_arregion(),.m09_axi_aruser(),.m09_axi_arvalid(mx_arvalid[9]),.m09_axi_arready(mx_arready[9]),
        .m09_axi_rid(mx_rid[9]),.m09_axi_rdata(mx_rdata[9]),.m09_axi_rresp(mx_rresp[9]),.m09_axi_rlast(mx_rlast[9]),.m09_axi_ruser('0),.m09_axi_rvalid(mx_rvalid[9]),.m09_axi_rready(mx_rready[9]),

        .m10_axi_awid(mx_awid[10]),.m10_axi_awaddr(mx_awaddr[10]),.m10_axi_awlen(mx_awlen[10]),.m10_axi_awsize(mx_awsize[10]),.m10_axi_awburst(mx_awburst[10]),.m10_axi_awlock(),.m10_axi_awcache(),.m10_axi_awprot(),.m10_axi_awqos(),.m10_axi_awregion(),.m10_axi_awuser(),.m10_axi_awvalid(mx_awvalid[10]),.m10_axi_awready(mx_awready[10]),
        .m10_axi_wdata(mx_wdata[10]),.m10_axi_wstrb(mx_wstrb[10]),.m10_axi_wlast(mx_wlast[10]),.m10_axi_wuser(),.m10_axi_wvalid(mx_wvalid[10]),.m10_axi_wready(mx_wready[10]),
        .m10_axi_bid(mx_bid[10]),.m10_axi_bresp(mx_bresp[10]),.m10_axi_buser('0),.m10_axi_bvalid(mx_bvalid[10]),.m10_axi_bready(mx_bready[10]),
        .m10_axi_arid(mx_arid[10]),.m10_axi_araddr(mx_araddr[10]),.m10_axi_arlen(mx_arlen[10]),.m10_axi_arsize(mx_arsize[10]),.m10_axi_arburst(mx_arburst[10]),.m10_axi_arlock(),.m10_axi_arcache(),.m10_axi_arprot(),.m10_axi_arqos(),.m10_axi_arregion(),.m10_axi_aruser(),.m10_axi_arvalid(mx_arvalid[10]),.m10_axi_arready(mx_arready[10]),
        .m10_axi_rid(mx_rid[10]),.m10_axi_rdata(mx_rdata[10]),.m10_axi_rresp(mx_rresp[10]),.m10_axi_rlast(mx_rlast[10]),.m10_axi_ruser('0),.m10_axi_rvalid(mx_rvalid[10]),.m10_axi_rready(mx_rready[10]),

        .m11_axi_awid(mx_awid[11]),.m11_axi_awaddr(mx_awaddr[11]),.m11_axi_awlen(mx_awlen[11]),.m11_axi_awsize(mx_awsize[11]),.m11_axi_awburst(mx_awburst[11]),.m11_axi_awlock(),.m11_axi_awcache(),.m11_axi_awprot(),.m11_axi_awqos(),.m11_axi_awregion(),.m11_axi_awuser(),.m11_axi_awvalid(mx_awvalid[11]),.m11_axi_awready(mx_awready[11]),
        .m11_axi_wdata(mx_wdata[11]),.m11_axi_wstrb(mx_wstrb[11]),.m11_axi_wlast(mx_wlast[11]),.m11_axi_wuser(),.m11_axi_wvalid(mx_wvalid[11]),.m11_axi_wready(mx_wready[11]),
        .m11_axi_bid(mx_bid[11]),.m11_axi_bresp(mx_bresp[11]),.m11_axi_buser('0),.m11_axi_bvalid(mx_bvalid[11]),.m11_axi_bready(mx_bready[11]),
        .m11_axi_arid(mx_arid[11]),.m11_axi_araddr(mx_araddr[11]),.m11_axi_arlen(mx_arlen[11]),.m11_axi_arsize(mx_arsize[11]),.m11_axi_arburst(mx_arburst[11]),.m11_axi_arlock(),.m11_axi_arcache(),.m11_axi_arprot(),.m11_axi_arqos(),.m11_axi_arregion(),.m11_axi_aruser(),.m11_axi_arvalid(mx_arvalid[11]),.m11_axi_arready(mx_arready[11]),
        .m11_axi_rid(mx_rid[11]),.m11_axi_rdata(mx_rdata[11]),.m11_axi_rresp(mx_rresp[11]),.m11_axi_rlast(mx_rlast[11]),.m11_axi_ruser('0),.m11_axi_rvalid(mx_rvalid[11]),.m11_axi_rready(mx_rready[11]),

        .m12_axi_awid(mx_awid[12]),.m12_axi_awaddr(mx_awaddr[12]),.m12_axi_awlen(mx_awlen[12]),.m12_axi_awsize(mx_awsize[12]),.m12_axi_awburst(mx_awburst[12]),.m12_axi_awlock(),.m12_axi_awcache(),.m12_axi_awprot(),.m12_axi_awqos(),.m12_axi_awregion(),.m12_axi_awuser(),.m12_axi_awvalid(mx_awvalid[12]),.m12_axi_awready(mx_awready[12]),
        .m12_axi_wdata(mx_wdata[12]),.m12_axi_wstrb(mx_wstrb[12]),.m12_axi_wlast(mx_wlast[12]),.m12_axi_wuser(),.m12_axi_wvalid(mx_wvalid[12]),.m12_axi_wready(mx_wready[12]),
        .m12_axi_bid(mx_bid[12]),.m12_axi_bresp(mx_bresp[12]),.m12_axi_buser('0),.m12_axi_bvalid(mx_bvalid[12]),.m12_axi_bready(mx_bready[12]),
        .m12_axi_arid(mx_arid[12]),.m12_axi_araddr(mx_araddr[12]),.m12_axi_arlen(mx_arlen[12]),.m12_axi_arsize(mx_arsize[12]),.m12_axi_arburst(mx_arburst[12]),.m12_axi_arlock(),.m12_axi_arcache(),.m12_axi_arprot(),.m12_axi_arqos(),.m12_axi_arregion(),.m12_axi_aruser(),.m12_axi_arvalid(mx_arvalid[12]),.m12_axi_arready(mx_arready[12]),
        .m12_axi_rid(mx_rid[12]),.m12_axi_rdata(mx_rdata[12]),.m12_axi_rresp(mx_rresp[12]),.m12_axi_rlast(mx_rlast[12]),.m12_axi_ruser('0),.m12_axi_rvalid(mx_rvalid[12]),.m12_axi_rready(mx_rready[12]),

        .m13_axi_awid(mx_awid[13]),.m13_axi_awaddr(mx_awaddr[13]),.m13_axi_awlen(mx_awlen[13]),.m13_axi_awsize(mx_awsize[13]),.m13_axi_awburst(mx_awburst[13]),.m13_axi_awlock(),.m13_axi_awcache(),.m13_axi_awprot(),.m13_axi_awqos(),.m13_axi_awregion(),.m13_axi_awuser(),.m13_axi_awvalid(mx_awvalid[13]),.m13_axi_awready(mx_awready[13]),
        .m13_axi_wdata(mx_wdata[13]),.m13_axi_wstrb(mx_wstrb[13]),.m13_axi_wlast(mx_wlast[13]),.m13_axi_wuser(),.m13_axi_wvalid(mx_wvalid[13]),.m13_axi_wready(mx_wready[13]),
        .m13_axi_bid(mx_bid[13]),.m13_axi_bresp(mx_bresp[13]),.m13_axi_buser('0),.m13_axi_bvalid(mx_bvalid[13]),.m13_axi_bready(mx_bready[13]),
        .m13_axi_arid(mx_arid[13]),.m13_axi_araddr(mx_araddr[13]),.m13_axi_arlen(mx_arlen[13]),.m13_axi_arsize(mx_arsize[13]),.m13_axi_arburst(mx_arburst[13]),.m13_axi_arlock(),.m13_axi_arcache(),.m13_axi_arprot(),.m13_axi_arqos(),.m13_axi_arregion(),.m13_axi_aruser(),.m13_axi_arvalid(mx_arvalid[13]),.m13_axi_arready(mx_arready[13]),
        .m13_axi_rid(mx_rid[13]),.m13_axi_rdata(mx_rdata[13]),.m13_axi_rresp(mx_rresp[13]),.m13_axi_rlast(mx_rlast[13]),.m13_axi_ruser('0),.m13_axi_rvalid(mx_rvalid[13]),.m13_axi_rready(mx_rready[13]),

        .m14_axi_awid(mx_awid[14]),.m14_axi_awaddr(mx_awaddr[14]),.m14_axi_awlen(mx_awlen[14]),.m14_axi_awsize(mx_awsize[14]),.m14_axi_awburst(mx_awburst[14]),.m14_axi_awlock(),.m14_axi_awcache(),.m14_axi_awprot(),.m14_axi_awqos(),.m14_axi_awregion(),.m14_axi_awuser(),.m14_axi_awvalid(mx_awvalid[14]),.m14_axi_awready(mx_awready[14]),
        .m14_axi_wdata(mx_wdata[14]),.m14_axi_wstrb(mx_wstrb[14]),.m14_axi_wlast(mx_wlast[14]),.m14_axi_wuser(),.m14_axi_wvalid(mx_wvalid[14]),.m14_axi_wready(mx_wready[14]),
        .m14_axi_bid(mx_bid[14]),.m14_axi_bresp(mx_bresp[14]),.m14_axi_buser('0),.m14_axi_bvalid(mx_bvalid[14]),.m14_axi_bready(mx_bready[14]),
        .m14_axi_arid(mx_arid[14]),.m14_axi_araddr(mx_araddr[14]),.m14_axi_arlen(mx_arlen[14]),.m14_axi_arsize(mx_arsize[14]),.m14_axi_arburst(mx_arburst[14]),.m14_axi_arlock(),.m14_axi_arcache(),.m14_axi_arprot(),.m14_axi_arqos(),.m14_axi_arregion(),.m14_axi_aruser(),.m14_axi_arvalid(mx_arvalid[14]),.m14_axi_arready(mx_arready[14]),
        .m14_axi_rid(mx_rid[14]),.m14_axi_rdata(mx_rdata[14]),.m14_axi_rresp(mx_rresp[14]),.m14_axi_rlast(mx_rlast[14]),.m14_axi_ruser('0),.m14_axi_rvalid(mx_rvalid[14]),.m14_axi_rready(mx_rready[14])
    );

    // =========================================================================
    //  3. AXI Width Adapter (Interconnect M00 → UART)
    // =========================================================================

    axi_width_adapter #(
        .IC_DATA_WIDTH (IC_DATA_W),
        .IC_ADDR_WIDTH (IC_ADDR_W),
        .IC_ID_WIDTH   (IC_ID_W),
        .SL_DATA_WIDTH (UART_DATA_W),
        .SL_ADDR_WIDTH (UART_ADDR_W),
        .SL_ID_WIDTH   (UART_ID_W)
    ) u_width_adapt (
        // Interconnect side (from M00)
        .ic_awid    (m00_awid),   .ic_awaddr  (m00_awaddr),
        .ic_awlen   (m00_awlen),  .ic_awsize  (m00_awsize),
        .ic_awburst (m00_awburst),.ic_awlock  (m00_awlock),
        .ic_awcache (m00_awcache),.ic_awprot  (m00_awprot),
        .ic_awqos   (m00_awqos),  .ic_awvalid (m00_awvalid),
        .ic_awready (m00_awready),

        .ic_wdata   (m00_wdata),  .ic_wstrb   (m00_wstrb),
        .ic_wlast   (m00_wlast),  .ic_wvalid  (m00_wvalid),
        .ic_wready  (m00_wready),

        .ic_bid     (m00_bid),    .ic_bresp   (m00_bresp),
        .ic_bvalid  (m00_bvalid), .ic_bready  (m00_bready),

        .ic_arid    (m00_arid),   .ic_araddr  (m00_araddr),
        .ic_arlen   (m00_arlen),  .ic_arsize  (m00_arsize),
        .ic_arburst (m00_arburst),.ic_arlock  (m00_arlock),
        .ic_arcache (m00_arcache),.ic_arprot  (m00_arprot),
        .ic_arqos   (m00_arqos),  .ic_arvalid (m00_arvalid),
        .ic_arready (m00_arready),

        .ic_rid     (m00_rid),    .ic_rdata   (m00_rdata),
        .ic_rresp   (m00_rresp),  .ic_rlast   (m00_rlast),
        .ic_rvalid  (m00_rvalid), .ic_rready  (m00_rready),

        // UART side
        .sl_awid    (uart_awid),  .sl_awaddr  (uart_awaddr),
        .sl_awvalid (uart_awvalid),.sl_awready (uart_awready),
        .sl_wdata   (uart_wdata), .sl_wstrb   (uart_wstrb),
        .sl_wvalid  (uart_wvalid),.sl_wready  (uart_wready),
        .sl_bid     (uart_bid),   .sl_bresp   (uart_bresp),
        .sl_bvalid  (uart_bvalid),.sl_bready  (uart_bready),
        .sl_arid    (uart_arid),  .sl_araddr  (uart_araddr),
        .sl_arvalid (uart_arvalid),.sl_arready(uart_arready),
        .sl_rid     (uart_rid),   .sl_rdata   (uart_rdata),
        .sl_rresp   (uart_rresp), .sl_rvalid  (uart_rvalid),
        .sl_rready  (uart_rready)
    );

    // =========================================================================
    //  4. UART AXI-Lite IP
    // =========================================================================

    axi_uart_top u_uart (
        .fixed_clk_i    (clk),
        .axi_aclk_i     (clk),
        .axi_aresetn_i  (rst_n),       // UART uses active-low reset

        // AXI read address channel
        .axi_arid_i     (uart_arid),
        .axi_araddr_i   (uart_araddr),
        .axi_arvalid_i  (uart_arvalid),
        .axi_arready_o  (uart_arready),

        // AXI read data channel
        .axi_rid_o      (uart_rid),
        .axi_rdata_o    (uart_rdata),
        .axi_rresp_o    (uart_rresp),
        .axi_rvalid_o   (uart_rvalid),
        .axi_rready_i   (uart_rready),

        // AXI write address channel
        .axi_awid_i     (uart_awid),
        .axi_awaddr_i   (uart_awaddr),
        .axi_awvalid_i  (uart_awvalid),
        .axi_awready_o  (uart_awready),

        // AXI write data channel
        .axi_wdata_i    (uart_wdata),
        .axi_wstrb_i    (uart_wstrb),
        .axi_wvalid_i   (uart_wvalid),
        .axi_wready_o   (uart_wready),

        // AXI write response channel
        .axi_bid_o      (uart_bid),
        .axi_bresp_o    (uart_bresp),
        .axi_bvalid_o   (uart_bvalid),
        .axi_bready_i   (uart_bready),

        // UART physical interface
        .uart_rx_i      (uart_rx_i),
        .uart_tx_o      (uart_tx_o),
        .read_interrupt_o (uart_irq_o)
    );

    // =========================================================================
    //  5. AXI Error-Slave stubs for M02-M14
    //     Accept every AW/AR and respond with SLVERR + zero data.
    //     Prevents deadlock if an unmapped address is accessed.
    //     M04 (PWM Generator) is excluded — it has a real slave.
    // =========================================================================

    // =========================================================================
    //  6. AXI Width Adapter (Interconnect M04 → PWM Generator)
    // =========================================================================

    axi_width_adapter #(
        .IC_DATA_WIDTH (IC_DATA_W),
        .IC_ADDR_WIDTH (IC_ADDR_W),
        .IC_ID_WIDTH   (IC_ID_W),
        .SL_DATA_WIDTH (PWM_DATA_W),
        .SL_ADDR_WIDTH (PWM_ADDR_W),
        .SL_ID_WIDTH   (PWM_ID_W)
    ) u_pwm_width_adapt (
        // Interconnect side (from M04)
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

        // PWM Generator side
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
    //  7. PWM Generator AXI-Lite IP
    // =========================================================================

    axi_pwm_top u_pwm (
        .axi_aclk_i     (clk),
        .axi_aresetn_i  (rst_n),

        // AXI write address channel
        .axi_awid_i     (pwm_awid),
        .axi_awaddr_i   (pwm_awaddr),
        .axi_awvalid_i  (pwm_awvalid),
        .axi_awready_o  (pwm_awready),

        // AXI write data channel
        .axi_wdata_i    (pwm_wdata),
        .axi_wstrb_i    (pwm_wstrb),
        .axi_wvalid_i   (pwm_wvalid),
        .axi_wready_o   (pwm_wready),

        // AXI write response channel
        .axi_bid_o      (pwm_bid),
        .axi_bresp_o    (pwm_bresp),
        .axi_bvalid_o   (pwm_bvalid),
        .axi_bready_i   (pwm_bready),

        // AXI read address channel
        .axi_arid_i     (pwm_arid),
        .axi_araddr_i   (pwm_araddr),
        .axi_arvalid_i  (pwm_arvalid),
        .axi_arready_o  (pwm_arready),

        // AXI read data channel
        .axi_rid_o      (pwm_rid),
        .axi_rdata_o    (pwm_rdata),
        .axi_rresp_o    (pwm_rresp),
        .axi_rvalid_o   (pwm_rvalid),
        .axi_rready_i   (pwm_rready),

        // PWM physical interface
        .pwm_force_disable_i (pwm_force_disable_i),
        .pwm_out_o           (pwm_out_o)
    );

    // =========================================================================
    //  8. AXI Error-Slave stubs for M02-M03, M05-M14
    //     (M04 = PWM Generator has a real slave above, excluded from loop)
    // =========================================================================

    genvar g;

    generate
        for (g = 2; g <= 14; g++) begin : GEN_STUB
            if (g != 4) begin : GEN_STUB_ACTIVE

            logic aw_seen;
            logic w_seen;
            logic [IC_ID_W-1:0] saved_id;

            always_comb begin
                mx_awready[g] = !aw_seen && !mx_bvalid[g];
                mx_wready[g]  = !w_seen  && !mx_bvalid[g];
                mx_arready[g] = !mx_rvalid[g];
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    aw_seen        <= 1'b0;
                    w_seen         <= 1'b0;
                    saved_id       <= '0;
                    mx_bvalid[g]   <= 1'b0;
                    mx_bid[g]      <= '0;
                    mx_bresp[g]    <= 2'b10; // SLVERR
                    mx_rvalid[g]   <= 1'b0;
                    mx_rid[g]      <= '0;
                    mx_rdata[g]    <= '0;
                    mx_rresp[g]    <= 2'b10; // SLVERR
                    mx_rlast[g]    <= 1'b0;
                end else begin
                    // Write address
                    if (mx_awvalid[g] && mx_awready[g]) begin
                        aw_seen  <= 1'b1;
                        saved_id <= mx_awid[g];
                    end
                    // Write data
                    if (mx_wvalid[g] && mx_wready[g])
                        w_seen <= 1'b1;
                    // Write response
                    if (aw_seen && w_seen && !mx_bvalid[g]) begin
                        mx_bid[g]    <= saved_id;
                        mx_bresp[g]  <= 2'b10;
                        mx_bvalid[g] <= 1'b1;
                        aw_seen      <= 1'b0;
                        w_seen       <= 1'b0;
                    end
                    if (mx_bvalid[g] && mx_bready[g])
                        mx_bvalid[g] <= 1'b0;
                    // Read
                    if (mx_arvalid[g] && mx_arready[g]) begin
                        mx_rid[g]    <= mx_arid[g];
                        mx_rdata[g]  <= '0;
                        mx_rresp[g]  <= 2'b10;
                        mx_rlast[g]  <= 1'b1;
                        mx_rvalid[g] <= 1'b1;
                    end
                    if (mx_rvalid[g] && mx_rready[g]) begin
                        mx_rvalid[g] <= 1'b0;
                        mx_rlast[g]  <= 1'b0;
                    end
                end
            end
            end : GEN_STUB_ACTIVE
        end
    endgenerate

endmodule : soc_top

`default_nettype wire
