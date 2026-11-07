// =============================================================================
// Top Environment Package for NebuCore SoC
// =============================================================================
`ifndef SOC_ENV_PKG_SV
`define SOC_ENV_PKG_SV

package soc_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import uart_pkg::*;
    import gpio_pkg::*;
    import pwm_pkg::*;
    import seg7_pkg::*;
    import soc_core_pkg::*;
    import axi4_pkg::*;
    import axi_lite_pkg::*;

    `include "soc_coverage.sv"
    `include "soc_scoreboard.sv"
    `include "soc_virtual_sequencer.sv"
    `include "soc_env.sv"
endpackage

`endif
