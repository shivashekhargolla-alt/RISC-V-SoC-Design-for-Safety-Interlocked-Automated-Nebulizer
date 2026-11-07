// =============================================================================
// 64-bit Full AXI4 Sequencer
// =============================================================================
`ifndef AXI4_SEQUENCER_SV
`define AXI4_SEQUENCER_SV

class axi4_sequencer extends uvm_sequencer #(axi4_item);
    `uvm_component_utils(axi4_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

`endif
