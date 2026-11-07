class seg7_test extends uvm_test;
seg7_env env;
`uvm_component_utils(seg7_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=seg7_env::type_id::create("env",this); endfunction
endclass
