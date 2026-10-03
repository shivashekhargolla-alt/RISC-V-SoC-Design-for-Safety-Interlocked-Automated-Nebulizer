// =============================================================================
// Module: axi_width_adapter
//
// Purpose:
//   AXI4 data-width adapter: converts a 64-bit AXI4 master (from the
//   interconnect M00 port) to a 32-bit AXI4-Lite slave (the UART IP).
//
// Interface mismatch summary:
//   ┌──────────────────────────────────────────────────────────────────┐
//   │  Signal group     │  Interconnect side │  UART side              │
//   │──────────────────────────────────────────────────────────────────│
//   │  Data             │  64-bit            │  32-bit                 │
//   │  Write strobes    │  8-bit             │  4-bit                  │
//   │  Address          │  32-bit            │  5-bit (UART reg space) │
//   │  ID               │  8-bit             │  12-bit                 │
//   │  Burst (AXI-Lite) │  present (ignored) │  not used (always 1)    │
//   └──────────────────────────────────────────────────────────────────┘
//
// Conversion rules:
//   • Write data  : lower 32 bits of 64-bit bus → UART 32-bit wdata
//   • Read data   : UART 32-bit rdata zero-extended → 64-bit bus
//   • Write strobe: lower 4 bits of 8-bit strobe → UART 4-bit wstrb
//   • Address     : lower 5 bits of 32-bit addr  → UART 5-bit addr
//   • ID          : 8-bit ID zero-extended to 12-bit for UART;
//                   UART 12-bit ID truncated to 8-bit on return path
//   • rlast       : AXI-Lite always responds with a single beat,
//                   so rlast is tied to rvalid on the slave side
//   • Burst fields: awlen/awsize/awburst etc. are ignored by the UART
//                   (it is AXI4-Lite – all transactions are single-beat)
//
// Author: Auto-generated for RISC-V VeeR EL2 SoC integration
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module axi_width_adapter #(
    // Interconnect side (master/upstream)
    parameter IC_DATA_WIDTH = 64,
    parameter IC_ADDR_WIDTH = 32,
    parameter IC_ID_WIDTH   = 8,

    // UART side (slave/downstream)
    parameter SL_DATA_WIDTH = 32,
    parameter SL_ADDR_WIDTH = 5,
    parameter SL_ID_WIDTH   = 12
) (
    // -----------------------------------------------------------------
    // Interconnect side – signals that come FROM the interconnect master
    // port (M00) and go INTO this adapter
    // -----------------------------------------------------------------
    // Write address channel
    input  logic [IC_ID_WIDTH-1:0]       ic_awid,
    input  logic [IC_ADDR_WIDTH-1:0]     ic_awaddr,
    input  logic [7:0]                   ic_awlen,
    input  logic [2:0]                   ic_awsize,
    input  logic [1:0]                   ic_awburst,
    input  logic                         ic_awlock,
    input  logic [3:0]                   ic_awcache,
    input  logic [2:0]                   ic_awprot,
    input  logic [3:0]                   ic_awqos,
    input  logic                         ic_awvalid,
    output logic                         ic_awready,

    // Write data channel
    input  logic [IC_DATA_WIDTH-1:0]     ic_wdata,
    input  logic [IC_DATA_WIDTH/8-1:0]   ic_wstrb,
    input  logic                         ic_wlast,
    input  logic                         ic_wvalid,
    output logic                         ic_wready,

    // Write response channel
    output logic [IC_ID_WIDTH-1:0]       ic_bid,
    output logic [1:0]                   ic_bresp,
    output logic                         ic_bvalid,
    input  logic                         ic_bready,

    // Read address channel
    input  logic [IC_ID_WIDTH-1:0]       ic_arid,
    input  logic [IC_ADDR_WIDTH-1:0]     ic_araddr,
    input  logic [7:0]                   ic_arlen,
    input  logic [2:0]                   ic_arsize,
    input  logic [1:0]                   ic_arburst,
    input  logic                         ic_arlock,
    input  logic [3:0]                   ic_arcache,
    input  logic [2:0]                   ic_arprot,
    input  logic [3:0]                   ic_arqos,
    input  logic                         ic_arvalid,
    output logic                         ic_arready,

    // Read data channel
    output logic [IC_ID_WIDTH-1:0]       ic_rid,
    output logic [IC_DATA_WIDTH-1:0]     ic_rdata,
    output logic [1:0]                   ic_rresp,
    output logic                         ic_rlast,
    output logic                         ic_rvalid,
    input  logic                         ic_rready,

    // -----------------------------------------------------------------
    // UART (slave) side – drive UART with adapted widths
    // -----------------------------------------------------------------
    // Write address channel
    output logic [SL_ID_WIDTH-1:0]       sl_awid,
    output logic [SL_ADDR_WIDTH-1:0]     sl_awaddr,
    output logic                         sl_awvalid,
    input  logic                         sl_awready,

    // Write data channel
    output logic [SL_DATA_WIDTH-1:0]     sl_wdata,
    output logic [SL_DATA_WIDTH/8-1:0]   sl_wstrb,
    output logic                         sl_wvalid,
    input  logic                         sl_wready,

    // Write response channel
    input  logic [SL_ID_WIDTH-1:0]       sl_bid,
    input  logic [1:0]                   sl_bresp,
    input  logic                         sl_bvalid,
    output logic                         sl_bready,

    // Read address channel
    output logic [SL_ID_WIDTH-1:0]       sl_arid,
    output logic [SL_ADDR_WIDTH-1:0]     sl_araddr,
    output logic                         sl_arvalid,
    input  logic                         sl_arready,

    // Read data channel
    input  logic [SL_ID_WIDTH-1:0]       sl_rid,
    input  logic [SL_DATA_WIDTH-1:0]     sl_rdata,
    input  logic [1:0]                   sl_rresp,
    input  logic                         sl_rvalid,
    output logic                         sl_rready
);

    // -----------------------------------------------------------------
    // Write address channel
    // -----------------------------------------------------------------
    // Zero-extend IC ID (8-bit) to UART ID (12-bit)
    assign sl_awid    = {{(SL_ID_WIDTH - IC_ID_WIDTH){1'b0}}, ic_awid};
    // Use lower SL_ADDR_WIDTH bits of the full address (UART register space)
    assign sl_awaddr  = ic_awaddr[SL_ADDR_WIDTH-1:0];
    assign sl_awvalid = ic_awvalid;
    assign ic_awready = sl_awready;

    // -----------------------------------------------------------------
    // Write data channel
    // -----------------------------------------------------------------
    // Use lower 32 bits; AXI-Lite ignores upper word
    assign sl_wdata  = ic_wdata[SL_DATA_WIDTH-1:0];
    assign sl_wstrb  = ic_wstrb[SL_DATA_WIDTH/8-1:0];
    assign sl_wvalid = ic_wvalid;
    assign ic_wready = sl_wready;

    // -----------------------------------------------------------------
    // Write response channel
    // -----------------------------------------------------------------
    // Truncate UART 12-bit BID to IC 8-bit BID
    assign ic_bid    = sl_bid[IC_ID_WIDTH-1:0];
    assign ic_bresp  = sl_bresp;
    assign ic_bvalid = sl_bvalid;
    assign sl_bready = ic_bready;

    // -----------------------------------------------------------------
    // Read address channel
    // -----------------------------------------------------------------
    assign sl_arid    = {{(SL_ID_WIDTH - IC_ID_WIDTH){1'b0}}, ic_arid};
    assign sl_araddr  = ic_araddr[SL_ADDR_WIDTH-1:0];
    assign sl_arvalid = ic_arvalid;
    assign ic_arready = sl_arready;

    // -----------------------------------------------------------------
    // Read data channel
    // -----------------------------------------------------------------
    // Zero-extend 32-bit UART read data to 64-bit IC data
    assign ic_rid    = sl_rid[IC_ID_WIDTH-1:0];
    assign ic_rdata  = {{(IC_DATA_WIDTH - SL_DATA_WIDTH){1'b0}}, sl_rdata};
    assign ic_rresp  = sl_rresp;
    // AXI-Lite always delivers a single-beat response; rlast is always 1
    // on the last (and only) beat.  Tie it to rvalid so the interconnect
    // sees a valid rlast on the cycle the data arrives.
    assign ic_rlast  = sl_rvalid;
    assign ic_rvalid = sl_rvalid;
    assign sl_rready = ic_rready;

endmodule : axi_width_adapter

`default_nettype wire
