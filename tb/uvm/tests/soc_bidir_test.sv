// =============================================================================
// SoC Bidirectional Loopback Test (UART RX -> Core compute -> PWM/GPIO drive)
// =============================================================================
`ifndef SOC_BIDIR_TEST_SV
`define SOC_BIDIR_TEST_SV

class soc_bidir_test extends soc_base_test;
    uart_send_byte_seq uart_seq;

    `uvm_component_utils(soc_bidir_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting soc_bidir_test...", UVM_LOW)

        // Set test mode = 4
        core_vif.test_mode = 32'd4;

        @(posedge core_vif.rst_n);

        // Wait until core is ready for bidirectional command (marker 0x55AA0041)
        wait (core_vif.completion_marker == 32'h55AA0041);
        #1us;

        // Drive UART byte 0xC8 (200 = ~78% duty cycle)
        `uvm_info("TEST", "Injecting command byte 0xC8 into UART RX...", UVM_LOW)
        uart_seq = uart_send_byte_seq::type_id::create("uart_seq");
        uart_seq.byte_val = 8'hC8;
        uart_seq.baud_div = 16;
        uart_seq.start(env.v_seqr.uart_seqr);

        // Wait for core to compute, program PWM, mirror to GPIO, and assert marker 0x55AA0040
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0040 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0040) begin
                    `uvm_info("TEST", "Bidirectional Loopback Test completed successfully with marker 0x55AA0040!", UVM_LOW)
                end else begin
                    `uvm_error("TEST", "Bidirectional Loopback Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TEST_TIMEOUT", "Timeout waiting for bidirectional completion marker!")
            end
        join_any

        #50us; // Allow several PWM pulses to be captured by monitor
        phase.drop_objection(this);
    endtask
endclass

`endif
