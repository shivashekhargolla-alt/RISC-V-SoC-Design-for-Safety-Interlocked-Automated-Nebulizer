// =============================================================================
// 32-bit AXI-Lite Monitor
// =============================================================================
`ifndef AXI_LITE_MONITOR_SV
`define AXI_LITE_MONITOR_SV

class axi_lite_monitor extends uvm_monitor;
    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_lite_item) ap;

    `uvm_component_utils(axi_lite_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "axi_lite_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual axi_lite_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        @(posedge vif.rst_n);
        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    task monitor_writes();
        axi_lite_item item;
        forever begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.awready) begin
                item = axi_lite_item::type_id::create("mon_axi_lite_wr");
                item.xfer_type = axi_lite_item::WRITE;
                item.addr      = vif.awaddr;
                while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);
                item.data      = vif.wdata;
                item.strb      = vif.wstrb;
                while (!(vif.bvalid && vif.bready)) @(posedge vif.clk);
                item.resp      = vif.bresp;

                `uvm_info("AXI_LITE_MON", $sformatf("Observed AXI-Lite WRITE: addr=0x%08h data=0x%08h",
                          item.addr, item.data), UVM_HIGH)
                ap.write(item);
            end
        end
    endtask

    task monitor_reads();
        axi_lite_item item;
        forever begin
            @(posedge vif.clk);
            if (vif.arvalid && vif.arready) begin
                item = axi_lite_item::type_id::create("mon_axi_lite_rd");
                item.xfer_type = axi_lite_item::READ;
                item.addr      = vif.araddr;
                while (!(vif.rvalid && vif.rready)) @(posedge vif.clk);
                item.data      = vif.rdata;
                item.resp      = vif.rresp;

                `uvm_info("AXI_LITE_MON", $sformatf("Observed AXI-Lite READ: addr=0x%08h data=0x%08h",
                          item.addr, item.data), UVM_HIGH)
                ap.write(item);
            end
        end
    endtask
endclass

`endif
