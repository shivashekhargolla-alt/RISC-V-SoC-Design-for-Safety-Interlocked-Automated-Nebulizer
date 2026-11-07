// =============================================================================
// UART Driver (Drives serial packets into uart_rx_i)
// =============================================================================
`ifndef UART_DRIVER_SV
`define UART_DRIVER_SV

class uart_driver extends uvm_driver #(uart_item);
    virtual uart_if vif;

    `uvm_component_utils(uart_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual uart_if)::get(this, "", "uart_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual uart_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        // Idle state: RX line is HIGH
        vif.uart_rx_i <= 1'b1;
        @(posedge vif.rst_n);

        forever begin
            seq_item_port.get_next_item(req);
            drive_byte(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_byte(uart_item item);
        int div = (item.baud_div > 0) ? item.baud_div : 16;
        `uvm_info("UART_DRV", $sformatf("Driving byte 0x%02h ('%c') with baud_div=%0d",
                  item.data_byte, item.data_byte, div), UVM_NONE)

        // Line idle
        vif.rx_byte_mon <= item.data_byte;
        vif.uart_rx_i <= 1'b1;
        repeat (div) @(posedge vif.clk);

        // Start bit: LOW
        vif.uart_rx_i <= 1'b0;
        repeat (div) @(posedge vif.clk);

        // 8 Data bits: LSB first
        for (int b = 0; b < 8; b++) begin
            vif.uart_rx_i <= item.data_byte[b];
            repeat (div) @(posedge vif.clk);
        end

        // Stop bit: HIGH
        vif.uart_rx_i <= 1'b1;
        repeat (div * 2) @(posedge vif.clk);
    endtask
endclass

`endif
