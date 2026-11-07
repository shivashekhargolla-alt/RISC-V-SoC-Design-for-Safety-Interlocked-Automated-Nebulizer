// =============================================================================
// Seven-Segment Display Agent (Passive monitor agent)
// =============================================================================
`ifndef SEG7_AGENT_SV
`define SEG7_AGENT_SV

class seg7_agent extends uvm_agent;
    seg7_monitor mon;

    `uvm_component_utils(seg7_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = seg7_monitor::type_id::create("mon", this);
    endfunction
endclass

`endif
