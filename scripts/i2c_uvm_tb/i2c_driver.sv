class i2c_driver extends uvm_driver #(i2c_item);
virtual i2c_if vif;
`uvm_component_utils(i2c_driver)
function new(string n,uvm_component p);super.new(n,p);endfunction
task run_phase(uvm_phase phase); forever begin seq_item_port.get_next_item(req); @(posedge vif.clk); seq_item_port.item_done(); end endtask
endclass
