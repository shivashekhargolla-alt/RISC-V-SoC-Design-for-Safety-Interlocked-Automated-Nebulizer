// =============================================================================
// SoC Core Monitor
// =============================================================================
`ifndef SOC_CORE_MONITOR_SV
`define SOC_CORE_MONITOR_SV

class soc_core_monitor extends uvm_monitor;
    virtual soc_core_if vif;
    uvm_analysis_port #(soc_core_item) ap;
    int commit_count = 0;

    `uvm_component_utils(soc_core_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual soc_core_if)::get(this, "", "core_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual soc_core_if not found in uvm_config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        logic [31:0] prev_marker = 32'h0;
        soc_core_item item;

        @(posedge vif.rst_n);

        fork
            // Monitor instruction commits
            forever begin
                @(posedge vif.clk);
                if (vif.trace_valid) begin
                    commit_count++;
                    if (commit_count % 5000 == 0) begin
                        `uvm_info("CORE_MON", $sformatf("Commits: %0d, Last PC: 0x%08h",
                                  commit_count, vif.trace_addr), UVM_HIGH)
                    end

                    if (vif.trace_except) begin
                        item = soc_core_item::type_id::create("core_except_item");
                        item.evt_type = soc_core_item::EXCEPT_EVT;
                        item.pc       = vif.trace_addr;
                        item.insn     = vif.trace_insn;
                        item.cause    = vif.trace_ecause;
                        `uvm_error("CORE_EXCEPT", $sformatf("Core Exception: cause=%0d, PC=0x%08h",
                                   item.cause, item.pc))
                        ap.write(item);
                    end
                end
            end

            // Monitor RAM completion marker changes
            forever begin
                @(posedge vif.clk);
                if (!$isunknown(vif.completion_marker) && (vif.completion_marker != prev_marker)) begin
                    item = soc_core_item::type_id::create("core_marker_item");
                    item.evt_type   = soc_core_item::MARKER_EVT;
                    item.marker_val = vif.completion_marker;
                    `uvm_info("CORE_MARKER", $sformatf("Milestone marker: 0x%08h", item.marker_val), UVM_LOW)
                    ap.write(item);
                    prev_marker = vif.completion_marker;
                end
            end
        join
    endtask
endclass

`endif
