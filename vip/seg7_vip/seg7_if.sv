// =============================================================================
// Seven-Segment Display UVM Interface
// =============================================================================
`ifndef SEG7_IF_SV
`define SEG7_IF_SV

interface seg7_if(input logic clk, input logic rst_n);
    logic [6:0] seg_out_o;
    logic [3:0] digit_sel_o;

    clocking mon_cb @(posedge clk);
        default input #1step output #1step;
        input seg_out_o;
        input digit_sel_o;
    endclocking

    modport mon_mp (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
