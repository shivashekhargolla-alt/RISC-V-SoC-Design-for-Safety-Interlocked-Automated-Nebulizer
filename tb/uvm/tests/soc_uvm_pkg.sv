// =============================================================================
// SoC Tests Package
// =============================================================================
`ifndef SOC_UVM_PKG_SV
`define SOC_UVM_PKG_SV

package soc_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import uart_pkg::*;
    import gpio_pkg::*;
    import pwm_pkg::*;
    import seg7_pkg::*;
    import soc_core_pkg::*;
    import axi4_pkg::*;
    import axi_lite_pkg::*;
    import soc_env_pkg::*;

    `include "soc_sequences.sv"
    `include "soc_test_base.sv"
    `include "soc_dosage_test.sv"
    `include "soc_safety_override_test.sv"
    `include "soc_fabric_stress_test.sv"
    `include "soc_data_transfer_test.sv"
    `include "soc_riscv_to_ips_test.sv"
    `include "soc_ips_to_riscv_test.sv"
    `include "soc_uart_to_riscv_test.sv"
    `include "soc_bidir_test.sv"
    `include "soc_all_test.sv"
endpackage

`endif
