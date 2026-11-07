// =============================================================================
// 64-bit Full AXI4 VIP Package
// =============================================================================
`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV

package axi4_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi4_item.sv"
    `include "axi4_sequencer.sv"
    `include "axi4_driver.sv"
    `include "axi4_monitor.sv"
    `include "axi4_agent.sv"
endpackage

`endif
