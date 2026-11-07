// =============================================================================
// GPIO UVM Interface
// =============================================================================
`ifndef GPIO_IF_SV
`define GPIO_IF_SV

interface gpio_if(input logic clk, input logic rst_n);
    logic [7:0] gpio_pin_i;
    logic [7:0] gpio_pin_o;
    logic [7:0] gpio_pin_oe;
    logic       gpio_irq_o;

    clocking drv_cb @(posedge clk);
        default input #1step output #1step;
        output gpio_pin_i;
        input  gpio_pin_o;
        input  gpio_pin_oe;
        input  gpio_irq_o;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step output #1step;
        input gpio_pin_i;
        input gpio_pin_o;
        input gpio_pin_oe;
        input gpio_irq_o;
    endclocking

    modport drv_mp (clocking drv_cb, input clk, input rst_n);
    modport mon_mp (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
