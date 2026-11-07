// =============================================================================
// SoC Virtual Sequencer
// =============================================================================
`ifndef SOC_VIRTUAL_SEQUENCER_SV
`define SOC_VIRTUAL_SEQUENCER_SV

class soc_virtual_sequencer extends uvm_sequencer;
    uart_sequencer uart_seqr;
    gpio_sequencer gpio_seqr;
    pwm_sequencer  pwm_seqr;

    `uvm_component_utils(soc_virtual_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

`endif
