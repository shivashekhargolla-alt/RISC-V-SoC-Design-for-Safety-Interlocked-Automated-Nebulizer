// =============================================================================
// SoC Full Verification Suite Test (Runs all 4 verification phases)
// =============================================================================
`ifndef SOC_ALL_TEST_SV
`define SOC_ALL_TEST_SV

class soc_all_test extends soc_base_test;
    uart_send_packet_seq uart_pkt_seq;
    uart_send_byte_seq   uart_byte_seq;
    gpio_drive_seq       gpio_seq;

    `uvm_component_utils(soc_all_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", "  Starting Comprehensive SoC UVM Test Suite       ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        // Set test mode = 0 (run all phases)
        core_vif.test_mode = 32'd0;

        @(posedge core_vif.rst_n);

        // ── Phase 1: Data Transfer Test ─────────────────────────────────────
        `uvm_info("TEST", ">>> PHASE 1: AXI Data Transfers & Register R/W...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0010 || core_vif.completion_marker == 32'hDEADFA11);
        if (core_vif.completion_marker != 32'h55AA0010) `uvm_fatal("TEST", "Phase 1 Failed!")

        // ── Phase 2: RISC-V to IPs Test ────────────────────────────────────
        `uvm_info("TEST", ">>> PHASE 2: RISC-V -> Peripheral IPs (UART TX, GPIO, PWM, Seg7)...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0020 || core_vif.completion_marker == 32'hDEADFA11);
        if (core_vif.completion_marker != 32'h55AA0020) `uvm_fatal("TEST", "Phase 2 Failed!")

        // ── Phase 3: IPs to RISC-V Test ────────────────────────────────────
        `uvm_info("TEST", ">>> PHASE 3: Peripheral IPs -> RISC-V Core...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0031 || core_vif.completion_marker == 32'hDEADFA11);
        #500ns;

        // Drive external GPIO input pattern
        gpio_seq = gpio_drive_seq::type_id::create("gpio_seq");
        gpio_seq.pattern = 8'h3C;
        fork
            gpio_seq.start(env.v_seqr.gpio_seqr);
        join_none

        // Drive external UART stream: "UVM1"
        uart_pkt_seq = uart_send_packet_seq::type_id::create("uart_pkt_seq");
        uart_pkt_seq.payload  = "UVM1";
        uart_pkt_seq.baud_div = 16;
        uart_pkt_seq.start(env.v_seqr.uart_seqr);

        wait (core_vif.completion_marker == 32'h55AA0030 || core_vif.completion_marker == 32'hDEADFA11);
        if (core_vif.completion_marker != 32'h55AA0030) `uvm_fatal("TEST", "Phase 3 Failed!")

        // ── Phase 4: Bidirectional Flow Test ───────────────────────────────
        `uvm_info("TEST", ">>> PHASE 4: Bidirectional / Cross-IP Control...", UVM_LOW)
        wait (core_vif.completion_marker == 32'h55AA0041 || core_vif.completion_marker == 32'hDEADFA11);
        #500ns;

        // Inject command byte 0xC8 (200 = ~78% duty cycle)
        uart_byte_seq = uart_send_byte_seq::type_id::create("uart_byte_seq");
        uart_byte_seq.byte_val = 8'hC8;
        uart_byte_seq.baud_div = 16;
        uart_byte_seq.start(env.v_seqr.uart_seqr);

        wait (core_vif.completion_marker == 32'h55AA0040 || core_vif.completion_marker == 32'hDEADFA11);
        if (core_vif.completion_marker != 32'h55AA0040) `uvm_fatal("TEST", "Phase 4 Failed!")

        // ── All Done ────────────────────────────────────────────────────────
        wait (core_vif.completion_marker == 32'h55AA00FF || core_vif.completion_marker == 32'hDEADFA11);
        #50us; // Allow several PWM pulses to be captured by monitor

        `uvm_info("TEST", "==================================================", UVM_NONE)
        `uvm_info("TEST", "  ALL 4 VERIFICATION PHASES COMPLETED!            ", UVM_NONE)
        `uvm_info("TEST", "==================================================", UVM_NONE)

        phase.drop_objection(this);
    endtask
endclass

`endif
