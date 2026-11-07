// =============================================================================
// 32-bit AXI-Lite Sequence Item
// =============================================================================
`ifndef AXI_LITE_ITEM_SV
`define AXI_LITE_ITEM_SV

class axi_lite_item extends uvm_sequence_item;
    typedef enum { READ, WRITE } xfer_type_e;

    rand xfer_type_e xfer_type;
    rand bit [31:0]  addr;
    rand bit [31:0]  data;
    rand bit [3:0]   strb;
    bit [1:0]        resp;

    constraint c_default {
        strb == 4'hF;
    }

    `uvm_object_utils_begin(axi_lite_item)
        `uvm_field_enum(xfer_type_e, xfer_type, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(strb, UVM_ALL_ON)
        `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_lite_item");
        super.new(name);
    endfunction
endclass

`endif
