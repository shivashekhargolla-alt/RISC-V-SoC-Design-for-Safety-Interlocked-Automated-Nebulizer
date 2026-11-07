// =============================================================================
// SoC Nominal Dosage Sequence Test
// Flow: External UART Dosage Request -> Core Compute -> PWM Piezo Drive & GPIO/Seg7
// =============================================================================
`ifndef SOC_DOSAGE_TEST_SV
`define SOC_DOSAGE_TEST_SV

class soc_dosage_test extends soc_test_base;
    uart_send_byte_seq uart_seq;

    `uvm_component_utils(soc_dosage_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("DOSAGE_TEST", "==================================================", UVM_NONE)
        `uvm_info("DOSAGE_TEST", "  Starting Nominal Dosage Sequence Test           ", UVM_NONE)
        `uvm_info("DOSAGE_TEST", "==================================================", UVM_NONE)

        // Set test mode = 4 (Bidirectional dosage flow)
        core_vif.test_mode = 32'd4;

        @(posedge core_vif.rst_n);

        // Wait until core is ready for dosage command
        `uvm_info("DOSAGE_TEST", "Waiting for core readiness marker (0x55AA0041)...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0041);
        #1us;

        // Transmit dosage prescription byte (0xC8 = 200/256 ≈ 78% dosage power)
        `uvm_info("DOSAGE_TEST", "Transmitting dosage prescription byte 0xC8 into UART RX...", UVM_LOW)
        uart_seq = uart_send_byte_seq::type_id::create("uart_seq");
        uart_seq.byte_val = 8'hC8;
        uart_seq.baud_div = 16;
        uart_seq.start(env.v_seqr.uart_seqr);

        // Wait for core to compute, program PWM, reflect on GPIO/Seg7, and assert pass marker
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0040 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0040) begin
                    `uvm_info("DOSAGE_TEST", "Nominal Dosage Test completed successfully with marker 0x55AA0040!", UVM_LOW)
                end else begin
                    `uvm_error("DOSAGE_TEST", "Nominal Dosage Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TIMEOUT", "Timeout waiting for dosage completion marker!")
            end
        join_any

        #50us; // Allow PWM pulses to be measured by safety VIP monitor
        phase.drop_objection(this);
    endtask
endclass

`endif
