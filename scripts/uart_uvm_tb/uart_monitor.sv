// =============================================================================
// UART Monitor (Monitors serial uart_tx_o and deserializes into bytes)
// =============================================================================
`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;
    virtual uart_if vif;
    uvm_analysis_port #(uart_item) ap;
    int baud_div = 16;

    `uvm_component_utils(uart_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual uart_if)::get(this, "", "uart_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual uart_if not found in uvm_config_db")
        end
        void'(uvm_config_db #(int)::get(this, "", "baud_div", baud_div));
    endfunction

    task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);

        fork
            monitor_tx();
            monitor_irq();
        join
    endtask

    task monitor_tx();
        bit [7:0] rx_char;
        uart_item item;

        forever begin
            // Wait for start bit (falling edge of uart_tx_o)
            @(negedge vif.uart_tx_o);

            // Wait half bit time to reach center of start bit
            repeat (baud_div / 2) @(posedge vif.clk);
            if (vif.uart_tx_o == 1'b0) begin
                // Valid start bit, sample 8 data bits at center of each bit
                for (int i = 0; i < 8; i++) begin
                    repeat (baud_div) @(posedge vif.clk);
                    rx_char[i] = vif.uart_tx_o;
                end

                // Wait for stop bit
                repeat (baud_div) @(posedge vif.clk);

                item = uart_item::type_id::create("mon_tx_item");
                item.data_byte = rx_char;
                item.is_tx     = 1'b1;
                item.baud_div  = baud_div;

                `uvm_info("UART_MON", $sformatf("Observed TX byte: 0x%02h ('%c')", rx_char, rx_char), UVM_HIGH)
                ap.write(item);
            end
        end
    endtask

    task monitor_irq();
        forever begin
            @(posedge vif.uart_irq_o);
            `uvm_info("UART_MON", "uart_irq_o asserted", UVM_FULL)
            @(negedge vif.uart_irq_o);
        end
    endtask
endclass

`endif
