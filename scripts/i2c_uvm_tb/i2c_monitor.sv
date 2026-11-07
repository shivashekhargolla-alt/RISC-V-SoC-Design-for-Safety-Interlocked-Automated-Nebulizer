class i2c_monitor extends uvm_monitor;
virtual i2c_if vif;
uvm_analysis_port #(i2c_item) ap;
`uvm_component_utils(i2c_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
