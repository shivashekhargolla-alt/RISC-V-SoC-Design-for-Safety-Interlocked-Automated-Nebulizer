// =============================================================================
// 64-bit Full AXI4 Agent
// =============================================================================
`ifndef AXI4_AGENT_SV
`define AXI4_AGENT_SV

class axi4_agent extends uvm_agent;
    axi4_driver    drv;
    axi4_monitor   mon;
    axi4_sequencer seqr;

    `uvm_component_utils(axi4_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi4_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = axi4_driver::type_id::create("drv", this);
            seqr = axi4_sequencer::type_id::create("seqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass

`endif
