// ============================================================
// tb_axi_interconnect.v
// NebuCore SoC — AXI Interconnect Testbench (1 master / 8 slaves)
//
// Address map (from spec.pdf):
//   M00 IMEM  0x0000_0000  16 KB  (addr width 14)
//   M01 DMEM  0x0001_0000  16 KB  (addr width 14)
//   M02 UART  0x0002_0000   4 KB  (addr width 12)
//   M03 TIMER 0x0003_0000   4 KB  (addr width 12)
//   M04 GPIO  0x0004_0000   4 KB  (addr width 12)
//   M05 PWM   0x0005_0000   4 KB  (addr width 12)
//   M06 7SEG  0x0006_0000   4 KB  (addr width 12)
//   M07 WDT   0x0007_0000   4 KB  (addr width 12)
//
// Test plan:
//   TC01  Reset check
//   TC02  Write to each of the 8 slaves
//   TC03  Read from each of the 8 slaves (verify data)
//   TC04  Address decode error (unmapped address -> DECERR)
//   TC05  Back-pressure on slow slave (WDT has DELAY=4)
//   TC06  Sequential write-then-read round-trip on every slave
//   TC07  Boundary addresses (first and last word of each region)
//   TC08  Read after reset (seed-pattern check)
// ============================================================
`timescale 1ns/1ps
`default_nettype none

module tb_axi_interconnect;

// ----------------------------------------------------------
// Parameters
// ----------------------------------------------------------
localparam DATA_WIDTH = 32;
localparam ADDR_WIDTH = 32;
localparam ID_WIDTH   = 8;
localparam STRB_WIDTH = DATA_WIDTH/8;

// Address base constants (NebuCore spec §1 / task context)
localparam [ADDR_WIDTH-1:0]
    BASE_IMEM  = 32'h0000_0000,
    BASE_DMEM  = 32'h0001_0000,
    BASE_UART  = 32'h0002_0000,
    BASE_TIMER = 32'h0003_0000,
    BASE_GPIO  = 32'h0004_0000,
    BASE_PWM   = 32'h0005_0000,
    BASE_7SEG  = 32'h0006_0000,
    BASE_WDT   = 32'h0007_0000;

// An address that falls in no region → decode error
localparam [ADDR_WIDTH-1:0] BAD_ADDR = 32'hDEAD_0000;

// Timeout guard (cycles)
localparam TIMEOUT = 500;

// ----------------------------------------------------------
// Clock / reset
// ----------------------------------------------------------
reg clk = 0;
reg rst = 1;
always #5 clk = ~clk;   // 100 MHz

// ----------------------------------------------------------
// Master AXI bus wires (driven by BFM tasks)
// ----------------------------------------------------------
// Write address channel
reg  [ID_WIDTH-1:0]   m_awid    = 0;
reg  [ADDR_WIDTH-1:0] m_awaddr  = 0;
reg  [7:0]            m_awlen   = 0;
reg  [2:0]            m_awsize  = 3'b010; // 4 bytes
reg  [1:0]            m_awburst = 2'b01;  // INCR
reg                   m_awlock  = 0;
reg  [3:0]            m_awcache = 0;
reg  [2:0]            m_awprot  = 0;
reg  [3:0]            m_awqos   = 0;
reg  [0:0]            m_awuser  = 0;
reg                   m_awvalid = 0;
wire                  m_awready;

// Write data channel
reg  [DATA_WIDTH-1:0] m_wdata  = 0;
reg  [STRB_WIDTH-1:0] m_wstrb  = 4'hF;
reg                   m_wlast  = 0;
reg  [0:0]            m_wuser  = 0;
reg                   m_wvalid = 0;
wire                  m_wready;

// Write response channel
wire [ID_WIDTH-1:0]   m_bid;
wire [1:0]            m_bresp;
wire [0:0]            m_buser;
wire                  m_bvalid;
reg                   m_bready = 0;

// Read address channel
reg  [ID_WIDTH-1:0]   m_arid    = 0;
reg  [ADDR_WIDTH-1:0] m_araddr  = 0;
reg  [7:0]            m_arlen   = 0;
reg  [2:0]            m_arsize  = 3'b010;
reg  [1:0]            m_arburst = 2'b01;
reg                   m_arlock  = 0;
reg  [3:0]            m_arcache = 0;
reg  [2:0]            m_arprot  = 0;
reg  [3:0]            m_arqos   = 0;
reg  [0:0]            m_aruser  = 0;
reg                   m_arvalid = 0;
wire                  m_arready;

// Read data channel
wire [ID_WIDTH-1:0]   m_rid;
wire [DATA_WIDTH-1:0] m_rdata;
wire [1:0]            m_rresp;
wire                  m_rlast;
wire [0:0]            m_ruser;
wire                  m_rvalid;
reg                   m_rready = 0;

// ----------------------------------------------------------
// Slave-side wires (8 slaves, flat buses)
// ----------------------------------------------------------
// Each slave's port wires are named s[N]_*
// Declare all 8 as individual wires so they're easy to connect.

