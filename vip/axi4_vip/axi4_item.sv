// =============================================================================
// 64-bit Full AXI4 Sequence Item
// =============================================================================
`ifndef AXI4_ITEM_SV
`define AXI4_ITEM_SV

class axi4_item extends uvm_sequence_item;
    typedef enum { READ, WRITE } xfer_type_e;

    rand xfer_type_e       xfer_type;
    rand bit [7:0]         id;
    rand bit [31:0]        addr;
    rand bit [7:0]         len;       // Burst length (0 = 1 beat, 255 = 256 beats)
    rand bit [2:0]         size;      // 3 = 8 bytes (64-bit), 2 = 4 bytes (32-bit)
    rand bit [1:0]         burst;     // 2'b01 = INCR
    rand bit [63:0]        data[];    // Dynamic array for beats
    rand bit [7:0]         strb[];    // Byte enables per beat
    bit [1:0]              resp;      // 2'b00 = OKAY

    constraint c_size {
        size inside {0, 1, 2, 3};
        burst == 2'b01; // INCR
        len inside {[0:15]}; // reasonable burst limit for tests
    }

    constraint c_data_len {
        data.size() == len + 1;
        strb.size() == len + 1;
    }

    `uvm_object_utils_begin(axi4_item)
        `uvm_field_enum(xfer_type_e, xfer_type, UVM_ALL_ON)
        `uvm_field_int(id,        UVM_ALL_ON)
        `uvm_field_int(addr,      UVM_ALL_ON)
        `uvm_field_int(len,       UVM_ALL_ON)
        `uvm_field_int(size,      UVM_ALL_ON)
        `uvm_field_int(burst,     UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_array_int(strb, UVM_ALL_ON)
        `uvm_field_int(resp,      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi4_item");
        super.new(name);
    endfunction
endclass

`endif
