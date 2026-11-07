// =============================================================================
// SoC Base Test
// =============================================================================
`ifndef SOC_BASE_TEST_SV
`define SOC_BASE_TEST_SV

class soc_base_test extends uvm_test;
    soc_env env;
    virtual soc_core_if core_vif;

    `uvm_component_utils(soc_base_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_env::type_id::create("env", this);
        if (!uvm_config_db #(virtual soc_core_if)::get(this, "", "core_vif", core_vif)) begin
            `uvm_fatal("NOVIF", "virtual soc_core_if not found in uvm_config_db")
        end
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    task run_phase(uvm_phase phase);
        // Default watchdog timer
        fork
            begin
                #100ms;
                `uvm_fatal("TIMEOUT", "Global simulation timeout reached!")
            end
        join_none
    endtask
endclass

`endif
