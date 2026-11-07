// =============================================================================
// Seven-Segment Display Monitor (Decodes 7-segment patterns into hex values)
// =============================================================================
`ifndef SEG7_MONITOR_SV
`define SEG7_MONITOR_SV

class seg7_monitor extends uvm_monitor;
    virtual seg7_if vif;
    uvm_analysis_port #(seg7_item) ap;

    `uvm_component_utils(seg7_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual seg7_if)::get(this, "", "seg7_vif", vif)) begin
            `uvm_fatal("NOVIF", "virtual seg7_if not found in uvm_config_db")
        end
    endfunction

    function bit [3:0] decode_segments(bit [6:0] seg);
        case (seg)
            7'b0111111: return 4'h0;
            7'b0000110: return 4'h1;
            7'b1011011: return 4'h2;
            7'b1001111: return 4'h3;
            7'b1100110: return 4'h4;
            7'b1101101: return 4'h5;
            7'b1111101: return 4'h6;
            7'b0000111: return 4'h7;
            7'b1111111: return 4'h8;
            7'b1101111: return 4'h9;
            7'b1110111: return 4'hA;
            7'b1111100: return 4'hB;
            7'b0111001: return 4'hC;
            7'b1011110: return 4'hD;
            7'b1111001: return 4'hE;
            7'b1110001: return 4'hF;
            default:    return 4'h0;
        endcase
    endfunction

    task run_phase(uvm_phase phase);
        logic [6:0] prev_seg;
        logic [3:0] prev_sel;
        seg7_item   item;

        @(posedge vif.rst_n);
        prev_seg = vif.seg_out_o;
        prev_sel = vif.digit_sel_o;

        forever begin
            @(posedge vif.clk);
            if ((vif.seg_out_o !== prev_seg) || (vif.digit_sel_o !== prev_sel)) begin
                item = seg7_item::type_id::create("mon_seg7_item");
                item.seg_pattern = vif.seg_out_o;
                item.digit_sel   = vif.digit_sel_o;
                item.decoded_val = decode_segments(vif.seg_out_o);

                case (vif.digit_sel_o)
                    4'b0001: item.digit_idx = 0;
                    4'b0010: item.digit_idx = 1;
                    4'b0100: item.digit_idx = 2;
                    4'b1000: item.digit_idx = 3;
                    default: item.digit_idx = -1;
                endcase

                `uvm_info("SEG7_MON", $sformatf("Digit %0d: pattern=7'b%07b, decoded=0x%01h",
                          item.digit_idx, item.seg_pattern, item.decoded_val), UVM_HIGH)
                ap.write(item);

                prev_seg = vif.seg_out_o;
                prev_sel = vif.digit_sel_o;
            end
        end
    endtask
endclass

`endif
