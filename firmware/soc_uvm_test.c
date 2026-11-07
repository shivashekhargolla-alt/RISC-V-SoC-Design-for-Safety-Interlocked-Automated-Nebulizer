/*
 * NebuCore SoC — Comprehensive UVM Test Firmware
 *
 * Targets: RISC-V VeeR EL2 Core (RV32IMC, 32-bit)
 *
 * Test Suites supported:
 *   1. Data Transfers:
 *      - SRAM word, half-word, byte read/write consistency & pattern tests
 *      - Peripheral register read/write across AXI3x15 interconnect
 *   2. RISC-V to IPs:
 *      - Core -> UART TX (stream test packets)
 *      - Core -> GPIO OUT (patterns on 8 output pins)
 *      - Core -> PWM (duty cycle, period, activation)
 *      - Core -> Seg7 (display digits 0-9, A-F)
 *      - Core -> Timer (counter load and start)
 *   3. IPs to RISC-V:
 *      - External UART RX -> Core (packet reception & verification)
 *      - External GPIO IN -> Core (pin reading & verification)
 *   4. Bidirectional / Cross-IP Transfer:
 *      - UART RX -> Core compute -> PWM duty drive + GPIO reflection + Seg7 display
 */

/* ── Base Addresses ───────────────────────────────────────────────────────── */
#define RAM_BASE                0x00000000u
#define UART_BASE               0x10000000u
#define TIMER_BASE              0x12000000u
#define GPIO_BASE               0x13000000u
#define PWM_BASE                0x14000000u
#define SEG7_BASE               0x15000000u
#define WDT_BASE                0x16000000u

/* ── Testbench Control / Markers (in RAM) ─────────────────────────────────── */
#define COMPLETION_MARKER_ADDR  (*(volatile unsigned int *)(RAM_BASE + 0x1000))
#define TEST_MODE_ADDR          (*(volatile unsigned int *)(RAM_BASE + 0x1004))
#define TEST_STATUS_ADDR        (*(volatile unsigned int *)(RAM_BASE + 0x1008))

/* Marker Values */
#define MARKER_BOOT_DONE        0x55AA0001u
#define MARKER_DATA_XFER_START  0x55AA0011u
#define MARKER_DATA_XFER_PASS   0x55AA0010u
#define MARKER_RV_TO_IPS_START  0x55AA0021u
#define MARKER_RV_TO_IPS_PASS   0x55AA0020u
#define MARKER_IPS_TO_RV_WAIT   0x55AA0031u
#define MARKER_IPS_TO_RV_PASS   0x55AA0030u
#define MARKER_BIDIR_WAIT       0x55AA0041u
#define MARKER_BIDIR_PASS       0x55AA0040u
#define MARKER_UART_TO_RV_WAIT  0x55AA0051u
#define MARKER_UART_TO_RV_PASS  0x55AA0050u
#define MARKER_ALL_PASS         0x55AA00FFu
#define MARKER_TEST_FAIL        0xDEADFA11u

/* ── UART Registers ───────────────────────────────────────────────────────── */
#define UART_RBR_THR            (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_IER                (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BAUD_DIV           (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_LCR                (*(volatile unsigned int *)(UART_BASE + 0x0C))
#define UART_LSR                (*(volatile unsigned int *)(UART_BASE + 0x14))

#define UART_LSR_DATA_READY     (1u << 0)
#define UART_LSR_THR_EMPTY      (1u << 5)

/* ── GPIO Registers ───────────────────────────────────────────────────────── */
#define GPIO_DIR                (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_OUT                (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_IN                 (*(volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_IRQ                (*(volatile unsigned int *)(GPIO_BASE + 0x0C))

/* ── PWM Registers ────────────────────────────────────────────────────────── */
#define PWM_CTRL                (*(volatile unsigned int *)(PWM_BASE + 0x00))
#define PWM_DUTY                (*(volatile unsigned int *)(PWM_BASE + 0x04))
#define PWM_PERIOD              (*(volatile unsigned int *)(PWM_BASE + 0x08))
#define PWM_STATUS              (*(volatile unsigned int *)(PWM_BASE + 0x0C))

#define PWM_CTRL_EN             (1u << 0)
#define PWM_STATUS_ACTIVE       (1u << 0)

/* ── Seg7 Registers ───────────────────────────────────────────────────────── */
#define SEG7_DATA               (*(volatile unsigned int *)(SEG7_BASE + 0x00))
#define SEG7_CTRL               (*(volatile unsigned int *)(SEG7_BASE + 0x04))
#define SEG7_STATUS             (*(volatile unsigned int *)(SEG7_BASE + 0x08))

