module tb_top;
import uvm_pkg::*; import seg7_pkg::*;
seg7_if vif();
initial run_test("seg7_test");
endmodule
