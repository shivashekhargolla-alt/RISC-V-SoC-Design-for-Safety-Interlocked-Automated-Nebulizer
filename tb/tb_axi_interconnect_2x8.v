// ============================================================
// tb_axi_interconnect_2x8.v
// NebuCore SoC — AXI Interconnect Testbench (2 masters / 8 slaves)
//
// Masters
//   M0 = RISC-V core (instruction fetch + data access)
//   M1 = DMA / debug master
//
// Address map (NebuCore spec):
//   Slave 0  IMEM   0x0000_0000  14-bit (16 KB)
//   Slave 1  DMEM   0x0001_0000  14-bit (16 KB)
//   Slave 2  UART   0x0002_0000  12-bit (4 KB)
//   Slave 3  TIMER  0x0003_0000  12-bit (4 KB)
//   Slave 4  GPIO   0x0004_0000  12-bit (4 KB)
//   Slave 5  PWM    0x0005_0000  12-bit (4 KB)
//   Slave 6  7SEG   0x0006_0000  12-bit (4 KB)
//   Slave 7  WDT    0x0007_0000  12-bit (4 KB)
//
// Test plan:
//   TC01  Reset — no spurious signals on either master port
//   TC02  M0 writes to every slave  → OKAY
//   TC03  M0 reads back from every slave → correct data
//   TC04  M1 writes to every slave  → OKAY
//   TC05  M1 reads back from every slave → correct data
//   TC06  Simultaneous access — M0 and M1 target different slaves
//   TC07  Arbitration — M0 and M1 both target the SAME slave (DMEM)
//   TC08  Address decode error from each master → DECERR
//   TC09  Back-pressure — WDT slave has DELAY=4, both masters
//   TC10  Boundary addresses — first/last word of IMEM & DMEM
// ============================================================
`timescale 1ns/1ps
`default_nettype none

module tb_axi_interconnect_2x8;

// ── Parameters ───────────────────────────────────────────
localparam DATA_WIDTH = 32;
localparam ADDR_WIDTH = 32;
localparam ID_WIDTH   = 8;
localparam STRB_WIDTH = DATA_WIDTH/8;

// Slave base addresses
localparam [ADDR_WIDTH-1:0]
    BASE_IMEM  = 32'h0000_0000,
    BASE_DMEM  = 32'h0001_0000,
    BASE_UART  = 32'h0002_0000,
    BASE_TIMER = 32'h0003_0000,
    BASE_GPIO  = 32'h0004_0000,
    BASE_PWM   = 32'h0005_0000,
    BASE_7SEG  = 32'h0006_0000,
    BASE_WDT   = 32'h0007_0000,
    BAD_ADDR   = 32'hDEAD_0000;

localparam TIMEOUT = 1000;   // max cycles per transaction

// ── Clock / reset ────────────────────────────────────────
reg clk = 0;
reg rst = 1;
always #5 clk = ~clk;   // 100 MHz

// ── Master 0 bus wires (RISC-V core) ─────────────────────
reg  [ID_WIDTH-1:0]   m0_awid=0; reg  [ADDR_WIDTH-1:0] m0_awaddr=0;
reg  [7:0]            m0_awlen=0; reg  [2:0]            m0_awsize=3'b010;
reg  [1:0]            m0_awburst=2'b01; reg              m0_awlock=0;
reg  [3:0]            m0_awcache=0; reg  [2:0]          m0_awprot=0;
reg  [3:0]            m0_awqos=0;  reg  [0:0]           m0_awuser=0;
reg                   m0_awvalid=0;
wire                  m0_awready;
reg  [DATA_WIDTH-1:0] m0_wdata=0;  reg  [STRB_WIDTH-1:0] m0_wstrb=4'hF;
reg                   m0_wlast=0;  reg  [0:0]            m0_wuser=0;
reg                   m0_wvalid=0;
wire                  m0_wready;
wire [ID_WIDTH-1:0]   m0_bid;      wire [1:0]            m0_bresp;
wire [0:0]            m0_buser;    wire                  m0_bvalid;
reg                   m0_bready=0;
reg  [ID_WIDTH-1:0]   m0_arid=0;   reg  [ADDR_WIDTH-1:0] m0_araddr=0;
reg  [7:0]            m0_arlen=0;  reg  [2:0]            m0_arsize=3'b010;
reg  [1:0]            m0_arburst=2'b01; reg              m0_arlock=0;
reg  [3:0]            m0_arcache=0; reg  [2:0]           m0_arprot=0;
reg  [3:0]            m0_arqos=0;  reg  [0:0]            m0_aruser=0;
reg                   m0_arvalid=0;
wire                  m0_arready;
wire [ID_WIDTH-1:0]   m0_rid;      wire [DATA_WIDTH-1:0] m0_rdata;
wire [1:0]            m0_rresp;    wire                  m0_rlast;
wire [0:0]            m0_ruser;    wire                  m0_rvalid;
reg                   m0_rready=0;

// ── Master 1 bus wires (DMA / debug) ─────────────────────
reg  [ID_WIDTH-1:0]   m1_awid=0; reg  [ADDR_WIDTH-1:0] m1_awaddr=0;
reg  [7:0]            m1_awlen=0; reg  [2:0]            m1_awsize=3'b010;
reg  [1:0]            m1_awburst=2'b01; reg              m1_awlock=0;
reg  [3:0]            m1_awcache=0; reg  [2:0]          m1_awprot=0;
reg  [3:0]            m1_awqos=0;  reg  [0:0]           m1_awuser=0;
reg                   m1_awvalid=0;
wire                  m1_awready;
reg  [DATA_WIDTH-1:0] m1_wdata=0;  reg  [STRB_WIDTH-1:0] m1_wstrb=4'hF;
reg                   m1_wlast=0;  reg  [0:0]            m1_wuser=0;
reg                   m1_wvalid=0;
wire                  m1_wready;
wire [ID_WIDTH-1:0]   m1_bid;      wire [1:0]            m1_bresp;
wire [0:0]            m1_buser;    wire                  m1_bvalid;
reg                   m1_bready=0;
reg  [ID_WIDTH-1:0]   m1_arid=0;   reg  [ADDR_WIDTH-1:0] m1_araddr=0;
reg  [7:0]            m1_arlen=0;  reg  [2:0]            m1_arsize=3'b010;
reg  [1:0]            m1_arburst=2'b01; reg              m1_arlock=0;
reg  [3:0]            m1_arcache=0; reg  [2:0]           m1_arprot=0;
reg  [3:0]            m1_arqos=0;  reg  [0:0]            m1_aruser=0;
reg                   m1_arvalid=0;
wire                  m1_arready;
wire [ID_WIDTH-1:0]   m1_rid;      wire [DATA_WIDTH-1:0] m1_rdata;
wire [1:0]            m1_rresp;    wire                  m1_rlast;
wire [0:0]            m1_ruser;    wire                  m1_rvalid;
reg                   m1_rready=0;

