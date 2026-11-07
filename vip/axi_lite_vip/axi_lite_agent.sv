// =============================================================================
// 32-bit AXI-Lite Agent
// =============================================================================
`ifndef AXI_LITE_AGENT_SV
`define AXI_LITE_AGENT_SV

class axi_lite_agent extends uvm_agent;
    axi_lite_driver    drv;
    axi_lite_monitor   mon;
    axi_lite_sequencer seqr;

    `uvm_component_utils(axi_lite_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi_lite_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = axi_lite_driver::type_id::create("drv", this);
            seqr = axi_lite_sequencer::type_id::create("seqr", this);
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
