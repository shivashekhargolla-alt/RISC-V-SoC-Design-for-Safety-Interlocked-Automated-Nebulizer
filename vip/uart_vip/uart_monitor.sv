// =============================================================================
// UART Monitor (Monitors serial uart_tx_o and uart_rx_i, deserializes into bytes)
// =============================================================================
`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;
    virtual uart_if vif;
    uvm_analysis_port #(uart_item) ap;
    int baud_div = 16;

    // Monitored statistics and captured data
    int    rx_byte_count   = 0;
    string rx_string       = "";
    string rx_hex_data     = "";
    int    tx_byte_count   = 0;
    string tx_string       = "";

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
            monitor_rx();
            monitor_tx();
            monitor_irq();
        join
    endtask

    // ── Monitor Inbound Data: VIP Driver -> SoC uart_rx_i ───────────────────
    task monitor_rx();
        bit [7:0] rx_byte;
        uart_item item;

        forever begin
            // Wait for start bit (falling edge of uart_rx_i)
            @(negedge vif.uart_rx_i);

            // Wait half bit time to reach center of start bit
            repeat (baud_div / 2) @(posedge vif.clk);
            if (vif.uart_rx_i == 1'b0) begin
                // Sample 8 data bits at center of each bit
                for (int i = 0; i < 8; i++) begin
                    repeat (baud_div) @(posedge vif.clk);
                    rx_byte[i] = vif.uart_rx_i;
                end

                // Wait for stop bit
                repeat (baud_div) @(posedge vif.clk);

                rx_byte_count++;
                rx_string = {rx_string, string'(rx_byte)};
                if (rx_hex_data == "")
                    rx_hex_data = $sformatf("0x%02h ('%c')", rx_byte, rx_byte);
                else
                    rx_hex_data = $sformatf("%s, 0x%02h ('%c')", rx_hex_data, rx_byte, rx_byte);

                item = uart_item::type_id::create("mon_rx_item");
                item.data_byte = rx_byte;
                item.is_tx     = 1'b0;
                item.baud_div  = baud_div;

                vif.rx_byte_mon = rx_byte;
                `uvm_info("UART_MON", $sformatf(">>> [UART_RX MONITORED] Byte #%0d = 0x%02h ('%c') on uart_rx_i",
                          rx_byte_count, rx_byte, rx_byte), UVM_NONE)
                ap.write(item);
            end
        end
    endtask

    // ── Monitor Outbound Data: SoC uart_tx_o -> Console ─────────────────────
    task monitor_tx();
        bit [7:0] tx_char;
        uart_item item;

        forever begin
            // Wait for start bit (falling edge of uart_tx_o)
            @(negedge vif.uart_tx_o);

            // Wait half bit time to reach center of start bit
            repeat (baud_div / 2) @(posedge vif.clk);
            if (vif.uart_tx_o == 1'b0) begin
                // Sample 8 data bits at center of each bit
                for (int i = 0; i < 8; i++) begin
                    repeat (baud_div) @(posedge vif.clk);
                    tx_char[i] = vif.uart_tx_o;
                end

                // Wait for stop bit
                repeat (baud_div) @(posedge vif.clk);

                tx_byte_count++;
                tx_string = {tx_string, string'(tx_char)};

                item = uart_item::type_id::create("mon_tx_item");
                item.data_byte = tx_char;
                item.is_tx     = 1'b1;
                item.baud_div  = baud_div;

                `uvm_info("UART_MON", $sformatf("Observed TX byte: 0x%02h ('%c')", tx_char, tx_char), UVM_HIGH)
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

    // ── Report Phase: Print complete monitor data activity summary ───────────
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("UART_MON", "==================================================================", UVM_NONE)
        `uvm_info("UART_MON", "           UART VIP MONITOR: DATA ACTIVITY REPORT                 ", UVM_NONE)
        `uvm_info("UART_MON", "==================================================================", UVM_NONE)
        `uvm_info("UART_MON", $sformatf("  Monitored RX Bytes (VIP Driver -> Core) : %0d bytes", rx_byte_count), UVM_NONE)
        `uvm_info("UART_MON", $sformatf("  Captured RX Payload String              : \"%s\"", rx_string), UVM_NONE)
        `uvm_info("UART_MON", $sformatf("  Captured RX Byte Sequence               : [ %s ]", rx_hex_data), UVM_NONE)
        `uvm_info("UART_MON", $sformatf("  Monitored TX Bytes (Core -> Console)    : %0d bytes", tx_byte_count), UVM_NONE)
        `uvm_info("UART_MON", "==================================================================", UVM_NONE)
    endfunction
endclass

`endif
