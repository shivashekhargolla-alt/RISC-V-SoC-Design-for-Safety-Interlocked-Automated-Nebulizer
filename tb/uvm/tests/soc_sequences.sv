// =============================================================================
// SoC UVM Sequences
// =============================================================================
`ifndef SOC_SEQUENCES_SV
`define SOC_SEQUENCES_SV

// ── UART send single byte sequence ───────────────────────────────────────────
class uart_send_byte_seq extends uvm_sequence #(uart_item);
    rand bit [7:0] byte_val;
    rand int       baud_div;

    `uvm_object_utils(uart_send_byte_seq)

    function new(string name = "uart_send_byte_seq");
        super.new(name);
        baud_div = 16;
    endfunction

    task body();
        `uvm_create(req)
        req.data_byte = byte_val;
        req.baud_div  = baud_div;
        req.is_tx     = 1'b0;
        `uvm_send(req)
    endtask
endclass

// ── UART send string packet sequence ─────────────────────────────────────────
class uart_send_packet_seq extends uvm_sequence #(uart_item);
    string payload = "UVM1";
    int    baud_div = 16;

    `uvm_object_utils(uart_send_packet_seq)

    function new(string name = "uart_send_packet_seq");
        super.new(name);
    endfunction

    task body();
        for (int i = 0; i < payload.len(); i++) begin
            `uvm_create(req)
            req.data_byte = payload[i];
            req.baud_div  = baud_div;
            req.is_tx     = 1'b0;
            `uvm_send(req)
        end
    endtask
endclass

// ── GPIO drive pattern sequence ──────────────────────────────────────────────
class gpio_drive_seq extends uvm_sequence #(gpio_item);
    rand bit [7:0] pattern;

    `uvm_object_utils(gpio_drive_seq)

    function new(string name = "gpio_drive_seq");
        super.new(name);
    endfunction

    task body();
        `uvm_create(req)
        req.pin_in = pattern;
        `uvm_send(req)
    endtask
endclass

// ── PWM force disable sequence ───────────────────────────────────────────────
class pwm_force_disable_seq extends uvm_sequence #(pwm_item);
    rand bit disable_val;

    `uvm_object_utils(pwm_force_disable_seq)

    function new(string name = "pwm_force_disable_seq");
        super.new(name);
    endfunction

    task body();
        `uvm_create(req)
        req.force_disable = disable_val;
        `uvm_send(req)
    endtask
endclass

`endif
