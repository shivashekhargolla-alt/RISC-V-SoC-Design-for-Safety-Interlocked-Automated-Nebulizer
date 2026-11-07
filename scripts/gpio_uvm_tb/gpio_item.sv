// =============================================================================
// GPIO Sequence Item
// =============================================================================
`ifndef GPIO_ITEM_SV
`define GPIO_ITEM_SV

class gpio_item extends uvm_sequence_item;
    rand bit [7:0] pin_in;
    bit [7:0]      pin_out;
    bit [7:0]      pin_oe;
    bit            gpio_irq;

    `uvm_object_utils_begin(gpio_item)
        `uvm_field_int(pin_in,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(pin_out,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(pin_oe,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(gpio_irq, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "gpio_item");
        super.new(name);
        pin_in   = 8'h00;
        pin_out  = 8'h00;
        pin_oe   = 8'h00;
        gpio_irq = 1'b0;
    endfunction
endclass

`endif
