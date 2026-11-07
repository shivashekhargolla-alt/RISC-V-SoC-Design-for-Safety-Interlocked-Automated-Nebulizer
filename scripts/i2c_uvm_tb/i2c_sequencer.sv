class i2c_sequencer extends uvm_sequencer #(i2c_item);
`uvm_component_utils(i2c_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