`define SLAVE_WIRES(N) \
    wire [ID_WIDTH-1:0]   s``N``_awid;    \
    wire [ADDR_WIDTH-1:0] s``N``_awaddr;  \
    wire [7:0]            s``N``_awlen;   \
    wire [2:0]            s``N``_awsize;  \
    wire [1:0]            s``N``_awburst; \
    wire                  s``N``_awvalid; \
    wire                  s``N``_awready; \
    wire [DATA_WIDTH-1:0] s``N``_wdata;   \
    wire [STRB_WIDTH-1:0] s``N``_wstrb;   \
    wire                  s``N``_wlast;   \
    wire                  s``N``_wvalid;  \
    wire                  s``N``_wready;  \
    wire [ID_WIDTH-1:0]   s``N``_bid;     \
    wire [1:0]            s``N``_bresp;   \
    wire [0:0]            s``N``_buser;   \
    wire                  s``N``_bvalid;  \
    wire                  s``N``_bready;  \
    wire [ID_WIDTH-1:0]   s``N``_arid;    \
    wire [ADDR_WIDTH-1:0] s``N``_araddr;  \
    wire [7:0]            s``N``_arlen;   \
    wire [2:0]            s``N``_arsize;  \
    wire [1:0]            s``N``_arburst; \
    wire                  s``N``_arvalid; \
    wire                  s``N``_arready; \
    wire [ID_WIDTH-1:0]   s``N``_rid;     \
    wire [DATA_WIDTH-1:0] s``N``_rdata;   \
    wire [1:0]            s``N``_rresp;   \
    wire                  s``N``_rlast;   \
    wire [0:0]            s``N``_ruser;   \
    wire                  s``N``_rvalid;  \
    wire                  s``N``_rready;

`SLAVE_WIRES(00)
`SLAVE_WIRES(01)
`SLAVE_WIRES(02)
`SLAVE_WIRES(03)
`SLAVE_WIRES(04)
`SLAVE_WIRES(05)
`SLAVE_WIRES(06)
`SLAVE_WIRES(07)

// buser and ruser from wrapper are 1-bit; tie the unused user wires
// The wrapper AWUSER_ENABLE/RUSER_ENABLE etc. are all 0 so user
// wires default to width 1 but are ignored.

// ----------------------------------------------------------
// DUT: axi_interconnect_wrap_1x8
// NebuCore address map parameters
// ----------------------------------------------------------
axi_interconnect_wrap_1x8 #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    // IMEM  0x0000_0000  14-bit (16 KB)
    .M00_BASE_ADDR (BASE_IMEM),
    .M00_ADDR_WIDTH(32'd14),
    .M00_CONNECT_READ (1'b1),
    .M00_CONNECT_WRITE(1'b1),
    // DMEM  0x0001_0000  14-bit (16 KB)
    .M01_BASE_ADDR (BASE_DMEM),
    .M01_ADDR_WIDTH(32'd14),
    .M01_CONNECT_READ (1'b1),
    .M01_CONNECT_WRITE(1'b1),
    // UART  0x0002_0000  12-bit (4 KB)
    .M02_BASE_ADDR (BASE_UART),
    .M02_ADDR_WIDTH(32'd12),
    .M02_CONNECT_READ (1'b1),
    .M02_CONNECT_WRITE(1'b1),
    // TIMER 0x0003_0000  12-bit (4 KB)
    .M03_BASE_ADDR (BASE_TIMER),
    .M03_ADDR_WIDTH(32'd12),
    .M03_CONNECT_READ (1'b1),
    .M03_CONNECT_WRITE(1'b1),
    // GPIO  0x0004_0000  12-bit (4 KB)
    .M04_BASE_ADDR (BASE_GPIO),
    .M04_ADDR_WIDTH(32'd12),
    .M04_CONNECT_READ (1'b1),
    .M04_CONNECT_WRITE(1'b1),
    // PWM   0x0005_0000  12-bit (4 KB)
    .M05_BASE_ADDR (BASE_PWM),
    .M05_ADDR_WIDTH(32'd12),
    .M05_CONNECT_READ (1'b1),
    .M05_CONNECT_WRITE(1'b1),
    // 7SEG  0x0006_0000  12-bit (4 KB)
    .M06_BASE_ADDR (BASE_7SEG),
    .M06_ADDR_WIDTH(32'd12),
    .M06_CONNECT_READ (1'b1),
    .M06_CONNECT_WRITE(1'b1),
    // WDT   0x0007_0000  12-bit (4 KB)
    .M07_BASE_ADDR (BASE_WDT),
    .M07_ADDR_WIDTH(32'd12),
    .M07_CONNECT_READ (1'b1),
    .M07_CONNECT_WRITE(1'b1)
) dut (
    .clk(clk), .rst(rst),

    // master (single AXI master = RISC-V core)
    .s00_axi_awid   (m_awid),   .s00_axi_awaddr(m_awaddr),
    .s00_axi_awlen  (m_awlen),  .s00_axi_awsize(m_awsize),
    .s00_axi_awburst(m_awburst),.s00_axi_awlock(m_awlock),
    .s00_axi_awcache(m_awcache),.s00_axi_awprot(m_awprot),
    .s00_axi_awqos  (m_awqos),  .s00_axi_awuser(m_awuser),
    .s00_axi_awvalid(m_awvalid),.s00_axi_awready(m_awready),
    .s00_axi_wdata  (m_wdata),  .s00_axi_wstrb (m_wstrb),
    .s00_axi_wlast  (m_wlast),  .s00_axi_wuser (m_wuser),
    .s00_axi_wvalid (m_wvalid), .s00_axi_wready(m_wready),
    .s00_axi_bid    (m_bid),    .s00_axi_bresp (m_bresp),
    .s00_axi_buser  (m_buser),  .s00_axi_bvalid(m_bvalid),
    .s00_axi_bready (m_bready),
    .s00_axi_arid   (m_arid),   .s00_axi_araddr(m_araddr),
    .s00_axi_arlen  (m_arlen),  .s00_axi_arsize(m_arsize),
    .s00_axi_arburst(m_arburst),.s00_axi_arlock(m_arlock),
    .s00_axi_arcache(m_arcache),.s00_axi_arprot(m_arprot),
    .s00_axi_arqos  (m_arqos),  .s00_axi_aruser(m_aruser),
    .s00_axi_arvalid(m_arvalid),.s00_axi_arready(m_arready),
    .s00_axi_rid    (m_rid),    .s00_axi_rdata (m_rdata),
    .s00_axi_rresp  (m_rresp),  .s00_axi_rlast (m_rlast),
    .s00_axi_ruser  (m_ruser),  .s00_axi_rvalid(m_rvalid),
    .s00_axi_rready (m_rready),

    // slave 0: IMEM
    .m00_axi_awid(s00_awid), .m00_axi_awaddr(s00_awaddr),
    .m00_axi_awlen(s00_awlen), .m00_axi_awsize(s00_awsize),
    .m00_axi_awburst(s00_awburst), .m00_axi_awlock(),
    .m00_axi_awcache(), .m00_axi_awprot(), .m00_axi_awqos(),
    .m00_axi_awregion(), .m00_axi_awuser(),
    .m00_axi_awvalid(s00_awvalid), .m00_axi_awready(s00_awready),
    .m00_axi_wdata(s00_wdata), .m00_axi_wstrb(s00_wstrb),
    .m00_axi_wlast(s00_wlast), .m00_axi_wuser(),
    .m00_axi_wvalid(s00_wvalid), .m00_axi_wready(s00_wready),
    .m00_axi_bid(s00_bid), .m00_axi_bresp(s00_bresp),
    .m00_axi_buser(1'b0), .m00_axi_bvalid(s00_bvalid),
    .m00_axi_bready(s00_bready),
    .m00_axi_arid(s00_arid), .m00_axi_araddr(s00_araddr),
    .m00_axi_arlen(s00_arlen), .m00_axi_arsize(s00_arsize),
    .m00_axi_arburst(s00_arburst), .m00_axi_arlock(),
    .m00_axi_arcache(), .m00_axi_arprot(), .m00_axi_arqos(),
    .m00_axi_arregion(), .m00_axi_aruser(),
    .m00_axi_arvalid(s00_arvalid), .m00_axi_arready(s00_arready),
    .m00_axi_rid(s00_rid), .m00_axi_rdata(s00_rdata),
    .m00_axi_rresp(s00_rresp), .m00_axi_rlast(s00_rlast),
    .m00_axi_ruser(1'b0), .m00_axi_rvalid(s00_rvalid),
    .m00_axi_rready(s00_rready),

    // slave 1: DMEM
    .m01_axi_awid(s01_awid), .m01_axi_awaddr(s01_awaddr),
    .m01_axi_awlen(s01_awlen), .m01_axi_awsize(s01_awsize),
    .m01_axi_awburst(s01_awburst), .m01_axi_awlock(),
    .m01_axi_awcache(), .m01_axi_awprot(), .m01_axi_awqos(),
    .m01_axi_awregion(), .m01_axi_awuser(),
    .m01_axi_awvalid(s01_awvalid), .m01_axi_awready(s01_awready),
    .m01_axi_wdata(s01_wdata), .m01_axi_wstrb(s01_wstrb),
    .m01_axi_wlast(s01_wlast), .m01_axi_wuser(),
    .m01_axi_wvalid(s01_wvalid), .m01_axi_wready(s01_wready),
    .m01_axi_bid(s01_bid), .m01_axi_bresp(s01_bresp),
    .m01_axi_buser(1'b0), .m01_axi_bvalid(s01_bvalid),
    .m01_axi_bready(s01_bready),
    .m01_axi_arid(s01_arid), .m01_axi_araddr(s01_araddr),
    .m01_axi_arlen(s01_arlen), .m01_axi_arsize(s01_arsize),
    .m01_axi_arburst(s01_arburst), .m01_axi_arlock(),
    .m01_axi_arcache(), .m01_axi_arprot(), .m01_axi_arqos(),
    .m01_axi_arregion(), .m01_axi_aruser(),
    .m01_axi_arvalid(s01_arvalid), .m01_axi_arready(s01_arready),
    .m01_axi_rid(s01_rid), .m01_axi_rdata(s01_rdata),
    .m01_axi_rresp(s01_rresp), .m01_axi_rlast(s01_rlast),
    .m01_axi_ruser(1'b0), .m01_axi_rvalid(s01_rvalid),
    .m01_axi_rready(s01_rready),

    // slave 2: UART
    .m02_axi_awid(s02_awid), .m02_axi_awaddr(s02_awaddr),
    .m02_axi_awlen(s02_awlen), .m02_axi_awsize(s02_awsize),
    .m02_axi_awburst(s02_awburst), .m02_axi_awlock(),
    .m02_axi_awcache(), .m02_axi_awprot(), .m02_axi_awqos(),
    .m02_axi_awregion(), .m02_axi_awuser(),
    .m02_axi_awvalid(s02_awvalid), .m02_axi_awready(s02_awready),
    .m02_axi_wdata(s02_wdata), .m02_axi_wstrb(s02_wstrb),
    .m02_axi_wlast(s02_wlast), .m02_axi_wuser(),
    .m02_axi_wvalid(s02_wvalid), .m02_axi_wready(s02_wready),
    .m02_axi_bid(s02_bid), .m02_axi_bresp(s02_bresp),
    .m02_axi_buser(1'b0), .m02_axi_bvalid(s02_bvalid),
    .m02_axi_bready(s02_bready),
    .m02_axi_arid(s02_arid), .m02_axi_araddr(s02_araddr),
    .m02_axi_arlen(s02_arlen), .m02_axi_arsize(s02_arsize),
    .m02_axi_arburst(s02_arburst), .m02_axi_arlock(),
    .m02_axi_arcache(), .m02_axi_arprot(), .m02_axi_arqos(),
    .m02_axi_arregion(), .m02_axi_aruser(),
    .m02_axi_arvalid(s02_arvalid), .m02_axi_arready(s02_arready),
    .m02_axi_rid(s02_rid), .m02_axi_rdata(s02_rdata),
    .m02_axi_rresp(s02_rresp), .m02_axi_rlast(s02_rlast),
    .m02_axi_ruser(1'b0), .m02_axi_rvalid(s02_rvalid),
    .m02_axi_rready(s02_rready),

    // slave 3: TIMER
    .m03_axi_awid(s03_awid), .m03_axi_awaddr(s03_awaddr),
    .m03_axi_awlen(s03_awlen), .m03_axi_awsize(s03_awsize),
    .m03_axi_awburst(s03_awburst), .m03_axi_awlock(),
    .m03_axi_awcache(), .m03_axi_awprot(), .m03_axi_awqos(),
    .m03_axi_awregion(), .m03_axi_awuser(),
    .m03_axi_awvalid(s03_awvalid), .m03_axi_awready(s03_awready),
    .m03_axi_wdata(s03_wdata), .m03_axi_wstrb(s03_wstrb),
    .m03_axi_wlast(s03_wlast), .m03_axi_wuser(),
    .m03_axi_wvalid(s03_wvalid), .m03_axi_wready(s03_wready),
    .m03_axi_bid(s03_bid), .m03_axi_bresp(s03_bresp),
    .m03_axi_buser(1'b0), .m03_axi_bvalid(s03_bvalid),
    .m03_axi_bready(s03_bready),
    .m03_axi_arid(s03_arid), .m03_axi_araddr(s03_araddr),
    .m03_axi_arlen(s03_arlen), .m03_axi_arsize(s03_arsize),
    .m03_axi_arburst(s03_arburst), .m03_axi_arlock(),
    .m03_axi_arcache(), .m03_axi_arprot(), .m03_axi_arqos(),
    .m03_axi_arregion(), .m03_axi_aruser(),
    .m03_axi_arvalid(s03_arvalid), .m03_axi_arready(s03_arready),
    .m03_axi_rid(s03_rid), .m03_axi_rdata(s03_rdata),
    .m03_axi_rresp(s03_rresp), .m03_axi_rlast(s03_rlast),
    .m03_axi_ruser(1'b0), .m03_axi_rvalid(s03_rvalid),
    .m03_axi_rready(s03_rready),

    // slave 4: GPIO
    .m04_axi_awid(s04_awid), .m04_axi_awaddr(s04_awaddr),
    .m04_axi_awlen(s04_awlen), .m04_axi_awsize(s04_awsize),
    .m04_axi_awburst(s04_awburst), .m04_axi_awlock(),
    .m04_axi_awcache(), .m04_axi_awprot(), .m04_axi_awqos(),
    .m04_axi_awregion(), .m04_axi_awuser(),
    .m04_axi_awvalid(s04_awvalid), .m04_axi_awready(s04_awready),
    .m04_axi_wdata(s04_wdata), .m04_axi_wstrb(s04_wstrb),
    .m04_axi_wlast(s04_wlast), .m04_axi_wuser(),
    .m04_axi_wvalid(s04_wvalid), .m04_axi_wready(s04_wready),
    .m04_axi_bid(s04_bid), .m04_axi_bresp(s04_bresp),
    .m04_axi_buser(1'b0), .m04_axi_bvalid(s04_bvalid),
    .m04_axi_bready(s04_bready),
    .m04_axi_arid(s04_arid), .m04_axi_araddr(s04_araddr),
    .m04_axi_arlen(s04_arlen), .m04_axi_arsize(s04_arsize),
    .m04_axi_arburst(s04_arburst), .m04_axi_arlock(),
    .m04_axi_arcache(), .m04_axi_arprot(), .m04_axi_arqos(),
    .m04_axi_arregion(), .m04_axi_aruser(),
    .m04_axi_arvalid(s04_arvalid), .m04_axi_arready(s04_arready),
    .m04_axi_rid(s04_rid), .m04_axi_rdata(s04_rdata),
    .m04_axi_rresp(s04_rresp), .m04_axi_rlast(s04_rlast),
    .m04_axi_ruser(1'b0), .m04_axi_rvalid(s04_rvalid),
    .m04_axi_rready(s04_rready),

    // slave 5: PWM
    .m05_axi_awid(s05_awid), .m05_axi_awaddr(s05_awaddr),
    .m05_axi_awlen(s05_awlen), .m05_axi_awsize(s05_awsize),
    .m05_axi_awburst(s05_awburst), .m05_axi_awlock(),
    .m05_axi_awcache(), .m05_axi_awprot(), .m05_axi_awqos(),
    .m05_axi_awregion(), .m05_axi_awuser(),
    .m05_axi_awvalid(s05_awvalid), .m05_axi_awready(s05_awready),
    .m05_axi_wdata(s05_wdata), .m05_axi_wstrb(s05_wstrb),
    .m05_axi_wlast(s05_wlast), .m05_axi_wuser(),
    .m05_axi_wvalid(s05_wvalid), .m05_axi_wready(s05_wready),
    .m05_axi_bid(s05_bid), .m05_axi_bresp(s05_bresp),
    .m05_axi_buser(1'b0), .m05_axi_bvalid(s05_bvalid),
    .m05_axi_bready(s05_bready),
    .m05_axi_arid(s05_arid), .m05_axi_araddr(s05_araddr),
    .m05_axi_arlen(s05_arlen), .m05_axi_arsize(s05_arsize),
    .m05_axi_arburst(s05_arburst), .m05_axi_arlock(),
    .m05_axi_arcache(), .m05_axi_arprot(), .m05_axi_arqos(),
    .m05_axi_arregion(), .m05_axi_aruser(),
    .m05_axi_arvalid(s05_arvalid), .m05_axi_arready(s05_arready),
    .m05_axi_rid(s05_rid), .m05_axi_rdata(s05_rdata),
    .m05_axi_rresp(s05_rresp), .m05_axi_rlast(s05_rlast),
    .m05_axi_ruser(1'b0), .m05_axi_rvalid(s05_rvalid),
    .m05_axi_rready(s05_rready),

    // slave 6: 7SEG
    .m06_axi_awid(s06_awid), .m06_axi_awaddr(s06_awaddr),
    .m06_axi_awlen(s06_awlen), .m06_axi_awsize(s06_awsize),
    .m06_axi_awburst(s06_awburst), .m06_axi_awlock(),
    .m06_axi_awcache(), .m06_axi_awprot(), .m06_axi_awqos(),
    .m06_axi_awregion(), .m06_axi_awuser(),
    .m06_axi_awvalid(s06_awvalid), .m06_axi_awready(s06_awready),
    .m06_axi_wdata(s06_wdata), .m06_axi_wstrb(s06_wstrb),
    .m06_axi_wlast(s06_wlast), .m06_axi_wuser(),
    .m06_axi_wvalid(s06_wvalid), .m06_axi_wready(s06_wready),
    .m06_axi_bid(s06_bid), .m06_axi_bresp(s06_bresp),
    .m06_axi_buser(1'b0), .m06_axi_bvalid(s06_bvalid),
    .m06_axi_bready(s06_bready),
    .m06_axi_arid(s06_arid), .m06_axi_araddr(s06_araddr),
    .m06_axi_arlen(s06_arlen), .m06_axi_arsize(s06_arsize),
    .m06_axi_arburst(s06_arburst), .m06_axi_arlock(),
    .m06_axi_arcache(), .m06_axi_arprot(), .m06_axi_arqos(),
    .m06_axi_arregion(), .m06_axi_aruser(),
    .m06_axi_arvalid(s06_arvalid), .m06_axi_arready(s06_arready),
    .m06_axi_rid(s06_rid), .m06_axi_rdata(s06_rdata),
    .m06_axi_rresp(s06_rresp), .m06_axi_rlast(s06_rlast),
    .m06_axi_ruser(1'b0), .m06_axi_rvalid(s06_rvalid),
    .m06_axi_rready(s06_rready),

    // slave 7: WDT
    .m07_axi_awid(s07_awid), .m07_axi_awaddr(s07_awaddr),
    .m07_axi_awlen(s07_awlen), .m07_axi_awsize(s07_awsize),
    .m07_axi_awburst(s07_awburst), .m07_axi_awlock(),
    .m07_axi_awcache(), .m07_axi_awprot(), .m07_axi_awqos(),
    .m07_axi_awregion(), .m07_axi_awuser(),
    .m07_axi_awvalid(s07_awvalid), .m07_axi_awready(s07_awready),
    .m07_axi_wdata(s07_wdata), .m07_axi_wstrb(s07_wstrb),
    .m07_axi_wlast(s07_wlast), .m07_axi_wuser(),
    .m07_axi_wvalid(s07_wvalid), .m07_axi_wready(s07_wready),
    .m07_axi_bid(s07_bid), .m07_axi_bresp(s07_bresp),
    .m07_axi_buser(1'b0), .m07_axi_bvalid(s07_bvalid),
    .m07_axi_bready(s07_bready),
    .m07_axi_arid(s07_arid), .m07_axi_araddr(s07_araddr),
    .m07_axi_arlen(s07_arlen), .m07_axi_arsize(s07_arsize),
    .m07_axi_arburst(s07_arburst), .m07_axi_arlock(),
    .m07_axi_arcache(), .m07_axi_arprot(), .m07_axi_arqos(),
    .m07_axi_arregion(), .m07_axi_aruser(),
    .m07_axi_arvalid(s07_arvalid), .m07_axi_arready(s07_arready),
    .m07_axi_rid(s07_rid), .m07_axi_rdata(s07_rdata),
    .m07_axi_rresp(s07_rresp), .m07_axi_rlast(s07_rlast),
    .m07_axi_ruser(1'b0), .m07_axi_rvalid(s07_rvalid),
    .m07_axi_rready(s07_rready)
);

// ----------------------------------------------------------
// 8 slave stub instances
// WDT (slave 7) uses DELAY=4 to exercise back-pressure path
// ----------------------------------------------------------
`define SLAVE_INST(N, ID, DLY) \
axi_slave_stub #( \
    .SLAVE_ID(ID), \
    .DELAY(DLY) \
) slave_``N ( \
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

`SLAVE_INST(00, 0, 0)   // IMEM
`SLAVE_INST(01, 1, 0)   // DMEM
`SLAVE_INST(02, 2, 0)   // UART
`SLAVE_INST(03, 3, 0)   // TIMER
`SLAVE_INST(04, 4, 0)   // GPIO
`SLAVE_INST(05, 5, 0)   // PWM
`SLAVE_INST(06, 6, 0)   // 7SEG
`SLAVE_INST(07, 7, 4)   // WDT  — DELAY=4 (back-pressure)

// ----------------------------------------------------------
// Pass / fail counters
// ----------------------------------------------------------
integer tests_run  = 0;
integer tests_pass = 0;
integer tests_fail = 0;

// Scratch registers for BFM returns
reg [DATA_WIDTH-1:0] rd_data;
reg [1:0]            rd_resp;
reg [1:0]            wr_resp;
integer              timed_out;

// ----------------------------------------------------------
// Task: axi_write
//   Performs a single-beat AXI write to <addr> with <data>.
//   Returns bresp in <resp>, sets timed_out=1 on timeout.
// ----------------------------------------------------------
task axi_write;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer                 cnt;
    begin
        tout = 0;
        // Drive AW channel
        @(posedge clk); #1;
        m_awaddr  = addr;
        m_awid    = 8'hAA;
        m_awlen   = 8'h00;        // single beat
        m_awsize  = 3'b010;       // 4 bytes
        m_awburst = 2'b01;
        m_awvalid = 1'b1;

        // Drive W channel simultaneously
        m_wdata  = data;
        m_wstrb  = 4'hF;
        m_wlast  = 1'b1;
        m_wvalid = 1'b1;

        // Wait for AWREADY
        cnt = 0;
        while (!m_awready) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
            if (cnt > TIMEOUT) begin tout = 1; disable axi_write; end
        end
        @(posedge clk); #1;
        m_awvalid = 1'b0;

        // Wait for WREADY
        cnt = 0;
        while (!m_wready) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
            if (cnt > TIMEOUT) begin tout = 1; disable axi_write; end
        end
        @(posedge clk); #1;
        m_wvalid = 1'b0;
        m_wlast  = 1'b0;

        // Accept write response
        m_bready = 1'b1;
        cnt = 0;
        while (!m_bvalid) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
            if (cnt > TIMEOUT) begin tout = 1; disable axi_write; end
        end
        resp = m_bresp;
        @(posedge clk); #1;
        m_bready = 1'b0;
    end
endtask

// ----------------------------------------------------------
// Task: axi_read
//   Performs a single-beat AXI read from <addr>.
//   Returns rdata in <data>, rresp in <resp>.
// ----------------------------------------------------------
task axi_read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    output [1:0]            resp;
    output integer          tout;
    integer                 cnt;
    begin
        tout = 0;
        @(posedge clk); #1;
        m_araddr  = addr;
        m_arid    = 8'hBB;
        m_arlen   = 8'h00;
        m_arsize  = 3'b010;
        m_arburst = 2'b01;
        m_arvalid = 1'b1;
        m_rready  = 1'b1;

        // Wait for ARREADY
        cnt = 0;
        while (!m_arready) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
            if (cnt > TIMEOUT) begin tout = 1; disable axi_read; end
        end
        @(posedge clk); #1;
        m_arvalid = 1'b0;

        // Wait for RVALID
        cnt = 0;
        while (!m_rvalid) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
            if (cnt > TIMEOUT) begin tout = 1; disable axi_read; end
        end
        data = m_rdata;
        resp = m_rresp;
        @(posedge clk); #1;
        m_rready = 1'b0;
    end
endtask

// ----------------------------------------------------------
// Macro: CHECK_EQ  — compare got vs expected, log result
// ----------------------------------------------------------
`define CHECK_EQ(label, got, exp) \
    tests_run = tests_run + 1; \
    if ((got) === (exp)) begin \
        $display("  PASS  %s  got=0x%0h", label, got); \
        tests_pass = tests_pass + 1; \
    end else begin \
        $display("  FAIL  %s  got=0x%0h  exp=0x%0h", label, got, exp); \
        tests_fail = tests_fail + 1; \
    end

`define CHECK_TIMEOUT(label) \
    tests_run = tests_run + 1; \
    if (timed_out) begin \
        $display("  FAIL  %s  TIMED OUT", label); \
        tests_fail = tests_fail + 1; \
    end else begin \
        tests_pass = tests_pass + 1; \
    end

// ----------------------------------------------------------
// Main stimulus
// ----------------------------------------------------------
integer i;
reg [DATA_WIDTH-1:0] exp_data;
reg [ADDR_WIDTH-1:0] test_addr;
reg [DATA_WIDTH-1:0] write_data;

// slave name look-up for display
reg [63:0] sname [0:7];

initial begin
    sname[0] = "IMEM";
    sname[1] = "DMEM";
    sname[2] = "UART";
    sname[3] = "TIMR";
    sname[4] = "GPIO";
    sname[5] = "PWM ";
    sname[6] = "7SEG";
    sname[7] = "WDT ";

    // --------------------------------------------------
    // TC01 – Reset check
    // --------------------------------------------------
    $display("\n=== TC01: Reset check ===");
    rst = 1;
    repeat(10) @(posedge clk);
    rst = 0;
    repeat(4)  @(posedge clk);

    // After reset the DUT state machine should be IDLE;
    // check that no spurious valid/ready signals are asserted.
    tests_run = tests_run + 1;
    if (!m_awready && !m_wready && !m_bvalid &&
        !m_arready && !m_rvalid) begin
        $display("  PASS  Post-reset signals quiescent");
        tests_pass = tests_pass + 1;
    end else begin
        $display("  FAIL  Post-reset spurious signal: awready=%b wready=%b bvalid=%b arready=%b rvalid=%b",
                  m_awready, m_wready, m_bvalid, m_arready, m_rvalid);
        tests_fail = tests_fail + 1;
    end

    // --------------------------------------------------
    // TC02 – Write to each slave (verify OKAY response)
    // --------------------------------------------------
    $display("\n=== TC02: Write to each slave ===");
    begin : tc02
        reg [ADDR_WIDTH-1:0] bases [0:7];
        bases[0] = BASE_IMEM;
        bases[1] = BASE_DMEM;
        bases[2] = BASE_UART;
        bases[3] = BASE_TIMER;
        bases[4] = BASE_GPIO;
        bases[5] = BASE_PWM;
        bases[6] = BASE_7SEG;
        bases[7] = BASE_WDT;

        for (i = 0; i < 8; i = i + 1) begin
            write_data = 32'hC0DE_0000 | i;
            axi_write(bases[i], write_data, wr_resp, timed_out);
            `CHECK_TIMEOUT($sformatf("TC02 write %s no-timeout", sname[i]))
            `CHECK_EQ($sformatf("TC02 write %s OKAY resp", sname[i]), wr_resp, 2'b00)
        end
    end

    // --------------------------------------------------
    // TC03 – Read from each slave (verify data echoed)
    // --------------------------------------------------
    $display("\n=== TC03: Read from each slave ===");
    begin : tc03
        reg [ADDR_WIDTH-1:0] bases [0:7];
        bases[0] = BASE_IMEM;
        bases[1] = BASE_DMEM;
        bases[2] = BASE_UART;
        bases[3] = BASE_TIMER;
        bases[4] = BASE_GPIO;
        bases[5] = BASE_PWM;
        bases[6] = BASE_7SEG;
        bases[7] = BASE_WDT;

        for (i = 0; i < 8; i = i + 1) begin
            axi_read(bases[i], rd_data, rd_resp, timed_out);
            `CHECK_TIMEOUT($sformatf("TC03 read %s no-timeout", sname[i]))
            `CHECK_EQ($sformatf("TC03 read %s OKAY resp", sname[i]), rd_resp, 2'b00)
            exp_data = 32'hC0DE_0000 | i;   // what TC02 wrote
            `CHECK_EQ($sformatf("TC03 read %s data", sname[i]), rd_data, exp_data)
        end
    end

    // --------------------------------------------------
    // TC04 – Address decode error (DECERR = 2'b11)
    // --------------------------------------------------
    $display("\n=== TC04: Address decode error ===");
    // Write to bad address — expect DECERR bresp
    axi_write(BAD_ADDR, 32'hDEAD_BEEF, wr_resp, timed_out);
    `CHECK_TIMEOUT("TC04 write bad addr no-timeout")
    `CHECK_EQ("TC04 write DECERR bresp", wr_resp, 2'b11)

    // Read from bad address — expect DECERR rresp
    axi_read(BAD_ADDR, rd_data, rd_resp, timed_out);
    `CHECK_TIMEOUT("TC04 read bad addr no-timeout")
    `CHECK_EQ("TC04 read DECERR rresp", rd_resp, 2'b11)

    // --------------------------------------------------
    // TC05 – Back-pressure: write/read to WDT (DELAY=4)
    // --------------------------------------------------
    $display("\n=== TC05: Back-pressure on WDT (DELAY=4) ===");
    axi_write(BASE_WDT + 4, 32'hBABE_CAFE, wr_resp, timed_out);
    `CHECK_TIMEOUT("TC05 WDT write no-timeout")
    `CHECK_EQ("TC05 WDT write OKAY resp", wr_resp, 2'b00)

    axi_read(BASE_WDT + 4, rd_data, rd_resp, timed_out);
    `CHECK_TIMEOUT("TC05 WDT read no-timeout")
    `CHECK_EQ("TC05 WDT read OKAY resp", rd_resp, 2'b00)
    `CHECK_EQ("TC05 WDT read data",      rd_data, 32'hBABE_CAFE)

    // --------------------------------------------------
    // TC06 – Write-then-read round-trip on every slave
    // --------------------------------------------------
    $display("\n=== TC06: Write-then-read round-trip ===");
    begin : tc06
        reg [ADDR_WIDTH-1:0] bases [0:7];
        bases[0] = BASE_IMEM  + 32'h0008;
        bases[1] = BASE_DMEM  + 32'h0008;
        bases[2] = BASE_UART  + 32'h0004;
        bases[3] = BASE_TIMER + 32'h0004;
        bases[4] = BASE_GPIO  + 32'h0004;
        bases[5] = BASE_PWM   + 32'h0004;
        bases[6] = BASE_7SEG  + 32'h0004;
        bases[7] = BASE_WDT   + 32'h0008;

        for (i = 0; i < 8; i = i + 1) begin
            write_data = 32'hA5A5_0000 | (i << 4);
            axi_write(bases[i], write_data, wr_resp, timed_out);
            `CHECK_TIMEOUT($sformatf("TC06 write %s no-timeout", sname[i]))
            axi_read(bases[i], rd_data, rd_resp, timed_out);
            `CHECK_TIMEOUT($sformatf("TC06 read %s no-timeout", sname[i]))
            `CHECK_EQ($sformatf("TC06 roundtrip %s", sname[i]), rd_data, write_data)
        end
    end

    // --------------------------------------------------
    // TC07 – Boundary: first and last word of IMEM region
    //        IMEM: 0x0000_0000 – 0x0000_3FFF  (14-bit)
    //        DMEM: 0x0001_0000 – 0x0001_3FFF
    // --------------------------------------------------
    $display("\n=== TC07: Boundary address access ===");
    // IMEM first word
    axi_write(BASE_IMEM, 32'h1111_1111, wr_resp, timed_out);
    `CHECK_TIMEOUT("TC07 IMEM base write no-timeout")
    `CHECK_EQ("TC07 IMEM base write resp", wr_resp, 2'b00)
    axi_read(BASE_IMEM, rd_data, rd_resp, timed_out);
    `CHECK_EQ("TC07 IMEM base read data", rd_data, 32'h1111_1111)

    // IMEM last valid word (offset 0x3FFC = 16380)
    axi_write(BASE_IMEM + 32'h3FFC, 32'h2222_2222, wr_resp, timed_out);
    `CHECK_TIMEOUT("TC07 IMEM end write no-timeout")
    `CHECK_EQ("TC07 IMEM end write resp", wr_resp, 2'b00)
    axi_read(BASE_IMEM + 32'h3FFC, rd_data, rd_resp, timed_out);
    `CHECK_EQ("TC07 IMEM end read data", rd_data, 32'h2222_2222)

    // DMEM first word
    axi_write(BASE_DMEM, 32'h3333_3333, wr_resp, timed_out);
    `CHECK_TIMEOUT("TC07 DMEM base write no-timeout")
    axi_read(BASE_DMEM, rd_data, rd_resp, timed_out);
    `CHECK_EQ("TC07 DMEM base read data", rd_data, 32'h3333_3333)

    // --------------------------------------------------
    // TC08 – Read-after-reset seed-pattern check
    //        Fresh stubs return {SLAVE_ID[3:0], addr[27:0]}
    //        We need a stub that has NOT been written yet.
    //        Apply a mid-simulation reset then read UART@base.
    // --------------------------------------------------
    $display("\n=== TC08: Seed pattern after reset ===");
    // Apply reset to clear stub state
    rst = 1;
    repeat(8) @(posedge clk);
    rst = 0;
    repeat(4) @(posedge clk);

    // Read from UART base — stub has not been written since reset
    axi_read(BASE_UART, rd_data, rd_resp, timed_out);
    `CHECK_TIMEOUT("TC08 read UART no-timeout")
    // Seed = {SLAVE_ID=2, addr[27:0]} = {4'h2, 28'h0002_0000}
    exp_data = {4'd2, BASE_UART[27:0]};
    `CHECK_EQ("TC08 UART seed pattern", rd_data, exp_data)

    // Read from WDT base — SLAVE_ID=7
    axi_read(BASE_WDT, rd_data, rd_resp, timed_out);
    `CHECK_TIMEOUT("TC08 read WDT no-timeout")
    exp_data = {4'd7, BASE_WDT[27:0]};
    `CHECK_EQ("TC08 WDT seed pattern", rd_data, exp_data)

    // --------------------------------------------------
    // Results summary
    // --------------------------------------------------
    $display("\n============================================");
    $display(" NebuCore AXI Interconnect Testbench Results");
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

// ----------------------------------------------------------
// Watchdog: kill simulation if it runs too long
// ----------------------------------------------------------
initial begin
    #(TIMEOUT * 1000);
    $display("FATAL: global simulation timeout");
    $finish;
end

// Optional VCD dump
initial begin
    $dumpfile("tb_axi_interconnect.vcd");
    $dumpvars(0, tb_axi_interconnect);
end

endmodule
`default_nettype wire
