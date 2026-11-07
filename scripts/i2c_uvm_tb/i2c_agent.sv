class i2c_agent extends uvm_agent;
i2c_driver drv; i2c_monitor mon; i2c_sequencer seqr;
`uvm_component_utils(i2c_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=i2c_driver::type_id::create("drv",this); mon=i2c_monitor::type_id::create("mon",this); seqr=i2c_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
