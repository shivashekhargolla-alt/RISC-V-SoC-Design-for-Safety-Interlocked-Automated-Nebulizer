// =============================================================================
// 32-bit AXI-Lite Driver
// =============================================================================
`ifndef AXI_LITE_DRIVER_SV
`define AXI_LITE_DRIVER_SV

class axi_lite_driver extends uvm_driver #(axi_lite_item);
    virtual axi_lite_if vif;

    `uvm_component_utils(axi_lite_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "axi_lite_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual axi_lite_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;

        @(posedge vif.rst_n);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.xfer_type == axi_lite_item::WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            seq_item_port.item_done();
        end
    endtask

    task drive_write(axi_lite_item item);
        @(posedge vif.clk);
        vif.awaddr  <= item.addr;
        vif.awprot  <= 3'b000;
        vif.awvalid <= 1'b1;
        vif.wdata   <= item.data;
        vif.wstrb   <= item.strb;
        vif.wvalid  <= 1'b1;

        fork
            begin
                while (!vif.awready) @(posedge vif.clk);
                @(posedge vif.clk);
                vif.awvalid <= 1'b0;
            end
            begin
                while (!vif.wready) @(posedge vif.clk);
                @(posedge vif.clk);
                vif.wvalid <= 1'b0;
            end
        join

        vif.bready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.bvalid) @(posedge vif.clk);
        item.resp = vif.bresp;
        @(posedge vif.clk);
        vif.bready <= 1'b0;
    endtask

    task drive_read(axi_lite_item item);
        @(posedge vif.clk);
        vif.araddr  <= item.addr;
        vif.arprot  <= 3'b000;
        vif.arvalid <= 1'b1;

        while (!vif.arready) @(posedge vif.clk);
        @(posedge vif.clk);
        vif.arvalid <= 1'b0;

        vif.rready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.rvalid) @(posedge vif.clk);
        item.data = vif.rdata;
        item.resp = vif.rresp;
        @(posedge vif.clk);
        vif.rready <= 1'b0;
    endtask
endclass

`endif
