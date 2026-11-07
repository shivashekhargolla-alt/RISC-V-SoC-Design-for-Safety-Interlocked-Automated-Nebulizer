// =============================================================================
// 64-bit Full AXI4 Monitor
// =============================================================================
`ifndef AXI4_MONITOR_SV
`define AXI4_MONITOR_SV

class axi4_monitor extends uvm_monitor;
    virtual axi4_if vif;
    uvm_analysis_port #(axi4_item) ap;

    `uvm_component_utils(axi4_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "axi4_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual axi4_if not found in uvm_config_db")
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
        axi4_item item;
        int beats;

        forever begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.awready) begin
                item = axi4_item::type_id::create("mon_axi4_wr");
                item.xfer_type = axi4_item::WRITE;
                item.id        = vif.awid;
                item.addr      = vif.awaddr;
                item.len       = vif.awlen;
                item.size      = vif.awsize;
                item.burst     = vif.awburst;
                beats          = item.len + 1;
                item.data      = new[beats];
                item.strb      = new[beats];

                for (int b = 0; b < beats; b++) begin
                    while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);
                    item.data[b] = vif.wdata;
                    item.strb[b] = vif.wstrb;
                    @(posedge vif.clk);
                end

                while (!(vif.bvalid && vif.bready)) @(posedge vif.clk);
                item.resp = vif.bresp;

                `uvm_info("AXI4_MON", $sformatf("Observed AXI4 WRITE: addr=0x%08h, len=%0d, resp=%0d",
                          item.addr, item.len, item.resp), UVM_HIGH)
                ap.write(item);
            end
        end
    endtask

    task monitor_reads();
        axi4_item item;
        int beats;

        forever begin
            @(posedge vif.clk);
            if (vif.arvalid && vif.arready) begin
                item = axi4_item::type_id::create("mon_axi4_rd");
                item.xfer_type = axi4_item::READ;
                item.id        = vif.arid;
                item.addr      = vif.araddr;
                item.len       = vif.arlen;
                item.size      = vif.arsize;
                item.burst     = vif.arburst;
                beats          = item.len + 1;
                item.data      = new[beats];

                for (int b = 0; b < beats; b++) begin
                    while (!(vif.rvalid && vif.rready)) @(posedge vif.clk);
                    item.data[b] = vif.rdata;
                    item.resp    = vif.rresp;
                    @(posedge vif.clk);
                end

                `uvm_info("AXI4_MON", $sformatf("Observed AXI4 READ: addr=0x%08h, len=%0d, resp=%0d",
                          item.addr, item.len, item.resp), UVM_HIGH)
                ap.write(item);
            end
        end
    endtask
endclass

`endif
