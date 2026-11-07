// =============================================================================
// Seven-Segment UVM Package
// =============================================================================
`ifndef SEG7_PKG_SV
`define SEG7_PKG_SV

package seg7_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "seg7_item.sv"
    `include "seg7_monitor.sv"
    `include "seg7_agent.sv"
endpackage

`endif
