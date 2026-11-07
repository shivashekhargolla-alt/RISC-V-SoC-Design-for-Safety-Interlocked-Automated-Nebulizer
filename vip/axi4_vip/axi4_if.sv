// =============================================================================
// 64-bit Full AXI4 Interface
// =============================================================================
`ifndef AXI4_IF_SV
`define AXI4_IF_SV

interface axi4_if #(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input logic clk,
    input logic rst_n
);
    // Write Address Channel
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache;
    logic [2:0]            awprot;
    logic                  awvalid;
    logic                  awready;

    // Write Data Channel
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    // Write Response Channel
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // Read Address Channel
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic                  arvalid;
    logic                  arready;

    // Read Data Channel
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

endinterface

`endif
