class i2c_item extends uvm_sequence_item;

  rand bit scl_pad_i;
  bit scl_pad_o;
  bit scl_padoen_o;
  rand bit sda_pad_i;
  bit sda_pad_o;
  bit sda_padoen_o;

  `uvm_object_utils(i2c_item)

  function new(string name="i2c_item"); super.new(name); endfunction
endclass
