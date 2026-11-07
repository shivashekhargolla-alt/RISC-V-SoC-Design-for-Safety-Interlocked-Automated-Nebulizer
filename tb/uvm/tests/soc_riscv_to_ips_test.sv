// =============================================================================
// SoC RISC-V to IPs Test (Core drives UART TX, GPIO OUT, PWM, Seg7)
// =============================================================================
`ifndef SOC_RISCV_TO_IPS_TEST_SV
`define SOC_RISCV_TO_IPS_TEST_SV

class soc_riscv_to_ips_test extends soc_base_test;
    `uvm_component_utils(soc_riscv_to_ips_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting soc_riscv_to_ips_test...", UVM_LOW)

        // Set test mode = 2
        core_vif.test_mode = 32'd2;

        @(posedge core_vif.rst_n);
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0020 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0020) begin
                    `uvm_info("TEST", "RISC-V -> IPs Test completed successfully with marker 0x55AA0020!", UVM_LOW)
                end else begin
                    `uvm_error("TEST", "RISC-V -> IPs Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TEST_TIMEOUT", "Timeout waiting for RISC-V to IPs completion marker!")
            end
        join_any

        #10us;
        phase.drop_objection(this);
    endtask
endclass

`endif
