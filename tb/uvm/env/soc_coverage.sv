// =============================================================================
// Top-Level Functional Coverage Collector for NebuCore SoC
// =============================================================================
`ifndef SOC_COVERAGE_SV
`define SOC_COVERAGE_SV

class soc_coverage extends uvm_subscriber #(soc_core_item);
    `uvm_component_utils(soc_coverage)

    // Current sampled values
    bit [31:0] cur_pc;
    bit [31:0] cur_marker;
    bit [7:0]  cur_uart_char;
    bit [7:0]  cur_gpio_out;
    bit [7:0]  cur_pwm_duty;
    bit        cur_pwm_disabled;
    bit [3:0]  cur_seg7_digit;

    // ── Functional Covergroups ───────────────────────────────────────────────
    covergroup cg_soc_markers;
        option.per_instance = 1;
        option.name = "cg_soc_milestones";
        cp_marker: coverpoint cur_marker {
            bins boot_done   = {32'h55AA0001};
            bins data_pass   = {32'h55AA0010};
            bins rv_ips_pass = {32'h55AA0020};
            bins ips_rv_pass = {32'h55AA0030};
            bins bidir_pass  = {32'h55AA0040};
            bins all_pass    = {32'h55AA00FF};
        }
    endgroup

    covergroup cg_peripherals;
        option.per_instance = 1;
        option.name = "cg_soc_peripherals";

        cp_pwm_duty: coverpoint cur_pwm_duty {
            bins zero    = {0};
            bins low     = {[1:64]};
            bins nominal = {[65:192]};
            bins high    = {[193:255]};
        }

        cp_pwm_safety: coverpoint cur_pwm_disabled {
            bins normal_run = {0};
            bins override   = {1};
        }

        cp_gpio_out: coverpoint cur_gpio_out {
            bins pattern_a5 = {8'hA5};
            bins pattern_5a = {8'h5A};
            bins pattern_c3 = {8'hC3};
            bins loopback   = {8'hC8};
        }

        cp_seg7: coverpoint cur_seg7_digit {
            bins digits[] = {[0:15]};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_soc_markers  = new();
        cg_peripherals  = new();
    endfunction

    virtual function void write(soc_core_item t);
        if (t.evt_type == soc_core_item::MARKER_EVT) begin
            cur_marker = t.marker_val;
            cg_soc_markers.sample();
        end else if (t.evt_type == soc_core_item::COMMIT_EVT) begin
            cur_pc = t.pc;
        end
    endfunction

    function void sample_pwm(bit [7:0] duty, bit disabled);
        cur_pwm_duty     = duty;
        cur_pwm_disabled = disabled;
        cg_peripherals.sample();
    endfunction

    function void sample_gpio(bit [7:0] gpio_out);
        cur_gpio_out = gpio_out;
        cg_peripherals.sample();
    endfunction

    function void sample_seg7(bit [3:0] digit);
        cur_seg7_digit = digit;
        cg_peripherals.sample();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE", $sformatf("SoC Milestones Coverage: %0.2f%%, Peripheral Coverage: %0.2f%%",
                  cg_soc_markers.get_coverage(), cg_peripherals.get_coverage()), UVM_LOW)
    endfunction
endclass

`endif
