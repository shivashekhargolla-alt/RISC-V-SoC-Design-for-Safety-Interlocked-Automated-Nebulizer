// =============================================================================
// SoC Core Agent
// =============================================================================
`ifndef SOC_CORE_AGENT_SV
`define SOC_CORE_AGENT_SV

class soc_core_agent extends uvm_agent;
    soc_core_monitor mon;

    `uvm_component_utils(soc_core_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = soc_core_monitor::type_id::create("mon", this);
    endfunction
endclass

`endif
