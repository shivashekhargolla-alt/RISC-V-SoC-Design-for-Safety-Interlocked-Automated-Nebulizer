// ============================================================
// axi_slave_stub.v
// Simple AXI4 slave stub for NebuCore interconnect testbench.
// Behaviour:
//   Write: accepts one write beat, echoes the address back as
//          the write-response ID, returns OKAY.
//   Read : returns the last-written data for any address, or
//          a deterministic "seed" pattern when nothing was
//          written yet: {SLAVE_ID[3:0], addr[27:0]}.
// Back-pressure is inserted for DELAY cycles on every
// write-address and read-address handshake when DELAY > 0.
// ============================================================
`timescale 1ns/1ps
`default_nettype none

module axi_slave_stub #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 8,
    parameter SLAVE_ID    = 0,          // 0-7, used in read-data seed
    parameter DELAY       = 0           // ready back-pressure cycles
)(
    input  wire                  clk,
    input  wire                  rst,

    // Write address channel
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    // Write data channel
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    // Write response channel
    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // Read address channel
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    // Read data channel
    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready
);

    // Simple internal register (single entry) ---------------
    reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'b0}};
    reg                  mem_valid = 1'b0;

    // Back-pressure counter
    reg [$clog2(DELAY+2)-1:0] bp_cnt = 0;

    // Write FSM
    localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
    reg [1:0] wstate = WS_IDLE;
    reg [ID_WIDTH-1:0] wid_lat = 0;

    always @(posedge clk) begin
        if (rst) begin
            wstate       <= WS_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            bp_cnt        <= 0;
        end else begin
            case (wstate)
                WS_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (DELAY == 0) begin
                        s_axi_awready <= 1'b1;
                    end else begin
                        // insert back-pressure
                        if (bp_cnt < DELAY) begin
                            s_axi_awready <= 1'b0;
                            bp_cnt <= bp_cnt + 1;
                        end else begin
                            s_axi_awready <= 1'b1;
                            bp_cnt <= 0;
                        end
                    end
                    if (s_axi_awvalid && s_axi_awready) begin
                        wid_lat       <= s_axi_awid;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wstate        <= WS_DATA;
                    end
                end
                WS_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        mem           <= s_axi_wdata;
                        mem_valid     <= 1'b1;
                        s_axi_wready  <= 1'b0;
                        if (s_axi_wlast) begin
                            s_axi_bid    <= wid_lat;
                            s_axi_bresp  <= 2'b00; // OKAY
                            s_axi_bvalid <= 1'b1;
                            wstate       <= WS_RESP;
                        end
                    end
                end
                WS_RESP: begin
                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        wstate       <= WS_IDLE;
                    end
                end
                default: wstate <= WS_IDLE;
            endcase
        end
    end

    // Read FSM
    localparam RS_IDLE = 1'b0, RS_DATA = 1'b1;
    reg rstate = RS_IDLE;
    reg [ID_WIDTH-1:0]   rid_lat   = 0;
    reg [ADDR_WIDTH-1:0] raddr_lat = 0;

    always @(posedge clk) begin
        if (rst) begin
            rstate        <= RS_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
        end else begin
            case (rstate)
                RS_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rid_lat       <= s_axi_arid;
                        raddr_lat     <= s_axi_araddr;
                        s_axi_arready <= 1'b0;
                        rstate        <= RS_DATA;
                    end
                end
                RS_DATA: begin
                    s_axi_rid   <= rid_lat;
                    // return last written data, or seed pattern
                    s_axi_rdata <= mem_valid ? mem :
                                   {SLAVE_ID[3:0], raddr_lat[27:0]};
                    s_axi_rresp <= 2'b00; // OKAY
                    s_axi_rlast <= 1'b1;  // single-beat
                    s_axi_rvalid <= 1'b1;
                    if (s_axi_rready && s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b0;
                        rstate       <= RS_IDLE;
                    end
                end
                default: rstate <= RS_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
