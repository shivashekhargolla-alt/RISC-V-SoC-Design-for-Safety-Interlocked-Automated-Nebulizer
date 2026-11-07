// =============================================================================
// PWM Sequence Item
// =============================================================================
`ifndef PWM_ITEM_SV
`define PWM_ITEM_SV

class pwm_item extends uvm_sequence_item;
    rand bit force_disable;
    int      period_ticks;
    int      high_ticks;
    int      duty_pct;
    int      pulse_cnt;

    `uvm_object_utils_begin(pwm_item)
        `uvm_field_int(force_disable, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(period_ticks,  UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(high_ticks,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(duty_pct,      UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(pulse_cnt,     UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "pwm_item");
        super.new(name);
        force_disable = 0;
        period_ticks  = 0;
        high_ticks    = 0;
        duty_pct      = 0;
        pulse_cnt     = 0;
    endfunction
endclass

`endif