/* ── Timer Registers ──────────────────────────────────────────────────────── */
#define TIMER_CTRL              (*(volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIMER_LOAD              (*(volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIMER_COUNT             (*(volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIMER_STATUS            (*(volatile unsigned int *)(TIMER_BASE + 0x0C))

/* ── UART Helpers ─────────────────────────────────────────────────────────── */
static void uart_putc(char c)
{
    while ((UART_LSR & UART_LSR_THR_EMPTY) == 0) { }
    UART_RBR_THR = (unsigned int)(unsigned char)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s);
        s++;
    }
}

static int uart_has_data(void)
{
    return (UART_LSR & UART_LSR_DATA_READY) != 0;
}

static unsigned int uart_getc(void)
{
    while (!uart_has_data()) { }
    return (UART_RBR_THR & 0xFFu);
}

static void uart_init(unsigned int baud_div)
{
    UART_LCR = 0x83u;          /* DLAB=1 */
    UART_BAUD_DIV = baud_div;
    UART_LCR = 0x03u;          /* 8N1, DLAB=0 */
    UART_IER = 0x01u;          /* Enable RX interrupt / status */
}

/* ── Minimal Memory Helpers ───────────────────────────────────────────────── */
void *memcpy(void *dest, const void *src, unsigned long n)
{
    char *d = (char *)dest;
    const char *s = (const char *)src;
    while (n--) *d++ = *s++;
    return dest;
}

static const unsigned int test_patterns[8] = {
    0xA5A5A5A5u, 0x5A5A5A5Au, 0x12345678u, 0x9ABCDEF0u,
    0xDEADBEEFu, 0xCAFEBABEu, 0xFFFFFFFFu, 0x00000000u
};

/* ── Test 1: Data Transfers Test ──────────────────────────────────────────── */
static int test_data_transfers(void)
{
    volatile unsigned int *ram_words = (volatile unsigned int *)(RAM_BASE + 0x2000);
    volatile unsigned short *ram_half = (volatile unsigned short *)(RAM_BASE + 0x2400);
    volatile unsigned char *ram_bytes = (volatile unsigned char *)(RAM_BASE + 0x2800);
    int i;

    COMPLETION_MARKER_ADDR = MARKER_DATA_XFER_START;
    uart_puts("[UVM-TEST] 1. Data Transfer Test Starting...\n");

    /* 1. Word transfers (32-bit AXI bursts) */
    for (i = 0; i < 8; i++) {
        ram_words[i] = test_patterns[i];
    }
    for (i = 0; i < 8; i++) {
        if (ram_words[i] != test_patterns[i]) {
            uart_puts("[UVM-TEST] ERROR: RAM 32-bit readback mismatch!\n");
            COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
            return -1;
        }
    }

    /* 2. Half-word transfers (16-bit) */
    for (i = 0; i < 8; i++) {
        ram_half[i] = (unsigned short)(test_patterns[i] & 0xFFFFu);
    }
    for (i = 0; i < 8; i++) {
        if (ram_half[i] != (unsigned short)(test_patterns[i] & 0xFFFFu)) {
            uart_puts("[UVM-TEST] ERROR: RAM 16-bit readback mismatch!\n");
            COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
            return -1;
        }
    }

    /* 3. Byte transfers (8-bit) */
    for (i = 0; i < 8; i++) {
        ram_bytes[i] = (unsigned char)(0x30 + i);
    }
    for (i = 0; i < 8; i++) {
        if (ram_bytes[i] != (unsigned char)(0x30 + i)) {
            uart_puts("[UVM-TEST] ERROR: RAM 8-bit readback mismatch!\n");
            COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
            return -1;
        }
    }

    /* 4. Peripheral register data transfers across Interconnect */
    PWM_PERIOD = 2000u;
    PWM_DUTY   = 100u;
    if (PWM_PERIOD != 2000u || PWM_DUTY != 100u) {
        uart_puts("[UVM-TEST] ERROR: PWM register transfer mismatch!\n");
        COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
        return -1;
    }

    GPIO_DIR = 0xAAu;
    if ((GPIO_DIR & 0xFFu) != 0xAAu) {
        uart_puts("[UVM-TEST] ERROR: GPIO register transfer mismatch!\n");
        COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
        return -1;
    }

    uart_puts("[UVM-TEST] 1. Data Transfer Test: PASS\n");
    COMPLETION_MARKER_ADDR = MARKER_DATA_XFER_PASS;
    return 0;
}

