// =============================================================================
// SoC IPs to RISC-V Test (External stimulus on UART RX & GPIO IN -> Core verifies)
// =============================================================================
`ifndef SOC_IPS_TO_RISCV_TEST_SV
`define SOC_IPS_TO_RISCV_TEST_SV

class soc_ips_to_riscv_test extends soc_base_test;
    uart_send_packet_seq uart_seq;
    gpio_drive_seq       gpio_seq;

    `uvm_component_utils(soc_ips_to_riscv_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "Starting soc_ips_to_riscv_test...", UVM_LOW)

        // Set test mode = 3
        core_vif.test_mode = 32'd3;

        @(posedge core_vif.rst_n);

        // Wait until core signals it is listening (marker 0x55AA0031)
        `uvm_info("TEST", "Waiting for core to configure UART RX & GPIO IN...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0031);
        #1us;

        // Drive external GPIO input
        gpio_seq = gpio_drive_seq::type_id::create("gpio_seq");
        gpio_seq.pattern = 8'h3C;
        fork
            gpio_seq.start(env.v_seqr.gpio_seqr);
        join_none

        // Drive external UART stream: "UVM1"
        `uvm_info("TEST", "Injecting UART payload 'UVM1' into uart_rx_i...", UVM_LOW)
        uart_seq = uart_send_packet_seq::type_id::create("uart_seq");
        uart_seq.payload  = "UVM1";
        uart_seq.baud_div = 16;
        uart_seq.start(env.v_seqr.uart_seqr);

        // Wait for core to verify received data and assert pass marker 0x55AA0030
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0030 || core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0030) begin
                    `uvm_info("TEST", "IPs -> RISC-V Test completed successfully with marker 0x55AA0030!", UVM_LOW)
                end else begin
                    `uvm_error("TEST", "IPs -> RISC-V Test failed with marker 0xDEADFA11!")
                end
            end
            begin
                #20ms;
                `uvm_fatal("TEST_TIMEOUT", "Timeout waiting for IPs to RISC-V completion marker!")
            end
        join_any

        #10us;
        phase.drop_objection(this);
    endtask
endclass

`endif
