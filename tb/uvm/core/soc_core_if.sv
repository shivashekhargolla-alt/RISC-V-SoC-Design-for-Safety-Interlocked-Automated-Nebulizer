// =============================================================================
// SoC Core & System Interface
// =============================================================================
`ifndef SOC_CORE_IF_SV
`define SOC_CORE_IF_SV

interface soc_core_if(input logic clk, input logic rst_n);
    // RISC-V Trace signals
    logic [31:0] trace_insn;
    logic [31:0] trace_addr;
    logic        trace_valid;
    logic        trace_except;
    logic [4:0]  trace_ecause;
    logic        trace_intr;
    logic [31:0] trace_tval;

    // RAM Completion & Status Markers (backdoor / mirror)
    logic [31:0] completion_marker;
    logic [31:0] test_mode;

    clocking mon_cb @(posedge clk);
        default input #1step output #1step;
        input trace_insn;
        input trace_addr;
        input trace_valid;
        input trace_except;
        input trace_ecause;
        input trace_intr;
        input trace_tval;
        input completion_marker;
        input test_mode;
    endclocking

    modport mon_mp (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
