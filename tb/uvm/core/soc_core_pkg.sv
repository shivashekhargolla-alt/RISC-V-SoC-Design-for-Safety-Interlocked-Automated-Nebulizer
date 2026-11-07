// =============================================================================
// SoC Core UVM Package
// =============================================================================
`ifndef SOC_CORE_PKG_SV
`define SOC_CORE_PKG_SV

package soc_core_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "soc_core_item.sv"
    `include "soc_core_monitor.sv"
    `include "soc_core_agent.sv"
endpackage

`endif
