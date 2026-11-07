// =============================================================================
// Seven-Segment Sequence Item
// =============================================================================
`ifndef SEG7_ITEM_SV
`define SEG7_ITEM_SV

class seg7_item extends uvm_sequence_item;
    bit [6:0] seg_pattern;
    bit [3:0] digit_sel;
    int       digit_idx;
    bit [3:0] decoded_val;

    `uvm_object_utils_begin(seg7_item)
        `uvm_field_int(seg_pattern, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(digit_sel,   UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(digit_idx,   UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(decoded_val, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "seg7_item");
        super.new(name);
    endfunction
endclass

`endif
