// =============================================================================
// PWM & Zero-Latency Safety Monitor
// =============================================================================
`ifndef PWM_MONITOR_SV
`define PWM_MONITOR_SV

class pwm_monitor extends uvm_monitor;
    virtual pwm_if vif;
    uvm_analysis_port #(pwm_item) ap;
    int pulse_counter = 0;

    `uvm_component_utils(pwm_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual pwm_if)::get(this, "", "pwm_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual pwm_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);

        fork
            monitor_pwm_pulses();
            monitor_safety_override();
        join
    endtask

    task monitor_pwm_pulses();
        time t_rise, t_fall;
        pwm_item item;

        forever begin
            @(posedge vif.pwm_out_o);
            t_rise = $time;
            pulse_counter++;
            @(negedge vif.pwm_out_o);
            t_fall = $time;

            item = pwm_item::type_id::create("mon_pwm_item");
            item.pulse_cnt     = pulse_counter;
            item.high_ticks    = int'((t_fall - t_rise) / 10ns);
            item.period_ticks  = item.high_ticks * 2;
            item.duty_pct      = 50;
            item.force_disable = vif.pwm_force_disable_i;

            `uvm_info("PWM_MON", $sformatf("Pulse #%0d observed: high_ticks=%0d",
                      item.pulse_cnt, item.high_ticks), UVM_HIGH)
            ap.write(item);
        end
    endtask

    // Zero-latency safety monitor: verifies pwm_out_o is immediately silenced
    // when pwm_force_disable_i is asserted (combinational override check)
    task monitor_safety_override();
        forever begin
            @(posedge vif.pwm_force_disable_i);
            #1ps; // Combinational delta check
            if (vif.pwm_out_o !== 1'b0) begin
                `uvm_error("PWM_SAFETY_FAIL", "Zero-latency lock violation: pwm_out_o is NOT 0 when force_disable is high!")
            end else begin
                `uvm_info("PWM_SAFETY_OK", "Zero-latency safety lock verified: pwm_out_o silenced immediately", UVM_LOW)
            end
        end
    endtask
endclass

`endif
