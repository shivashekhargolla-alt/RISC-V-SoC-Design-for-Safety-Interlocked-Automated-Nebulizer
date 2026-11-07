// =============================================================================
// SoC UVM Scoreboard
// =============================================================================
`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_pwm)
`uvm_analysis_imp_decl(_seg7)
`uvm_analysis_imp_decl(_core)

class soc_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_uart #(uart_item, soc_scoreboard)     uart_export;
    uvm_analysis_imp_gpio #(gpio_item, soc_scoreboard)     gpio_export;
    uvm_analysis_imp_pwm  #(pwm_item,  soc_scoreboard)     pwm_export;
    uvm_analysis_imp_seg7 #(seg7_item, soc_scoreboard)     seg7_export;
    uvm_analysis_imp_core #(soc_core_item, soc_scoreboard) core_export;

    // Test tracking counters & flags
    int uart_tx_chars_seen = 0;
    string uart_tx_buffer  = "";

    int gpio_transitions_seen = 0;
    bit [7:0] last_gpio_out   = 8'h00;
    bit saw_gpio_pattern_a5   = 0;
    bit saw_gpio_pattern_5a   = 0;
    bit saw_gpio_pattern_c3   = 0;

    int pwm_pulses_seen       = 0;
    int last_pwm_duty_pct     = 0;
    bit saw_pwm_active        = 0;

    int seg7_digits_seen      = 0;
    bit [3:0] last_seg7_val   = 4'h0;

    // Milestone markers seen
    bit marker_boot_done       = 0;
    bit marker_data_xfer_pass  = 0;
    bit marker_rv_to_ips_pass  = 0;
    bit marker_ips_to_rv_wait  = 0;
    bit marker_ips_to_rv_pass  = 0;
    bit marker_bidir_wait      = 0;
    bit marker_bidir_pass      = 0;
    bit marker_all_pass        = 0;
    bit marker_fail            = 0;

    int total_checks_passed    = 0;
    int total_checks_failed    = 0;

    `uvm_component_utils(soc_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        uart_export = new("uart_export", this);
        gpio_export = new("gpio_export", this);
        pwm_export  = new("pwm_export",  this);
        seg7_export = new("seg7_export", this);
        core_export = new("core_export", this);
    endfunction

    // ── UART transaction callback ──────────────────────────────────────────
    virtual function void write_uart(uart_item item);
        if (item.is_tx) begin
            uart_tx_chars_seen++;
            uart_tx_buffer = {uart_tx_buffer, string'(item.data_byte)};
            `uvm_info("SB_UART", $sformatf("Observed UART TX char #%0d: '%c' (0x%02h)",
                      uart_tx_chars_seen, item.data_byte, item.data_byte), UVM_HIGH)
        end
    endfunction

    // ── GPIO transaction callback ──────────────────────────────────────────
    virtual function void write_gpio(gpio_item item);
        gpio_transitions_seen++;
        last_gpio_out = item.pin_out;
        if (item.pin_out == 8'hA5) saw_gpio_pattern_a5 = 1;
        if (item.pin_out == 8'h5A) saw_gpio_pattern_5a = 1;
        if (item.pin_out == 8'hC3) saw_gpio_pattern_c3 = 1;

        `uvm_info("SB_GPIO", $sformatf("GPIO state: out=0x%02h, oe=0x%02h, in=0x%02h",
                  item.pin_out, item.pin_oe, item.pin_in), UVM_HIGH)
    endfunction

    // ── PWM transaction callback ───────────────────────────────────────────
    virtual function void write_pwm(pwm_item item);
        pwm_pulses_seen++;
        last_pwm_duty_pct = item.duty_pct;
        if (item.pulse_cnt > 0) saw_pwm_active = 1;

        `uvm_info("SB_PWM", $sformatf("PWM Pulse #%0d: period=%0d, high=%0d, duty=%0d%%",
                  item.pulse_cnt, item.period_ticks, item.high_ticks, item.duty_pct), UVM_HIGH)
    endfunction

    // ── Seg7 transaction callback ──────────────────────────────────────────
    virtual function void write_seg7(seg7_item item);
        seg7_digits_seen++;
        last_seg7_val = item.decoded_val;
        `uvm_info("SB_SEG7", $sformatf("Seg7 update: digit_idx=%0d, val=0x%01h",
                  item.digit_idx, item.decoded_val), UVM_HIGH)
    endfunction

    // ── Core marker callback ───────────────────────────────────────────────
    virtual function void write_core(soc_core_item item);
        if (item.evt_type == soc_core_item::MARKER_EVT) begin
            case (item.marker_val)
                32'h55AA0001: marker_boot_done      = 1;
                32'h55AA0010: marker_data_xfer_pass = 1;
                32'h55AA0020: marker_rv_to_ips_pass = 1;
                32'h55AA0031: marker_ips_to_rv_wait = 1;
                32'h55AA0030: marker_ips_to_rv_pass = 1;
                32'h55AA0041: marker_bidir_wait     = 1;
                32'h55AA0040: marker_bidir_pass     = 1;
                32'h55AA00FF: marker_all_pass       = 1;
                32'hDEADFA11: marker_fail           = 1;
                default: ;
            endcase
        end
    endfunction

    // ── Report Phase Summary ───────────────────────────────────────────────
    virtual function void report_phase(uvm_phase phase);
        string active_test = "soc_all_test";
        bit check_t1 = 1'b1;
        bit check_t2 = 1'b1;
        bit check_t3 = 1'b1;
        bit check_t4 = 1'b1;
        bit data_xfer_ok;
        bit rv_to_ips_ok;
        bit ips_to_rv_ok;
        bit bidir_ok;

        void'($value$plusargs("UVM_TESTNAME=%s", active_test));

        if (active_test == "soc_data_transfer_test") begin
            check_t2 = 1'b0; check_t3 = 1'b0; check_t4 = 1'b0;
        end else if (active_test == "soc_riscv_to_ips_test") begin
            check_t1 = 1'b0; check_t3 = 1'b0; check_t4 = 1'b0;
        end else if (active_test == "soc_ips_to_riscv_test") begin
            check_t1 = 1'b0; check_t2 = 1'b0; check_t4 = 1'b0;
        end else if (active_test == "soc_bidir_test") begin
            check_t1 = 1'b0; check_t2 = 1'b0; check_t3 = 1'b0;
        end

        data_xfer_ok = marker_data_xfer_pass;
        rv_to_ips_ok = marker_rv_to_ips_pass && (uart_tx_chars_seen > 0) && saw_pwm_active;
        ips_to_rv_ok = marker_ips_to_rv_pass;
        bidir_ok     = marker_bidir_pass;

        `uvm_info("SCOREBOARD", "==================================================================", UVM_NONE)
        `uvm_info("SCOREBOARD", $sformatf("      NebuCore SoC UVM Verification Summary: %s", active_test), UVM_NONE)
        `uvm_info("SCOREBOARD", "==================================================================", UVM_NONE)

        if (check_t1) begin
            if (data_xfer_ok) begin
                `uvm_info("SCOREBOARD", "  [PASS] 1. Data Transfers (SRAM AXI R/W & Peripheral Regs)", UVM_NONE)
                total_checks_passed++;
            end else begin
                `uvm_error("SCOREBOARD", "  [FAIL] 1. Data Transfers (SRAM AXI R/W & Peripheral Regs)")
                total_checks_failed++;
            end
        end

        if (check_t2) begin
            if (rv_to_ips_ok) begin
                `uvm_info("SCOREBOARD", $sformatf("  [PASS] 2. RISC-V -> IPs (UART TX chars=%0d, PWM active=%0b, GPIO trans=%0d)",
                          uart_tx_chars_seen, saw_pwm_active, gpio_transitions_seen), UVM_NONE)
                total_checks_passed++;
            end else begin
                `uvm_error("SCOREBOARD", "  [FAIL] 2. RISC-V -> IPs (Outputs not observed as expected)")
                total_checks_failed++;
            end
        end

        if (check_t3) begin
            if (ips_to_rv_ok) begin
                `uvm_info("SCOREBOARD", "  [PASS] 3. IPs -> RISC-V (UART RX stream + GPIO IN verified by Core)", UVM_NONE)
                total_checks_passed++;
            end else begin
                `uvm_error("SCOREBOARD", "  [FAIL] 3. IPs -> RISC-V (Stimulus verification failed)")
                total_checks_failed++;
            end
        end

        if (check_t4) begin
            if (bidir_ok) begin
                `uvm_info("SCOREBOARD", "  [PASS] 4. Bidirectional Flow (UART RX -> Core compute -> PWM/GPIO drive)", UVM_NONE)
                total_checks_passed++;
            end else begin
                `uvm_error("SCOREBOARD", "  [FAIL] 4. Bidirectional Flow (End-to-end loopback check failed)")
                total_checks_failed++;
            end
        end

        `uvm_info("SCOREBOARD", "------------------------------------------------------------------", UVM_NONE)
        `uvm_info("SCOREBOARD", $sformatf("  Total Scoreboard Checks: Passed=%0d, Failed=%0d",
                  total_checks_passed, total_checks_failed), UVM_NONE)
        `uvm_info("SCOREBOARD", "==================================================================", UVM_NONE)

        if (total_checks_failed == 0 && !marker_fail) begin
            `uvm_info("SCOREBOARD", "  >>> ALL SOC UVM VERIFICATION CHECKS PASSED <<<", UVM_NONE)
        end else begin
            `uvm_fatal("SCOREBOARD", "  >>> SOC UVM VERIFICATION FAILED <<<")
        end
    endfunction
endclass

`endif
