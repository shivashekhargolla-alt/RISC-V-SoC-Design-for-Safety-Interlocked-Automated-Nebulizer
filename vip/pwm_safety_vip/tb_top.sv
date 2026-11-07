module tb_top;
import uvm_pkg::*; import pwm_pkg::*;
pwm_if vif();
initial run_test("pwm_test");
endmodule
