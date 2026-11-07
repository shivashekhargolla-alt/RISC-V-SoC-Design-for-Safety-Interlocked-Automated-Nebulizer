class pwm_env extends uvm_env;
pwm_agent agent; pwm_scoreboard sb;
`uvm_component_utils(pwm_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=pwm_agent::type_id::create("agent",this); sb=pwm_scoreboard::type_id::create("sb",this); endfunction
endclass
