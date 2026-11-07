// =============================================================================
// 64-bit Full AXI4 Master Driver
// =============================================================================
`ifndef AXI4_DRIVER_SV
`define AXI4_DRIVER_SV

class axi4_driver extends uvm_driver #(axi4_item);
    virtual axi4_if vif;

    `uvm_component_utils(axi4_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "axi4_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual axi4_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        // Default bus signals
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.wlast   <= 1'b0;
        vif.bready  <= 1'b0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;

        @(posedge vif.rst_n);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.xfer_type == axi4_item::WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            seq_item_port.item_done();
        end
    endtask

    task drive_write(axi4_item item);
        int total_beats = item.len + 1;

        // Drive Address Write Channel
        @(posedge vif.clk);
        vif.awid    <= item.id;
        vif.awaddr  <= item.addr;
        vif.awlen   <= item.len;
        vif.awsize  <= item.size;
        vif.awburst <= item.burst;
        vif.awvalid <= 1'b1;

        fork
            begin
                while (!vif.awready) @(posedge vif.clk);
                @(posedge vif.clk);
                vif.awvalid <= 1'b0;
            end
            begin
                // Drive Write Data Channel
                for (int b = 0; b < total_beats; b++) begin
                    vif.wdata  <= item.data[b];
                    vif.wstrb  <= (item.strb.size() > b) ? item.strb[b] : 8'hFF;
                    vif.wlast  <= (b == total_beats - 1);
                    vif.wvalid <= 1'b1;
                    @(posedge vif.clk);
                    while (!vif.wready) @(posedge vif.clk);
                end
                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
            end
        join

        // Wait for B response
        vif.bready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.bvalid) @(posedge vif.clk);
        item.resp = vif.bresp;
        @(posedge vif.clk);
        vif.bready <= 1'b0;
    endtask

    task drive_read(axi4_item item);
        int total_beats = item.len + 1;
        item.data = new[total_beats];

        // Drive Read Address Channel
        @(posedge vif.clk);
        vif.arid    <= item.id;
        vif.araddr  <= item.addr;
        vif.arlen   <= item.len;
        vif.arsize  <= item.size;
        vif.arburst <= item.burst;
        vif.arvalid <= 1'b1;

        while (!vif.arready) @(posedge vif.clk);
        @(posedge vif.clk);
        vif.arvalid <= 1'b0;

        // Receive Read Data Channel
        vif.rready <= 1'b1;
        for (int b = 0; b < total_beats; b++) begin
            @(posedge vif.clk);
            while (!vif.rvalid) @(posedge vif.clk);
            item.data[b] = vif.rdata;
            item.resp    = vif.rresp;
        end
        vif.rready <= 1'b0;
    endtask
endclass

`endif
