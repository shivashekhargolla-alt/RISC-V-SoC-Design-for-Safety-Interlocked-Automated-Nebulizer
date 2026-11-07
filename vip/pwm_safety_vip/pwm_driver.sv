// =============================================================================
// PWM Driver (Drives pwm_force_disable_i)
// =============================================================================
`ifndef PWM_DRIVER_SV
`define PWM_DRIVER_SV

class pwm_driver extends uvm_driver #(pwm_item);
    virtual pwm_if vif;

    `uvm_component_utils(pwm_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual pwm_if)::get(this, "", "pwm_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual pwm_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.pwm_force_disable_i <= 1'b0;
        @(posedge vif.rst_n);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("PWM_DRV", $sformatf("Driving pwm_force_disable_i = %0b", req.force_disable), UVM_HIGH)
            vif.pwm_force_disable_i <= req.force_disable;
            @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass

`endif
