// =============================================================================
// UART UVM Interface
// =============================================================================
`ifndef UART_IF_SV
`define UART_IF_SV

interface uart_if(input logic clk, input logic rst_n);
    logic uart_rx_i;
    logic uart_tx_o;
    logic uart_irq_o;
    logic [7:0] rx_byte_mon;

    // Clocking block for driver
    clocking drv_cb @(posedge clk);
        default input #1step output #1step;
        output uart_rx_i;
        input  uart_tx_o;
        input  uart_irq_o;
    endclocking

    // Clocking block for monitor
    clocking mon_cb @(posedge clk);
        default input #1step output #1step;
        input uart_rx_i;
        input uart_tx_o;
        input uart_irq_o;
    endclocking

    modport drv_mp (clocking drv_cb, input clk, input rst_n);
    modport mon_mp (clocking mon_cb, input clk, input rst_n);
endinterface

`endif
