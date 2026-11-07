// =============================================================================
// PWM UVM Interface
// =============================================================================
`ifndef PWM_IF_SV
`define PWM_IF_SV

interface pwm_if(input logic clk, input logic rst_n);
    logic pwm_force_disable_i;
    logic pwm_out_o;

    clocking drv_cb @(posedge clk);
        default input #1step output #1step;
        output pwm_force_disable_i;
        input  pwm_out_o;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step output #1step;
        input pwm_force_disable_i;
        input pwm_out_o;
    endclocking

    modport drv_mp (clocking drv_cb, input clk, input rst_n);
    modport mon_mp (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
