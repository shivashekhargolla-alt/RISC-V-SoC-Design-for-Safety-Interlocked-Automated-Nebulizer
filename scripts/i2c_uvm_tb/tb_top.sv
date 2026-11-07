module tb_top;
import uvm_pkg::*; import i2c_pkg::*;
i2c_if vif();
initial run_test("i2c_test");
endmodule
