// =============================================================================
// UART Sequence Item
// =============================================================================
`ifndef UART_ITEM_SV
`define UART_ITEM_SV

class uart_item extends uvm_sequence_item;
    rand bit [7:0] data_byte;
    rand int       baud_div;
    bit            is_tx; // 0 = RX (driven into DUT), 1 = TX (monitored from DUT)

    `uvm_object_utils_begin(uart_item)
        `uvm_field_int(data_byte, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(baud_div,  UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(is_tx,     UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "uart_item");
        super.new(name);
        baud_div = 16;
        is_tx = 0;
    endfunction

    constraint default_baud_div_c {
        baud_div inside {16, 32, 64, 868};
    }
endclass

`endif
