// =============================================================================
// SoC AXI4 Crossbar Fabric Stress Test
// Verifies: Multi-width AXI bursts, SRAM consistency, and register accesses
// across the 3x15 interconnect crossbar
// =============================================================================
`ifndef SOC_FABRIC_STRESS_TEST_SV
`define SOC_FABRIC_STRESS_TEST_SV

class soc_fabric_stress_test extends soc_test_base;
    `uvm_component_utils(soc_fabric_stress_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("STRESS_TEST", "==================================================", UVM_NONE)
        `uvm_info("STRESS_TEST", "  Starting AXI4 Fabric Crossbar Stress Test       ", UVM_NONE)
        `uvm_info("STRESS_TEST", "==================================================", UVM_NONE)

        // Set test mode = 1 (Data Transfers & Interconnect R/W)
        core_vif.test_mode = 32'd1;

        @(posedge core_vif.rst_n);

        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0010 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0010) begin
                    `uvm_info("STRESS_TEST", "AXI4 Crossbar Fabric Stress Test PASSED with marker 0x55AA0010!", UVM_LOW)
                end else begin
                    `uvm_error("STRESS_TEST", "AXI4 Fabric Stress Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TIMEOUT", "Timeout waiting for fabric stress completion marker!")
            end
        join_any

        #10us;
        phase.drop_objection(this);
    endtask
endclass

`endif