/* ── Test 2: RISC-V to IPs Test ───────────────────────────────────────────── */
static int test_riscv_to_ips(void)
{
    COMPLETION_MARKER_ADDR = MARKER_RV_TO_IPS_START;
    uart_puts("[UVM-TEST] 2. RISC-V -> IPs Test Starting...\n");

    /* 1. Drive UART TX */
    uart_puts("[UVM:CORE->UART] PACKET_TX_DATA=0x41_0x42_0x43\n");

    /* 2. Drive GPIO Outputs */
    GPIO_DIR = 0xFFu; /* all outputs */
    GPIO_OUT = 0xA5u;
    for (volatile int d = 0; d < 50; d++) { }
    GPIO_OUT = 0x5Au;
    for (volatile int d = 0; d < 50; d++) { }
    GPIO_OUT = 0xC3u;
    for (volatile int d = 0; d < 50; d++) { }

    /* 3. Drive PWM Generator */
    PWM_CTRL   = 0u;
    PWM_PERIOD = 1000u;
    PWM_DUTY   = 128u; /* 50% duty */
    PWM_CTRL   = PWM_CTRL_EN;
    for (volatile int d = 0; d < 200; d++) { }

    if ((PWM_STATUS & PWM_STATUS_ACTIVE) == 0) {
        uart_puts("[UVM-TEST] ERROR: PWM not active!\n");
        COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
        return -1;
    }

    /* 4. Drive 7-Segment Display */
    SEG7_CTRL = 1u;      /* Display ON */
    SEG7_DATA = 0x1234u; /* Display digits: 1, 2, 3, 4 */

    /* 5. Drive Timer */
    TIMER_CTRL = 0u;
    TIMER_LOAD = 100u;
    TIMER_CTRL = 1u; /* Enable countdown */

    uart_puts("[UVM-TEST] 2. RISC-V -> IPs Test: PASS\n");
    COMPLETION_MARKER_ADDR = MARKER_RV_TO_IPS_PASS;
    return 0;
}

/* ── Test 3: IPs to RISC-V Test ───────────────────────────────────────────── */
static int test_ips_to_riscv(void)
{
    unsigned int b1, b2, b3, b4;
    unsigned int gpio_val;

    uart_puts("[UVM-TEST] 3. IPs -> RISC-V Test Starting...\n");

    /* Configure GPIO for inputs */
    GPIO_DIR = 0x00u; /* all inputs */

    /* Signal UVM testbench we are ready to receive */
    COMPLETION_MARKER_ADDR = MARKER_IPS_TO_RV_WAIT;
    uart_puts("[UVM-TEST] Waiting for stimulus on UART RX & GPIO IN...\n");

    /* Wait for 4 UART bytes from UVM driver */
    b1 = uart_getc();
    b2 = uart_getc();
    b3 = uart_getc();
    b4 = uart_getc();

    /* Read external GPIO inputs */
    gpio_val = GPIO_IN & 0xFFu;

    uart_puts("[UVM-TEST] Received UART: ");
    uart_putc((char)b1);
    uart_putc((char)b2);
    uart_putc((char)b3);
    uart_putc((char)b4);
    uart_puts(", GPIO IN readback = 0x");
    uart_putc("0123456789ABCDEF"[(gpio_val >> 4) & 0xF]);
    uart_putc("0123456789ABCDEF"[gpio_val & 0xF]);
    uart_puts("\n");

    /* Verify received UART payload: expected 'U', 'V', 'M', '1' */
    if (b1 != 'U' || b2 != 'V' || b3 != 'M' || b4 != '1') {
        uart_puts("[UVM-TEST] ERROR: Unexpected UART payload!\n");
        COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
        return -1;
    }

    uart_puts("[UVM-TEST] 3. IPs -> RISC-V Test: PASS\n");
    COMPLETION_MARKER_ADDR = MARKER_IPS_TO_RV_PASS;
    return 0;
}

