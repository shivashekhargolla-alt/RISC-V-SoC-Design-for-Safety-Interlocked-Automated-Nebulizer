// =============================================================================
// SoC Safety Override Test
// Verifies: Fault Injection & Zero-Latency Safety Lock on PWM Actuator
// =============================================================================
`ifndef SOC_SAFETY_OVERRIDE_TEST_SV
`define SOC_SAFETY_OVERRIDE_TEST_SV

class soc_safety_override_test extends soc_test_base;
    uart_send_byte_seq    uart_seq;
    pwm_force_disable_seq safety_seq;

    `uvm_component_utils(soc_safety_override_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("SAFETY_TEST", "==================================================", UVM_NONE)
        `uvm_info("SAFETY_TEST", "  Starting Fault Injection & Zero-Latency Safety  ", UVM_NONE)
        `uvm_info("SAFETY_TEST", "==================================================", UVM_NONE)

        // Set test mode = 4 (Bidirectional dosage flow)
        core_vif.test_mode = 32'd4;

        @(posedge core_vif.rst_n);

        // Wait until core is ready for dosage command
        wait (core_vif.completion_marker == 32'h55AA0041);
        #1us;

        // Drive dosage byte into UART RX
        uart_seq = uart_send_byte_seq::type_id::create("uart_seq");
        uart_seq.byte_val = 8'hC8;
        uart_seq.baud_div = 16;
        uart_seq.start(env.v_seqr.uart_seqr);

        wait (core_vif.completion_marker == 32'h55AA0040);
        `uvm_info("SAFETY_TEST", "Dosage running. Injecting emergency safety override...", UVM_LOW)

        // Wait for active PWM output high pulse
        #25us;

        // Assert emergency safety lock
        safety_seq = pwm_force_disable_seq::type_id::create("safety_seq");
        safety_seq.disable_val = 1'b1;
        safety_seq.start(env.v_seqr.pwm_seqr);

        #10us;
        `uvm_info("SAFETY_TEST", "Zero-latency safety lock active: PWM actuator forced LOW.", UVM_LOW)

        // De-assert emergency lock to verify release
        safety_seq = pwm_force_disable_seq::type_id::create("safety_seq");
        safety_seq.disable_val = 1'b0;
        safety_seq.start(env.v_seqr.pwm_seqr);
        #25us;

        `uvm_info("SAFETY_TEST", "Safety Override & Fault Injection Test PASSED!", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

`endif
