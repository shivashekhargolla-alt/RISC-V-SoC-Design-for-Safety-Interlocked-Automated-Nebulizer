class seg7_env extends uvm_env;
seg7_agent agent; seg7_scoreboard sb;
`uvm_component_utils(seg7_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=seg7_agent::type_id::create("agent",this); sb=seg7_scoreboard::type_id::create("sb",this); endfunction
endclass