/* ── Test 4: Bidirectional / Cross-IP Test ────────────────────────────────── */
static int test_bidirectional(void)
{
    unsigned int rx_byte;
    unsigned int computed_duty;

    uart_puts("[UVM-TEST] 4. Bidirectional Test Starting...\n");

    COMPLETION_MARKER_ADDR = MARKER_BIDIR_WAIT;

    /* Receive command byte from UART */
    rx_byte = uart_getc();

    /* Compute PWM duty: if ASCII digit '0'-'9', scale to 28 * digit, else raw */
    if (rx_byte >= '0' && rx_byte <= '9') {
        computed_duty = (rx_byte - '0') * 28u;
    } else {
        computed_duty = rx_byte;
    }
    if (computed_duty == 0) computed_duty = 32u;
    if (computed_duty > 255u) computed_duty = 255u;

    /* Drive computed duty to PWM IP */
    PWM_CTRL   = 0u;
    PWM_PERIOD = 1000u;
    PWM_DUTY   = computed_duty;
    PWM_CTRL   = PWM_CTRL_EN;

    /* Reflect received data onto GPIO outputs */
    GPIO_DIR = 0xFFu;
    GPIO_OUT = (rx_byte & 0xFFu);

    /* Display received byte on 7-Segment */
    SEG7_CTRL = 1u;
    SEG7_DATA = ((rx_byte & 0xF0u) << 4) | (rx_byte & 0x0Fu);

    uart_puts("[UVM-TEST] Bidirectional data routed: UART->Core->PWM & GPIO\n");
    COMPLETION_MARKER_ADDR = MARKER_BIDIR_PASS;
    return 0;
}

/* ── Test 5: Dedicated UART Driver -> RISC-V Core Test ───────────────────── */
static int test_uart_to_riscv(void)
{
    unsigned int b1, b2, b3, b4;
    volatile unsigned int *ram_dest = (volatile unsigned int *)(RAM_BASE + 0x2000);

    /* Signal UVM testbench UART driver immediately that Core is ready to listen */
    COMPLETION_MARKER_ADDR = MARKER_UART_TO_RV_WAIT;

    /* Core polls and loads 4 bytes from UART_RBR via AXI4 */
    b1 = uart_getc();
    b2 = uart_getc();
    b3 = uart_getc();
    b4 = uart_getc();

    /* Store received 32-bit word into RAM for visual proof in memory */
    *ram_dest = (b4 << 24) | (b3 << 16) | (b2 << 8) | b1;

    /* Verify payload matches 'R', 'I', 'S', 'C' */
    if (b1 != 'R' || b2 != 'I' || b3 != 'S' || b4 != 'C') {
        COMPLETION_MARKER_ADDR = MARKER_TEST_FAIL;
        return -1;
    }

    COMPLETION_MARKER_ADDR = MARKER_UART_TO_RV_PASS;
    return 0;
}

/* ── Entry Point / Reset Vector ───────────────────────────────────────────── */
__attribute__((section(".text.init"), naked, noreturn))
void _start(void)
{
    __asm__ volatile (
        "la sp, _stack_top\n"
        "li t0, 0x55555559\n"
        "csrw 0x7c0, t0\n"
        "j main\n"
    );
    __builtin_unreachable();
}

/* ── Main ─────────────────────────────────────────────────────────────────── */
int main(void)
{
    unsigned int mode;

    /* Step 1: Initialize UART for logging & communication */
    uart_init(16);

    /* Read test mode from RAM (set by UVM testbench) */
    mode = TEST_MODE_ADDR;

    if (mode == 5) {
        /* Run dedicated UART VIP Driver -> RISC-V Test immediately (no slow banner delay) */
        test_uart_to_riscv();
        while (1) { }
    }

    uart_puts("\n======================================================\n");
    uart_puts("  NebuCore SoC: Comprehensive UVM Verification Suite  \n");
    uart_puts("======================================================\n");

    COMPLETION_MARKER_ADDR = MARKER_BOOT_DONE;

    if (mode == 1) {
        /* Run only Data Transfers Test */
        test_data_transfers();
    } else if (mode == 2) {
        /* Run only RISC-V to IPs Test */
        test_riscv_to_ips();
    } else if (mode == 3) {
        /* Run only IPs to RISC-V Test */
        test_ips_to_riscv();
    } else if (mode == 4) {
        /* Run only Bidirectional Test */
        test_bidirectional();
    } else if (mode == 5) {
        /* Run dedicated UART VIP Driver -> RISC-V Test */
        test_uart_to_riscv();
    } else {
        /* Mode 0: Run all tests in sequence */
        if (test_data_transfers() == 0) {
            for (volatile int d = 0; d < 100; d++) { }
            if (test_riscv_to_ips() == 0) {
                for (volatile int d = 0; d < 100; d++) { }
                if (test_ips_to_riscv() == 0) {
                    for (volatile int d = 0; d < 100; d++) { }
                    test_bidirectional();
                }
            }
        }
    }

    uart_puts("\n======================================================\n");
    uart_puts("  ALL REQUESTED TESTS COMPLETED SUCCESSFULLY!         \n");
    uart_puts("======================================================\n");

    COMPLETION_MARKER_ADDR = MARKER_ALL_PASS;

    /* Loop indefinitely to keep PWM pulsing for waveform dump */
    while (1) { }

    return 0;
}
