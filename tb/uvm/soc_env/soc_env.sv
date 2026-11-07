// =============================================================================
// SoC UVM Environment
// =============================================================================
`ifndef SOC_ENV_SV
`define SOC_ENV_SV

class soc_env extends uvm_env;
    uart_agent             uart_ag;
    gpio_agent             gpio_ag;
    pwm_agent              pwm_ag;
    seg7_agent             seg7_ag;
    soc_core_agent         core_ag;
    soc_virtual_sequencer  v_seqr;
    soc_scoreboard         sb;

    `uvm_component_utils(soc_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        uart_ag = uart_agent::type_id::create("uart_ag", this);
        gpio_ag = gpio_agent::type_id::create("gpio_ag", this);
        pwm_ag  = pwm_agent::type_id::create("pwm_ag", this);
        seg7_ag = seg7_agent::type_id::create("seg7_ag", this);
        core_ag = soc_core_agent::type_id::create("core_ag", this);

        v_seqr  = soc_virtual_sequencer::type_id::create("v_seqr", this);
        sb      = soc_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect sequencers to virtual sequencer
        v_seqr.uart_seqr = uart_ag.seqr;
        v_seqr.gpio_seqr = gpio_ag.seqr;
        v_seqr.pwm_seqr  = pwm_ag.seqr;

        // Connect monitor analysis ports to scoreboard exports
        uart_ag.mon.ap.connect(sb.uart_export);
        gpio_ag.mon.ap.connect(sb.gpio_export);
        pwm_ag.mon.ap.connect(sb.pwm_export);
        seg7_ag.mon.ap.connect(sb.seg7_export);
        core_ag.mon.ap.connect(sb.core_export);
    endfunction
endclass

`endif
