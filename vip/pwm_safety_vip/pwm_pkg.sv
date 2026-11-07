// =============================================================================
// PWM UVM Package
// =============================================================================
`ifndef PWM_PKG_SV
`define PWM_PKG_SV

package pwm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "pwm_item.sv"
    `include "pwm_sequencer.sv"
    `include "pwm_driver.sv"
    `include "pwm_monitor.sv"
    `include "pwm_agent.sv"
endpackage

`endif
