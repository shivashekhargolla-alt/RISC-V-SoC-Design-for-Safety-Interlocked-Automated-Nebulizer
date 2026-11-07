// =============================================================================
// Top-Level Virtual Sequencer for NebuCore SoC
// =============================================================================
`ifndef SOC_VIRTUAL_SEQUENCER_SV
`define SOC_VIRTUAL_SEQUENCER_SV

class soc_virtual_sequencer extends uvm_sequencer;
    uart_sequencer     uart_seqr;
    gpio_sequencer     gpio_seqr;
    pwm_sequencer      pwm_seqr;
    axi4_sequencer     axi4_seqr;
    axi_lite_sequencer axi_lite_seqr;

    `uvm_component_utils(soc_virtual_sequencer)

    function new(string name = "soc_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

`endif