// ── Slave-side wires (8 slaves) ───────────────────────────
// Macro: declare all AXI wires for one slave port
`define SLAVE_WIRES(N) \
    wire [ID_WIDTH-1:0]    s``N``_awid;    \
    wire [ADDR_WIDTH-1:0]  s``N``_awaddr;  \
    wire [7:0]             s``N``_awlen;   \
    wire [2:0]             s``N``_awsize;  \
    wire [1:0]             s``N``_awburst; \
    wire                   s``N``_awvalid; \
    wire                   s``N``_awready; \
    wire [DATA_WIDTH-1:0]  s``N``_wdata;   \
    wire [STRB_WIDTH-1:0]  s``N``_wstrb;   \
    wire                   s``N``_wlast;   \
    wire                   s``N``_wvalid;  \
    wire                   s``N``_wready;  \
    wire [ID_WIDTH-1:0]    s``N``_bid;     \
    wire [1:0]             s``N``_bresp;   \
    wire                   s``N``_bvalid;  \
    wire                   s``N``_bready;  \
    wire [ID_WIDTH-1:0]    s``N``_arid;    \
    wire [ADDR_WIDTH-1:0]  s``N``_araddr;  \
    wire [7:0]             s``N``_arlen;   \
    wire [2:0]             s``N``_arsize;  \
    wire [1:0]             s``N``_arburst; \
    wire                   s``N``_arvalid; \
    wire                   s``N``_arready; \
    wire [ID_WIDTH-1:0]    s``N``_rid;     \
    wire [DATA_WIDTH-1:0]  s``N``_rdata;   \
    wire [1:0]             s``N``_rresp;   \
    wire                   s``N``_rlast;   \
    wire                   s``N``_rvalid;  \
    wire                   s``N``_rready;

`SLAVE_WIRES(00) `SLAVE_WIRES(01) `SLAVE_WIRES(02) `SLAVE_WIRES(03)
`SLAVE_WIRES(04) `SLAVE_WIRES(05) `SLAVE_WIRES(06) `SLAVE_WIRES(07)

// ── DUT: axi_interconnect_wrap_2x8 ───────────────────────
axi_interconnect_wrap_2x8 #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    // IMEM
    .M00_BASE_ADDR(BASE_IMEM),  .M00_ADDR_WIDTH(32'd14),
    .M00_CONNECT_READ(2'b11),   .M00_CONNECT_WRITE(2'b11),
    // DMEM
    .M01_BASE_ADDR(BASE_DMEM),  .M01_ADDR_WIDTH(32'd14),
    .M01_CONNECT_READ(2'b11),   .M01_CONNECT_WRITE(2'b11),
    // UART
    .M02_BASE_ADDR(BASE_UART),  .M02_ADDR_WIDTH(32'd12),
    .M02_CONNECT_READ(2'b11),   .M02_CONNECT_WRITE(2'b11),
    // TIMER
    .M03_BASE_ADDR(BASE_TIMER), .M03_ADDR_WIDTH(32'd12),
    .M03_CONNECT_READ(2'b11),   .M03_CONNECT_WRITE(2'b11),
    // GPIO
    .M04_BASE_ADDR(BASE_GPIO),  .M04_ADDR_WIDTH(32'd12),
    .M04_CONNECT_READ(2'b11),   .M04_CONNECT_WRITE(2'b11),
    // PWM
    .M05_BASE_ADDR(BASE_PWM),   .M05_ADDR_WIDTH(32'd12),
    .M05_CONNECT_READ(2'b11),   .M05_CONNECT_WRITE(2'b11),
    // 7SEG
    .M06_BASE_ADDR(BASE_7SEG),  .M06_ADDR_WIDTH(32'd12),
    .M06_CONNECT_READ(2'b11),   .M06_CONNECT_WRITE(2'b11),
    // WDT
    .M07_BASE_ADDR(BASE_WDT),   .M07_ADDR_WIDTH(32'd12),
    .M07_CONNECT_READ(2'b11),   .M07_CONNECT_WRITE(2'b11)
) dut (
    .clk(clk), .rst(rst),

    // ── master 0 (s00 port of wrapper) ───────────────────
    .s00_axi_awid(m0_awid),     .s00_axi_awaddr(m0_awaddr),
    .s00_axi_awlen(m0_awlen),   .s00_axi_awsize(m0_awsize),
    .s00_axi_awburst(m0_awburst),.s00_axi_awlock(m0_awlock),
    .s00_axi_awcache(m0_awcache),.s00_axi_awprot(m0_awprot),
    .s00_axi_awqos(m0_awqos),   .s00_axi_awuser(m0_awuser),
    .s00_axi_awvalid(m0_awvalid),.s00_axi_awready(m0_awready),
    .s00_axi_wdata(m0_wdata),   .s00_axi_wstrb(m0_wstrb),
    .s00_axi_wlast(m0_wlast),   .s00_axi_wuser(m0_wuser),
    .s00_axi_wvalid(m0_wvalid), .s00_axi_wready(m0_wready),
    .s00_axi_bid(m0_bid),       .s00_axi_bresp(m0_bresp),
    .s00_axi_buser(m0_buser),   .s00_axi_bvalid(m0_bvalid),
    .s00_axi_bready(m0_bready),
    .s00_axi_arid(m0_arid),     .s00_axi_araddr(m0_araddr),
    .s00_axi_arlen(m0_arlen),   .s00_axi_arsize(m0_arsize),
    .s00_axi_arburst(m0_arburst),.s00_axi_arlock(m0_arlock),
    .s00_axi_arcache(m0_arcache),.s00_axi_arprot(m0_arprot),
    .s00_axi_arqos(m0_arqos),   .s00_axi_aruser(m0_aruser),
    .s00_axi_arvalid(m0_arvalid),.s00_axi_arready(m0_arready),
    .s00_axi_rid(m0_rid),       .s00_axi_rdata(m0_rdata),
    .s00_axi_rresp(m0_rresp),   .s00_axi_rlast(m0_rlast),
    .s00_axi_ruser(m0_ruser),   .s00_axi_rvalid(m0_rvalid),
    .s00_axi_rready(m0_rready),

    // ── master 1 (s01 port of wrapper) ───────────────────
    .s01_axi_awid(m1_awid),     .s01_axi_awaddr(m1_awaddr),
    .s01_axi_awlen(m1_awlen),   .s01_axi_awsize(m1_awsize),
    .s01_axi_awburst(m1_awburst),.s01_axi_awlock(m1_awlock),
    .s01_axi_awcache(m1_awcache),.s01_axi_awprot(m1_awprot),
    .s01_axi_awqos(m1_awqos),   .s01_axi_awuser(m1_awuser),
    .s01_axi_awvalid(m1_awvalid),.s01_axi_awready(m1_awready),
    .s01_axi_wdata(m1_wdata),   .s01_axi_wstrb(m1_wstrb),
    .s01_axi_wlast(m1_wlast),   .s01_axi_wuser(m1_wuser),
    .s01_axi_wvalid(m1_wvalid), .s01_axi_wready(m1_wready),
    .s01_axi_bid(m1_bid),       .s01_axi_bresp(m1_bresp),
    .s01_axi_buser(m1_buser),   .s01_axi_bvalid(m1_bvalid),
    .s01_axi_bready(m1_bready),
    .s01_axi_arid(m1_arid),     .s01_axi_araddr(m1_araddr),
    .s01_axi_arlen(m1_arlen),   .s01_axi_arsize(m1_arsize),
    .s01_axi_arburst(m1_arburst),.s01_axi_arlock(m1_arlock),
    .s01_axi_arcache(m1_arcache),.s01_axi_arprot(m1_arprot),
    .s01_axi_arqos(m1_arqos),   .s01_axi_aruser(m1_aruser),
    .s01_axi_arvalid(m1_arvalid),.s01_axi_arready(m1_arready),
    .s01_axi_rid(m1_rid),       .s01_axi_rdata(m1_rdata),
    .s01_axi_rresp(m1_rresp),   .s01_axi_rlast(m1_rlast),
    .s01_axi_ruser(m1_ruser),   .s01_axi_rvalid(m1_rvalid),
    .s01_axi_rready(m1_rready),

    // ── slave 0: IMEM ─────────────────────────────────────
    .m00_axi_awid(s00_awid),   .m00_axi_awaddr(s00_awaddr),
    .m00_axi_awlen(s00_awlen), .m00_axi_awsize(s00_awsize),
    .m00_axi_awburst(s00_awburst), .m00_axi_awlock(),
    .m00_axi_awcache(),.m00_axi_awprot(),.m00_axi_awqos(),
    .m00_axi_awregion(),.m00_axi_awuser(),
    .m00_axi_awvalid(s00_awvalid),.m00_axi_awready(s00_awready),
    .m00_axi_wdata(s00_wdata), .m00_axi_wstrb(s00_wstrb),
    .m00_axi_wlast(s00_wlast), .m00_axi_wuser(),
    .m00_axi_wvalid(s00_wvalid),.m00_axi_wready(s00_wready),
    .m00_axi_bid(s00_bid),     .m00_axi_bresp(s00_bresp),
    .m00_axi_buser(1'b0),      .m00_axi_bvalid(s00_bvalid),
    .m00_axi_bready(s00_bready),
    .m00_axi_arid(s00_arid),   .m00_axi_araddr(s00_araddr),
    .m00_axi_arlen(s00_arlen), .m00_axi_arsize(s00_arsize),
    .m00_axi_arburst(s00_arburst),.m00_axi_arlock(),
    .m00_axi_arcache(),.m00_axi_arprot(),.m00_axi_arqos(),
    .m00_axi_arregion(),.m00_axi_aruser(),
    .m00_axi_arvalid(s00_arvalid),.m00_axi_arready(s00_arready),
    .m00_axi_rid(s00_rid),     .m00_axi_rdata(s00_rdata),
    .m00_axi_rresp(s00_rresp), .m00_axi_rlast(s00_rlast),
    .m00_axi_ruser(1'b0),      .m00_axi_rvalid(s00_rvalid),
    .m00_axi_rready(s00_rready),

    // ── slave 1: DMEM ─────────────────────────────────────
    .m01_axi_awid(s01_awid),   .m01_axi_awaddr(s01_awaddr),
    .m01_axi_awlen(s01_awlen), .m01_axi_awsize(s01_awsize),
    .m01_axi_awburst(s01_awburst),.m01_axi_awlock(),
    .m01_axi_awcache(),.m01_axi_awprot(),.m01_axi_awqos(),
    .m01_axi_awregion(),.m01_axi_awuser(),
    .m01_axi_awvalid(s01_awvalid),.m01_axi_awready(s01_awready),
    .m01_axi_wdata(s01_wdata), .m01_axi_wstrb(s01_wstrb),
    .m01_axi_wlast(s01_wlast), .m01_axi_wuser(),
    .m01_axi_wvalid(s01_wvalid),.m01_axi_wready(s01_wready),
    .m01_axi_bid(s01_bid),     .m01_axi_bresp(s01_bresp),
    .m01_axi_buser(1'b0),      .m01_axi_bvalid(s01_bvalid),
    .m01_axi_bready(s01_bready),
    .m01_axi_arid(s01_arid),   .m01_axi_araddr(s01_araddr),
    .m01_axi_arlen(s01_arlen), .m01_axi_arsize(s01_arsize),
    .m01_axi_arburst(s01_arburst),.m01_axi_arlock(),
    .m01_axi_arcache(),.m01_axi_arprot(),.m01_axi_arqos(),
    .m01_axi_arregion(),.m01_axi_aruser(),
    .m01_axi_arvalid(s01_arvalid),.m01_axi_arready(s01_arready),
    .m01_axi_rid(s01_rid),     .m01_axi_rdata(s01_rdata),
    .m01_axi_rresp(s01_rresp), .m01_axi_rlast(s01_rlast),
    .m01_axi_ruser(1'b0),      .m01_axi_rvalid(s01_rvalid),
    .m01_axi_rready(s01_rready),

    // ── slave 2: UART ─────────────────────────────────────
    .m02_axi_awid(s02_awid),   .m02_axi_awaddr(s02_awaddr),
    .m02_axi_awlen(s02_awlen), .m02_axi_awsize(s02_awsize),
    .m02_axi_awburst(s02_awburst),.m02_axi_awlock(),
    .m02_axi_awcache(),.m02_axi_awprot(),.m02_axi_awqos(),
    .m02_axi_awregion(),.m02_axi_awuser(),
    .m02_axi_awvalid(s02_awvalid),.m02_axi_awready(s02_awready),
    .m02_axi_wdata(s02_wdata), .m02_axi_wstrb(s02_wstrb),
    .m02_axi_wlast(s02_wlast), .m02_axi_wuser(),
    .m02_axi_wvalid(s02_wvalid),.m02_axi_wready(s02_wready),
    .m02_axi_bid(s02_bid),     .m02_axi_bresp(s02_bresp),
    .m02_axi_buser(1'b0),      .m02_axi_bvalid(s02_bvalid),
    .m02_axi_bready(s02_bready),
    .m02_axi_arid(s02_arid),   .m02_axi_araddr(s02_araddr),
    .m02_axi_arlen(s02_arlen), .m02_axi_arsize(s02_arsize),
    .m02_axi_arburst(s02_arburst),.m02_axi_arlock(),
    .m02_axi_arcache(),.m02_axi_arprot(),.m02_axi_arqos(),
    .m02_axi_arregion(),.m02_axi_aruser(),
    .m02_axi_arvalid(s02_arvalid),.m02_axi_arready(s02_arready),
    .m02_axi_rid(s02_rid),     .m02_axi_rdata(s02_rdata),
    .m02_axi_rresp(s02_rresp), .m02_axi_rlast(s02_rlast),
    .m02_axi_ruser(1'b0),      .m02_axi_rvalid(s02_rvalid),
    .m02_axi_rready(s02_rready),

    // ── slave 3: TIMER ────────────────────────────────────
    .m03_axi_awid(s03_awid),   .m03_axi_awaddr(s03_awaddr),
    .m03_axi_awlen(s03_awlen), .m03_axi_awsize(s03_awsize),
    .m03_axi_awburst(s03_awburst),.m03_axi_awlock(),
    .m03_axi_awcache(),.m03_axi_awprot(),.m03_axi_awqos(),
    .m03_axi_awregion(),.m03_axi_awuser(),
    .m03_axi_awvalid(s03_awvalid),.m03_axi_awready(s03_awready),
    .m03_axi_wdata(s03_wdata), .m03_axi_wstrb(s03_wstrb),
    .m03_axi_wlast(s03_wlast), .m03_axi_wuser(),
    .m03_axi_wvalid(s03_wvalid),.m03_axi_wready(s03_wready),
    .m03_axi_bid(s03_bid),     .m03_axi_bresp(s03_bresp),
    .m03_axi_buser(1'b0),      .m03_axi_bvalid(s03_bvalid),
    .m03_axi_bready(s03_bready),
    .m03_axi_arid(s03_arid),   .m03_axi_araddr(s03_araddr),
    .m03_axi_arlen(s03_arlen), .m03_axi_arsize(s03_arsize),
    .m03_axi_arburst(s03_arburst),.m03_axi_arlock(),
    .m03_axi_arcache(),.m03_axi_arprot(),.m03_axi_arqos(),
    .m03_axi_arregion(),.m03_axi_aruser(),
    .m03_axi_arvalid(s03_arvalid),.m03_axi_arready(s03_arready),
    .m03_axi_rid(s03_rid),     .m03_axi_rdata(s03_rdata),
    .m03_axi_rresp(s03_rresp), .m03_axi_rlast(s03_rlast),
    .m03_axi_ruser(1'b0),      .m03_axi_rvalid(s03_rvalid),
    .m03_axi_rready(s03_rready),

    // ── slave 4: GPIO ─────────────────────────────────────
    .m04_axi_awid(s04_awid),   .m04_axi_awaddr(s04_awaddr),
    .m04_axi_awlen(s04_awlen), .m04_axi_awsize(s04_awsize),
    .m04_axi_awburst(s04_awburst),.m04_axi_awlock(),
    .m04_axi_awcache(),.m04_axi_awprot(),.m04_axi_awqos(),
    .m04_axi_awregion(),.m04_axi_awuser(),
    .m04_axi_awvalid(s04_awvalid),.m04_axi_awready(s04_awready),
    .m04_axi_wdata(s04_wdata), .m04_axi_wstrb(s04_wstrb),
    .m04_axi_wlast(s04_wlast), .m04_axi_wuser(),
    .m04_axi_wvalid(s04_wvalid),.m04_axi_wready(s04_wready),
    .m04_axi_bid(s04_bid),     .m04_axi_bresp(s04_bresp),
    .m04_axi_buser(1'b0),      .m04_axi_bvalid(s04_bvalid),
    .m04_axi_bready(s04_bready),
    .m04_axi_arid(s04_arid),   .m04_axi_araddr(s04_araddr),
    .m04_axi_arlen(s04_arlen), .m04_axi_arsize(s04_arsize),
    .m04_axi_arburst(s04_arburst),.m04_axi_arlock(),
    .m04_axi_arcache(),.m04_axi_arprot(),.m04_axi_arqos(),
    .m04_axi_arregion(),.m04_axi_aruser(),
    .m04_axi_arvalid(s04_arvalid),.m04_axi_arready(s04_arready),
    .m04_axi_rid(s04_rid),     .m04_axi_rdata(s04_rdata),
    .m04_axi_rresp(s04_rresp), .m04_axi_rlast(s04_rlast),
    .m04_axi_ruser(1'b0),      .m04_axi_rvalid(s04_rvalid),
    .m04_axi_rready(s04_rready),

    // ── slave 5: PWM ──────────────────────────────────────
    .m05_axi_awid(s05_awid),   .m05_axi_awaddr(s05_awaddr),
    .m05_axi_awlen(s05_awlen), .m05_axi_awsize(s05_awsize),
    .m05_axi_awburst(s05_awburst),.m05_axi_awlock(),
    .m05_axi_awcache(),.m05_axi_awprot(),.m05_axi_awqos(),
    .m05_axi_awregion(),.m05_axi_awuser(),
    .m05_axi_awvalid(s05_awvalid),.m05_axi_awready(s05_awready),
    .m05_axi_wdata(s05_wdata), .m05_axi_wstrb(s05_wstrb),
    .m05_axi_wlast(s05_wlast), .m05_axi_wuser(),
    .m05_axi_wvalid(s05_wvalid),.m05_axi_wready(s05_wready),
    .m05_axi_bid(s05_bid),     .m05_axi_bresp(s05_bresp),
    .m05_axi_buser(1'b0),      .m05_axi_bvalid(s05_bvalid),
    .m05_axi_bready(s05_bready),
    .m05_axi_arid(s05_arid),   .m05_axi_araddr(s05_araddr),
    .m05_axi_arlen(s05_arlen), .m05_axi_arsize(s05_arsize),
    .m05_axi_arburst(s05_arburst),.m05_axi_arlock(),
    .m05_axi_arcache(),.m05_axi_arprot(),.m05_axi_arqos(),
    .m05_axi_arregion(),.m05_axi_aruser(),
    .m05_axi_arvalid(s05_arvalid),.m05_axi_arready(s05_arready),
    .m05_axi_rid(s05_rid),     .m05_axi_rdata(s05_rdata),
    .m05_axi_rresp(s05_rresp), .m05_axi_rlast(s05_rlast),
    .m05_axi_ruser(1'b0),      .m05_axi_rvalid(s05_rvalid),
    .m05_axi_rready(s05_rready),

    // ── slave 6: 7SEG ─────────────────────────────────────
    .m06_axi_awid(s06_awid),   .m06_axi_awaddr(s06_awaddr),
    .m06_axi_awlen(s06_awlen), .m06_axi_awsize(s06_awsize),
    .m06_axi_awburst(s06_awburst),.m06_axi_awlock(),
    .m06_axi_awcache(),.m06_axi_awprot(),.m06_axi_awqos(),
    .m06_axi_awregion(),.m06_axi_awuser(),
    .m06_axi_awvalid(s06_awvalid),.m06_axi_awready(s06_awready),
    .m06_axi_wdata(s06_wdata), .m06_axi_wstrb(s06_wstrb),
    .m06_axi_wlast(s06_wlast), .m06_axi_wuser(),
    .m06_axi_wvalid(s06_wvalid),.m06_axi_wready(s06_wready),
    .m06_axi_bid(s06_bid),     .m06_axi_bresp(s06_bresp),
    .m06_axi_buser(1'b0),      .m06_axi_bvalid(s06_bvalid),
    .m06_axi_bready(s06_bready),
    .m06_axi_arid(s06_arid),   .m06_axi_araddr(s06_araddr),
    .m06_axi_arlen(s06_arlen), .m06_axi_arsize(s06_arsize),
    .m06_axi_arburst(s06_arburst),.m06_axi_arlock(),
    .m06_axi_arcache(),.m06_axi_arprot(),.m06_axi_arqos(),
    .m06_axi_arregion(),.m06_axi_aruser(),
    .m06_axi_arvalid(s06_arvalid),.m06_axi_arready(s06_arready),
    .m06_axi_rid(s06_rid),     .m06_axi_rdata(s06_rdata),
    .m06_axi_rresp(s06_rresp), .m06_axi_rlast(s06_rlast),
    .m06_axi_ruser(1'b0),      .m06_axi_rvalid(s06_rvalid),
    .m06_axi_rready(s06_rready),

    // ── slave 7: WDT ──────────────────────────────────────
    .m07_axi_awid(s07_awid),   .m07_axi_awaddr(s07_awaddr),
    .m07_axi_awlen(s07_awlen), .m07_axi_awsize(s07_awsize),
    .m07_axi_awburst(s07_awburst),.m07_axi_awlock(),
    .m07_axi_awcache(),.m07_axi_awprot(),.m07_axi_awqos(),
    .m07_axi_awregion(),.m07_axi_awuser(),
    .m07_axi_awvalid(s07_awvalid),.m07_axi_awready(s07_awready),
    .m07_axi_wdata(s07_wdata), .m07_axi_wstrb(s07_wstrb),
    .m07_axi_wlast(s07_wlast), .m07_axi_wuser(),
    .m07_axi_wvalid(s07_wvalid),.m07_axi_wready(s07_wready),
    .m07_axi_bid(s07_bid),     .m07_axi_bresp(s07_bresp),
    .m07_axi_buser(1'b0),      .m07_axi_bvalid(s07_bvalid),
    .m07_axi_bready(s07_bready),
    .m07_axi_arid(s07_arid),   .m07_axi_araddr(s07_araddr),
    .m07_axi_arlen(s07_arlen), .m07_axi_arsize(s07_arsize),
    .m07_axi_arburst(s07_arburst),.m07_axi_arlock(),
    .m07_axi_arcache(),.m07_axi_arprot(),.m07_axi_arqos(),
    .m07_axi_arregion(),.m07_axi_aruser(),
    .m07_axi_arvalid(s07_arvalid),.m07_axi_arready(s07_arready),
    .m07_axi_rid(s07_rid),     .m07_axi_rdata(s07_rdata),
    .m07_axi_rresp(s07_rresp), .m07_axi_rlast(s07_rlast),
    .m07_axi_ruser(1'b0),      .m07_axi_rvalid(s07_rvalid),
    .m07_axi_rready(s07_rready)
);

// ── 8 slave stub instances ────────────────────────────────
// WDT (slave 7) uses DELAY=4 to exercise back-pressure path.
// Reuse axi_slave_stub from the 1x8 TB.
`define SLAVE_INST(N, SID, DLY) \
axi_slave_stub #(.SLAVE_ID(SID), .DELAY(DLY)) slave_``N ( \
    .clk(clk), .rst(rst), \
    .s_axi_awid(s``N``_awid),     .s_axi_awaddr(s``N``_awaddr), \
    .s_axi_awlen(s``N``_awlen),   .s_axi_awsize(s``N``_awsize), \
    .s_axi_awburst(s``N``_awburst),.s_axi_awvalid(s``N``_awvalid), \
    .s_axi_awready(s``N``_awready), \
    .s_axi_wdata(s``N``_wdata),   .s_axi_wstrb(s``N``_wstrb), \
    .s_axi_wlast(s``N``_wlast),   .s_axi_wvalid(s``N``_wvalid), \
    .s_axi_wready(s``N``_wready), \
    .s_axi_bid(s``N``_bid),       .s_axi_bresp(s``N``_bresp), \
    .s_axi_bvalid(s``N``_bvalid), .s_axi_bready(s``N``_bready), \
    .s_axi_arid(s``N``_arid),     .s_axi_araddr(s``N``_araddr), \
    .s_axi_arlen(s``N``_arlen),   .s_axi_arsize(s``N``_arsize), \
    .s_axi_arburst(s``N``_arburst),.s_axi_arvalid(s``N``_arvalid), \
    .s_axi_arready(s``N``_arready), \
    .s_axi_rid(s``N``_rid),       .s_axi_rdata(s``N``_rdata), \
    .s_axi_rresp(s``N``_rresp),   .s_axi_rlast(s``N``_rlast), \
    .s_axi_rvalid(s``N``_rvalid), .s_axi_rready(s``N``_rready) \
);

