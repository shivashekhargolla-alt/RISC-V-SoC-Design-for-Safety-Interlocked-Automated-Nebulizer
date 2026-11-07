// =============================================================================
// Dedicated UVM Test: UART VIP Driver -> RISC-V Core Transfer
// =============================================================================
`ifndef SOC_UART_TO_RISCV_TEST_SV
`define SOC_UART_TO_RISCV_TEST_SV

class soc_uart_to_riscv_test extends soc_test_base;
    uart_send_packet_seq uart_seq;

    `uvm_component_utils(soc_uart_to_riscv_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("UART_TO_RV", "==================================================", UVM_NONE)
        `uvm_info("UART_TO_RV", "  Starting UART VIP Driver -> RISC-V Core Test   ", UVM_NONE)
        `uvm_info("UART_TO_RV", "==================================================", UVM_NONE)

        // Set test mode = 5 (Dedicated UART VIP Driver -> RISC-V Core)
        core_vif.test_mode = 32'd5;

        @(posedge core_vif.rst_n);

        // Wait until core signals it is listening (marker 0x55AA0051)
        `uvm_info("UART_TO_RV", "Waiting for core to configure UART RX and signal readiness (0x55AA0051)...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0051 || core_vif.completion_marker == 32'hDEADFA11);
        if (core_vif.completion_marker != 32'h55AA0051) begin
            `uvm_fatal("UART_TO_RV", "Core failed initialization before UART RX readiness!")
        end
        #1us;

        // Drive external UART stream from VIP driver: "RISC" (0x52, 0x49, 0x53, 0x43)
        `uvm_info("UART_TO_RV", ">>> Injecting UART payload 'RISC' via UART VIP Driver into uart_rx_i...", UVM_LOW)
        uart_seq = uart_send_packet_seq::type_id::create("uart_seq");
        uart_seq.payload  = "RISC";
        uart_seq.baud_div = 16;
        uart_seq.start(env.v_seqr.uart_seqr);

        // Wait for core to verify received data and assert pass marker 0x55AA0050
        fork
            begin
                wait (core_vif.completion_marker == 32'h55AA0050 || 
                      core_vif.completion_marker == 32'h55AA00FF || 
                      core_vif.completion_marker == 32'hDEADFA11);
                if (core_vif.completion_marker == 32'h55AA0050 || core_vif.completion_marker == 32'h55AA00FF) begin
                    `uvm_info("UART_TO_RV", ">>> SUCCESS: UART VIP Driver -> RISC-V Core transfer PASSED (Marker 0x55AA0050)!", UVM_LOW)
                end else begin
                    `uvm_error("UART_TO_RV", "FAILED: Core signaled error marker 0xDEADFA11!")
                end
            end
            begin
                #10ms;
                `uvm_fatal("UART_TO_RV", "TIMEOUT: Core did not acknowledge UART payload within 10ms!")
            end
        join_any

        #5us;
        `uvm_info("UART_TO_RV", "==================================================", UVM_NONE)
        `uvm_info("UART_TO_RV", "  UART VIP Driver -> RISC-V Core Test COMPLETED  ", UVM_NONE)
        `uvm_info("UART_TO_RV", "==================================================", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

`endif
