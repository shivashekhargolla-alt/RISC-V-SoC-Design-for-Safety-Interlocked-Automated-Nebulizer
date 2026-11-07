// =============================================================================
// GPIO Driver (Drives gpio_pin_i inputs to SoC)
// =============================================================================
`ifndef GPIO_DRIVER_SV
`define GPIO_DRIVER_SV

class gpio_driver extends uvm_driver #(gpio_item);
    virtual gpio_if vif;

    `uvm_component_utils(gpio_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gpio_if)::get(this, "", "gpio_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual gpio_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.gpio_pin_i <= 8'h00;
        @(posedge vif.rst_n);

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("GPIO_DRV", $sformatf("Driving gpio_pin_i = 0x%02h", req.pin_in), UVM_HIGH)
            vif.gpio_pin_i <= req.pin_in;
            @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass

`endif