`SLAVE_INST(00, 0, 0)  // IMEM
`SLAVE_INST(01, 1, 0)  // DMEM
`SLAVE_INST(02, 2, 0)  // UART
`SLAVE_INST(03, 3, 0)  // TIMER
`SLAVE_INST(04, 4, 0)  // GPIO
`SLAVE_INST(05, 5, 0)  // PWM
`SLAVE_INST(06, 6, 0)  // 7SEG
`SLAVE_INST(07, 7, 4)  // WDT  — DELAY=4 (back-pressure)

// ── Pass / fail counters ──────────────────────────────────
integer tests_run  = 0;
integer tests_pass = 0;
integer tests_fail = 0;

// BFM output registers
reg [DATA_WIDTH-1:0] rd0_data, rd1_data;
reg [1:0]            rd0_resp, rd1_resp;
reg [1:0]            wr0_resp, wr1_resp;
integer              to0, to1;   // timeout flags

// ── BFM task: axi_write (generic — pass master signals in) ─
// To avoid Verilog's lack of reference arguments we define
// two concrete tasks, one per master.

task m0_write;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer cnt;
    begin
        tout = 0;
        @(posedge clk); #1;
        m0_awaddr=addr; m0_awid=8'hA0; m0_awlen=0;
        m0_awsize=3'b010; m0_awburst=2'b01; m0_awvalid=1;
        m0_wdata=data; m0_wstrb=4'hF; m0_wlast=1; m0_wvalid=1;
        cnt=0;
        while (!m0_awready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m0_awvalid=0; m0_wvalid=0; m0_wlast=0; disable m0_write; end
        end
        @(posedge clk); #1; m0_awvalid=0;
        cnt=0;
        while (!m0_wready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m0_wvalid=0; m0_wlast=0; disable m0_write; end
        end
        @(posedge clk); #1; m0_wvalid=0; m0_wlast=0;
        m0_bready=1; cnt=0;
        while (!m0_bvalid) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m0_bready=0; disable m0_write; end
        end
        resp=m0_bresp; @(posedge clk); #1; m0_bready=0;
    end
endtask

task m1_write;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer cnt;
    begin
        tout = 0;
        @(posedge clk); #1;
        m1_awaddr=addr; m1_awid=8'hB0; m1_awlen=0;
        m1_awsize=3'b010; m1_awburst=2'b01; m1_awvalid=1;
        m1_wdata=data; m1_wstrb=4'hF; m1_wlast=1; m1_wvalid=1;
        cnt=0;
        while (!m1_awready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m1_awvalid=0; m1_wvalid=0; m1_wlast=0; disable m1_write; end
        end
        @(posedge clk); #1; m1_awvalid=0;
        cnt=0;
        while (!m1_wready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m1_wvalid=0; m1_wlast=0; disable m1_write; end
        end
        @(posedge clk); #1; m1_wvalid=0; m1_wlast=0;
        m1_bready=1; cnt=0;
        while (!m1_bvalid) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m1_bready=0; disable m1_write; end
        end
        resp=m1_bresp; @(posedge clk); #1; m1_bready=0;
    end
endtask

task m0_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer cnt;
    begin
        tout=0;
        @(posedge clk); #1;
        m0_araddr=addr; m0_arid=8'hA1; m0_arlen=0;
        m0_arsize=3'b010; m0_arburst=2'b01;
        m0_arvalid=1; m0_rready=1;
        cnt=0;
        while (!m0_arready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m0_arvalid=0; m0_rready=0; disable m0_read; end
        end
        @(posedge clk); #1; m0_arvalid=0;
        cnt=0;
        while (!m0_rvalid) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m0_rready=0; disable m0_read; end
        end
        data=m0_rdata; resp=m0_rresp;
        @(posedge clk); #1; m0_rready=0;
    end
endtask

task m1_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer cnt;
    begin
        tout=0;
        @(posedge clk); #1;
        m1_araddr=addr; m1_arid=8'hB1; m1_arlen=0;
        m1_arsize=3'b010; m1_arburst=2'b01;
        m1_arvalid=1; m1_rready=1;
        cnt=0;
        while (!m1_arready) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m1_arvalid=0; m1_rready=0; disable m1_read; end
        end
        @(posedge clk); #1; m1_arvalid=0;
        cnt=0;
        while (!m1_rvalid) begin
            @(posedge clk); #1; cnt=cnt+1;
            if (cnt>TIMEOUT) begin tout=1; m1_rready=0; disable m1_read; end
        end
        data=m1_rdata; resp=m1_rresp;
        @(posedge clk); #1; m1_rready=0;
    end
endtask

// ── Checker macros ────────────────────────────────────────
`define CHECK_EQ(lbl, got, exp) \
    tests_run = tests_run + 1; \
    if ((got) === (exp)) begin \
        $display("  PASS  %s  got=0x%0h", lbl, got); \
        tests_pass = tests_pass + 1; \
    end else begin \
        $display("  FAIL  %s  got=0x%0h  exp=0x%0h", lbl, got, exp); \
        tests_fail = tests_fail + 1; \
    end

`define CHECK_NOTIMEOUT(lbl, tflag) \
    tests_run = tests_run + 1; \
    if (tflag) begin \
        $display("  FAIL  %s  TIMED OUT", lbl); \
        tests_fail = tests_fail + 1; \
    end else begin \
        $display("  PASS  %s  completed in time", lbl); \
        tests_pass = tests_pass + 1; \
    end

// ── Stimulus ──────────────────────────────────────────────
integer i;
reg [ADDR_WIDTH-1:0] bases [0:7];
reg [DATA_WIDTH-1:0] wdata, exp;

// fork/join state for TC06 simultaneous access
reg tc06_m0_done, tc06_m1_done;
reg [1:0] tc06_resp0, tc06_resp1;
integer   tc06_to0,  tc06_to1;

initial begin
    bases[0]=BASE_IMEM; bases[1]=BASE_DMEM; bases[2]=BASE_UART;
    bases[3]=BASE_TIMER; bases[4]=BASE_GPIO; bases[5]=BASE_PWM;
    bases[6]=BASE_7SEG; bases[7]=BASE_WDT;

    // ────────────────────────────────────────────────────
    // TC01 — Reset
    // ────────────────────────────────────────────────────
    $display("\n=== TC01: Reset check ===");
    rst=1; repeat(10) @(posedge clk); rst=0; repeat(4) @(posedge clk);

    tests_run = tests_run + 1;
    if (!m0_awready && !m0_wready && !m0_bvalid &&
        !m0_arready && !m0_rvalid &&
        !m1_awready && !m1_wready && !m1_bvalid &&
        !m1_arready && !m1_rvalid) begin
        $display("  PASS  Both master ports quiescent after reset");
        tests_pass = tests_pass + 1;
    end else begin
        $display("  FAIL  Spurious signal after reset");
        tests_fail = tests_fail + 1;
    end

    // ────────────────────────────────────────────────────
    // TC02 — M0 writes to every slave
    // ────────────────────────────────────────────────────
    $display("\n=== TC02: M0 writes to all 8 slaves ===");
    for (i=0; i<8; i=i+1) begin
        wdata = 32'hC0_00_00_00 | (i << 4);
        m0_write(bases[i], wdata, wr0_resp, to0);
        `CHECK_NOTIMEOUT($sformatf("TC02 M0->S%0d no-timeout",i), to0)
        `CHECK_EQ($sformatf("TC02 M0->S%0d OKAY",i), wr0_resp, 2'b00)
    end

    // ────────────────────────────────────────────────────
    // TC03 — M0 reads back from every slave
    // ────────────────────────────────────────────────────
    $display("\n=== TC03: M0 reads from all 8 slaves ===");
    for (i=0; i<8; i=i+1) begin
        exp = 32'hC0_00_00_00 | (i << 4);
        m0_read(bases[i], rd0_data, rd0_resp, to0);
        `CHECK_NOTIMEOUT($sformatf("TC03 M0<-S%0d no-timeout",i), to0)
        `CHECK_EQ($sformatf("TC03 M0<-S%0d OKAY",i),  rd0_resp, 2'b00)
        `CHECK_EQ($sformatf("TC03 M0<-S%0d data",i),  rd0_data, exp)
    end

    // ────────────────────────────────────────────────────
    // TC04 — M1 writes to every slave (distinct data)
    // ────────────────────────────────────────────────────
    $display("\n=== TC04: M1 writes to all 8 slaves ===");
    for (i=0; i<8; i=i+1) begin
        wdata = 32'hD1_00_00_00 | (i << 8);
        m1_write(bases[i], wdata, wr1_resp, to1);
        `CHECK_NOTIMEOUT($sformatf("TC04 M1->S%0d no-timeout",i), to1)
        `CHECK_EQ($sformatf("TC04 M1->S%0d OKAY",i), wr1_resp, 2'b00)
    end

    // ────────────────────────────────────────────────────
    // TC05 — M1 reads back from every slave
    // ────────────────────────────────────────────────────
    $display("\n=== TC05: M1 reads from all 8 slaves ===");
    for (i=0; i<8; i=i+1) begin
        exp = 32'hD1_00_00_00 | (i << 8);
        m1_read(bases[i], rd1_data, rd1_resp, to1);
        `CHECK_NOTIMEOUT($sformatf("TC05 M1<-S%0d no-timeout",i), to1)
        `CHECK_EQ($sformatf("TC05 M1<-S%0d OKAY",i),  rd1_resp, 2'b00)
        `CHECK_EQ($sformatf("TC05 M1<-S%0d data",i),  rd1_data, exp)
    end

    // ────────────────────────────────────────────────────
    // TC06 — Simultaneous: M0→IMEM and M1→TIMER (different slaves)
    // The interconnect should service both without stalling.
    // Because Verilog tasks can't truly run in parallel we
    // launch them in a fork/join block.
    // ────────────────────────────────────────────────────
    $display("\n=== TC06: Simultaneous access to different slaves ===");
    fork
        begin
            m0_write(BASE_IMEM, 32'hFACE_0001, tc06_resp0, tc06_to0);
            tc06_m0_done = 1;
        end
        begin
            m1_write(BASE_TIMER, 32'hFACE_0002, tc06_resp1, tc06_to1);
            tc06_m1_done = 1;
        end
    join
    `CHECK_NOTIMEOUT("TC06 M0->IMEM no-timeout",  tc06_to0)
    `CHECK_EQ("TC06 M0->IMEM OKAY",  tc06_resp0, 2'b00)
    `CHECK_NOTIMEOUT("TC06 M1->TIMER no-timeout", tc06_to1)
    `CHECK_EQ("TC06 M1->TIMER OKAY", tc06_resp1, 2'b00)
    // Verify data
    m0_read(BASE_IMEM,  rd0_data, rd0_resp, to0);
    `CHECK_EQ("TC06 IMEM  readback",  rd0_data, 32'hFACE_0001)
    m1_read(BASE_TIMER, rd1_data, rd1_resp, to1);
    `CHECK_EQ("TC06 TIMER readback",  rd1_data, 32'hFACE_0002)

    // ────────────────────────────────────────────────────
    // TC07 — Arbitration: M0 and M1 both target DMEM
    // They can't go simultaneously — interconnect must
    // serialise them. We launch in fork/join; one will win
    // the arbiter and the other will wait. Both must get OKAY.
    // ────────────────────────────────────────────────────
    $display("\n=== TC07: Arbitration — both masters target DMEM ===");
    fork
        begin m0_write(BASE_DMEM,       32'hAAAA_AAAA, tc06_resp0, tc06_to0); end
        begin m1_write(BASE_DMEM+32'h4, 32'hBBBB_BBBB, tc06_resp1, tc06_to1); end
    join
    `CHECK_NOTIMEOUT("TC07 M0->DMEM no-timeout", tc06_to0)
    `CHECK_EQ("TC07 M0->DMEM OKAY", tc06_resp0, 2'b00)
    `CHECK_NOTIMEOUT("TC07 M1->DMEM no-timeout", tc06_to1)
    `CHECK_EQ("TC07 M1->DMEM OKAY", tc06_resp1, 2'b00)
    // Read each address back from M0 to confirm no corruption
    m0_read(BASE_DMEM,       rd0_data, rd0_resp, to0);
    `CHECK_EQ("TC07 DMEM+0 readback", rd0_data, 32'hAAAA_AAAA)

    // ────────────────────────────────────────────────────
    // TC08 — Decode error from each master
    // ────────────────────────────────────────────────────
    $display("\n=== TC08: Address decode error (both masters) ===");
    m0_write(BAD_ADDR, 32'hDEAD_0001, wr0_resp, to0);
    `CHECK_NOTIMEOUT("TC08 M0 bad-addr write no-timeout", to0)
    `CHECK_EQ("TC08 M0 bad-addr DECERR", wr0_resp, 2'b11)

    m0_read(BAD_ADDR, rd0_data, rd0_resp, to0);
    `CHECK_NOTIMEOUT("TC08 M0 bad-addr read no-timeout", to0)
    `CHECK_EQ("TC08 M0 bad-addr read DECERR", rd0_resp, 2'b11)

    m1_write(BAD_ADDR, 32'hDEAD_0002, wr1_resp, to1);
    `CHECK_NOTIMEOUT("TC08 M1 bad-addr write no-timeout", to1)
    `CHECK_EQ("TC08 M1 bad-addr DECERR", wr1_resp, 2'b11)

    m1_read(BAD_ADDR, rd1_data, rd1_resp, to1);
    `CHECK_NOTIMEOUT("TC08 M1 bad-addr read no-timeout", to1)
    `CHECK_EQ("TC08 M1 bad-addr read DECERR", rd1_resp, 2'b11)

    // ────────────────────────────────────────────────────
    // TC09 — Back-pressure: WDT (DELAY=4), both masters
    // ────────────────────────────────────────────────────
    $display("\n=== TC09: Back-pressure on WDT (DELAY=4) ===");
    m0_write(BASE_WDT+32'h8, 32'hCAFE_0000, wr0_resp, to0);
    `CHECK_NOTIMEOUT("TC09 M0->WDT write no-timeout", to0)
    `CHECK_EQ("TC09 M0->WDT OKAY", wr0_resp, 2'b00)
    m0_read(BASE_WDT+32'h8, rd0_data, rd0_resp, to0);
    `CHECK_NOTIMEOUT("TC09 M0 WDT read no-timeout", to0)
    `CHECK_EQ("TC09 M0 WDT data", rd0_data, 32'hCAFE_0000)

    m1_write(BASE_WDT+32'hC, 32'hCAFE_0001, wr1_resp, to1);
    `CHECK_NOTIMEOUT("TC09 M1->WDT write no-timeout", to1)
    `CHECK_EQ("TC09 M1->WDT OKAY", wr1_resp, 2'b00)
    m1_read(BASE_WDT+32'hC, rd1_data, rd1_resp, to1);
    `CHECK_NOTIMEOUT("TC09 M1 WDT read no-timeout", to1)
    `CHECK_EQ("TC09 M1 WDT data", rd1_data, 32'hCAFE_0001)

    // ────────────────────────────────────────────────────
    // TC10 — Boundary addresses: first/last word of IMEM & DMEM
    // ────────────────────────────────────────────────────
    $display("\n=== TC10: Boundary addresses ===");
    // IMEM first word (M0)
    m0_write(BASE_IMEM,        32'h1111_1111, wr0_resp, to0);
    m0_read(BASE_IMEM,         rd0_data, rd0_resp, to0);
    `CHECK_EQ("TC10 IMEM[0] M0", rd0_data, 32'h1111_1111)
    // IMEM last word — offset 0x3FFC (14-bit region, last aligned word)
    m0_write(BASE_IMEM+32'h3FFC, 32'h2222_2222, wr0_resp, to0);
    m0_read(BASE_IMEM+32'h3FFC,  rd0_data, rd0_resp, to0);
    `CHECK_EQ("TC10 IMEM[last] M0", rd0_data, 32'h2222_2222)
    // DMEM first word (M1)
    m1_write(BASE_DMEM,        32'h3333_3333, wr1_resp, to1);
    m1_read(BASE_DMEM,         rd1_data, rd1_resp, to1);
    `CHECK_EQ("TC10 DMEM[0] M1", rd1_data, 32'h3333_3333)
    // DMEM last word
    m1_write(BASE_DMEM+32'h3FFC, 32'h4444_4444, wr1_resp, to1);
    m1_read(BASE_DMEM+32'h3FFC,  rd1_data, rd1_resp, to1);
    `CHECK_EQ("TC10 DMEM[last] M1", rd1_data, 32'h4444_4444)

    // ────────────────────────────────────────────────────
    // Summary
    // ────────────────────────────────────────────────────
    $display("\n============================================");
    $display(" NebuCore AXI 2x8 Interconnect TB Results");
    $display("  Tests run  : %0d", tests_run);
    $display("  Tests PASS : %0d", tests_pass);
    $display("  Tests FAIL : %0d", tests_fail);
    $display("============================================");
    if (tests_fail == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" FAILURES DETECTED — see above");
    $display("============================================\n");
    $finish;
end

// Global watchdog
initial begin
    #(TIMEOUT * 200 * 10);   // 200 transactions × 10 ns/cycle × TIMEOUT
    $display("FATAL: global simulation timeout at %0t", $time);
    $finish;
end

// VCD dump
initial begin
    $dumpfile("tb_axi_interconnect_2x8.vcd");
    $dumpvars(0, tb_axi_interconnect_2x8);
end

// FSDB dump (Verdi)
initial begin
    $fsdbDumpfile("tb_axi_interconnect_2x8.fsdb");
    $fsdbDumpvars(0, tb_axi_interconnect_2x8);
end

endmodule
`default_nettype wire
