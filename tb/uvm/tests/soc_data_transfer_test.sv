// =============================================================================
// SoC Data Transfer Test (Verifies SRAM & Peripheral Reg AXI transfers)
// =============================================================================
`ifndef SOC_DATA_TRANSFER_TEST_SV
`define SOC_DATA_TRANSFER_TEST_SV

class soc_data_transfer_test extends soc_base_test;
    `uvm_component_utils(soc_data_transfer_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting soc_data_transfer_test...", UVM_LOW)

        // Set test mode = 1 in core interface
        core_vif.test_mode = 32'd1;

        // Wait for data transfer completion marker
        @(posedge core_vif.rst_n);
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0010 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0010) begin
                    `uvm_info("TEST", "Data Transfer Test completed successfully with marker 0x55AA0010!", UVM_LOW)
                end else begin
                    `uvm_error("TEST", "Data Transfer Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TEST_TIMEOUT", "Timeout waiting for data transfer completion marker!")
            end
        join_any

        #10us;
        phase.drop_objection(this);
    endtask
endclass

`endif
