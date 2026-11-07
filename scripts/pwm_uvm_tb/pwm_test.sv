class pwm_test extends uvm_test;
pwm_env env;
`uvm_component_utils(pwm_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=pwm_env::type_id::create("env",this); endfunction
endclass
