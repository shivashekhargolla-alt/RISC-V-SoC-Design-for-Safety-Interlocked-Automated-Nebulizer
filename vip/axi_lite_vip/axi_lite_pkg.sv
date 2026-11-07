// =============================================================================
// 32-bit AXI-Lite VIP Package
// =============================================================================
`ifndef AXI_LITE_PKG_SV
`define AXI_LITE_PKG_SV

package axi_lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi_lite_item.sv"
    `include "axi_lite_sequencer.sv"
    `include "axi_lite_driver.sv"
    `include "axi_lite_monitor.sv"
    `include "axi_lite_agent.sv"
endpackage

`endif
