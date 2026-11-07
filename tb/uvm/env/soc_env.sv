// =============================================================================
// Top-Level SoC UVM Environment
// =============================================================================
`ifndef SOC_ENV_SV
`define SOC_ENV_SV

class soc_env extends uvm_env;
    uart_agent             uart_ag;
    gpio_agent             gpio_ag;
    pwm_agent              pwm_ag;
    seg7_agent             seg7_ag;
    soc_core_agent         core_ag;
    axi4_agent             axi4_ag;
    axi_lite_agent         axi_lite_ag;
    soc_virtual_sequencer  v_seqr;
    soc_scoreboard         sb;
    soc_coverage           cov;

    `uvm_component_utils(soc_env)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        uart_ag     = uart_agent::type_id::create("uart_ag", this);
        gpio_ag     = gpio_agent::type_id::create("gpio_ag", this);
        pwm_ag      = pwm_agent::type_id::create("pwm_ag", this);
        seg7_ag     = seg7_agent::type_id::create("seg7_ag", this);
        core_ag     = soc_core_agent::type_id::create("core_ag", this);
        axi4_ag     = axi4_agent::type_id::create("axi4_ag", this);
        axi_lite_ag = axi_lite_agent::type_id::create("axi_lite_ag", this);

        v_seqr      = soc_virtual_sequencer::type_id::create("v_seqr", this);
        sb          = soc_scoreboard::type_id::create("sb", this);
        cov         = soc_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect sequencers to virtual sequencer
        v_seqr.uart_seqr     = uart_ag.seqr;
        v_seqr.gpio_seqr     = gpio_ag.seqr;
        v_seqr.pwm_seqr      = pwm_ag.seqr;
        v_seqr.axi4_seqr     = axi4_ag.seqr;
        v_seqr.axi_lite_seqr = axi_lite_ag.seqr;

        // Connect monitor analysis ports to scoreboard exports
        uart_ag.mon.ap.connect(sb.uart_export);
        gpio_ag.mon.ap.connect(sb.gpio_export);
        pwm_ag.mon.ap.connect(sb.pwm_export);
        seg7_ag.mon.ap.connect(sb.seg7_export);
        core_ag.mon.ap.connect(sb.core_export);
        axi4_ag.mon.ap.connect(sb.axi4_export);

        // Connect core monitor to coverage collector
        core_ag.mon.ap.connect(cov.analysis_export);
    endfunction
endclass

`endif
