// =============================================================================
// GPIO Sequence Item (Supports Volume Switches & Glitch Injection)
// =============================================================================
`ifndef GPIO_ITEM_SV
`define GPIO_ITEM_SV

class gpio_item extends uvm_sequence_item;
    rand bit [7:0] pin_in;
    rand bit       is_glitch;
    rand int       glitch_duration_ns;
    bit [7:0]      pin_out;
    bit [7:0]      pin_oe;
    bit            gpio_irq;

    constraint c_glitch {
        glitch_duration_ns inside {[1:20]};
    }

    `uvm_object_utils_begin(gpio_item)
        `uvm_field_int(pin_in,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(is_glitch,          UVM_ALL_ON)
        `uvm_field_int(glitch_duration_ns, UVM_ALL_ON)
        `uvm_field_int(pin_out,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(pin_oe,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(gpio_irq,           UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "gpio_item");
        super.new(name);
        pin_in             = 8'h00;
        is_glitch          = 1'b0;
        glitch_duration_ns = 5;
        pin_out            = 8'h00;
        pin_oe             = 8'h00;
        gpio_irq           = 1'b0;
    endfunction
endclass

`endif
