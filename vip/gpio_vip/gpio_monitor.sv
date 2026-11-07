// =============================================================================
// GPIO Monitor (Monitors gpio_pin_o, gpio_pin_oe, gpio_irq_o)
// =============================================================================
`ifndef GPIO_MONITOR_SV
`define GPIO_MONITOR_SV

class gpio_monitor extends uvm_monitor;
    virtual gpio_if vif;
    uvm_analysis_port #(gpio_item) ap;

    `uvm_component_utils(gpio_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gpio_if)::get(this, "", "gpio_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual gpio_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        logic [7:0] prev_out;
        logic [7:0] prev_oe;
        logic       prev_irq;
        gpio_item   item;

        @(posedge vif.rst_n);
        prev_out = vif.gpio_pin_o;
        prev_oe  = vif.gpio_pin_oe;
        prev_irq = vif.gpio_irq_o;

        forever begin
            @(posedge vif.clk);
            if ((vif.gpio_pin_o !== prev_out) || (vif.gpio_pin_oe !== prev_oe) || (vif.gpio_irq_o !== prev_irq)) begin
                item = gpio_item::type_id::create("mon_gpio_item");
                item.pin_in   = vif.gpio_pin_i;
                item.pin_out  = vif.gpio_pin_o;
                item.pin_oe   = vif.gpio_pin_oe;
                item.gpio_irq = vif.gpio_irq_o;

                `uvm_info("GPIO_MON", $sformatf("GPIO state changed: pin_out=0x%02h, pin_oe=0x%02h, irq=%0b",
                          item.pin_out, item.pin_oe, item.gpio_irq), UVM_HIGH)
                ap.write(item);

                prev_out = vif.gpio_pin_o;
                prev_oe  = vif.gpio_pin_oe;
                prev_irq = vif.gpio_irq_o;
            end
        end
    endtask
endclass

`endif
