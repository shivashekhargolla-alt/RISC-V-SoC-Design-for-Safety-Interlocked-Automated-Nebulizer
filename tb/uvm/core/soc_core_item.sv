// =============================================================================
// SoC Core Item (Trace & Marker events)
// =============================================================================
`ifndef SOC_CORE_ITEM_SV
`define SOC_CORE_ITEM_SV

class soc_core_item extends uvm_sequence_item;
    typedef enum { COMMIT_EVT, MARKER_EVT, EXCEPT_EVT } event_type_e;

    event_type_e evt_type;
    bit [31:0]   pc;
    bit [31:0]   insn;
    bit [31:0]   marker_val;
    bit [4:0]    cause;

    `uvm_object_utils_begin(soc_core_item)
        `uvm_field_enum(event_type_e, evt_type,   UVM_ALL_ON)
        `uvm_field_int(pc,                        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(insn,                      UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(marker_val,                UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(cause,                     UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "soc_core_item");
        super.new(name);
    endfunction
endclass

`endif
