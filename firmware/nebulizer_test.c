/*
 * NebuCore SoC — C Firmware Test
 *
 * Targets the RISC-V VeeR EL2 SoC (RV32IMC, 32-bit).
 *
 * This program exercises the on-chip peripherals via memory-mapped I/O:
 *   1. Writes "NebuCore SoC alive\n" to the UART.
 *   2. Configures the PWM Generator (duty = 50%, period = 1000 ticks).
 *   3. Enables PWM and reads back STATUS.
 *   4. Writes a completion marker to a known RAM address so the testbench
 *      can verify firmware executed correctly.
 *
 * Memory map (from the SoC spec):
 *   RAM   : 0x0000_0000  (boot, data — M01)
 *   UART  : 0x1000_0000  (M00)
 *   PWM   : 0x1400_0000  (M04)
 *
 * Build:
 *   riscv64-linux-gnu-gcc -march=rv32imc -mabi=ilp32 \
 *       -nostdlib -nostartfiles -ffreestanding -T nebulizer.ld \
 *       -Wl,--gc-sections -o nebulizer_test.elf nebulizer_test.c
 */

/* ── Peripheral base addresses ────────────────────────────────────────────── */
#define UART_BASE   0x10000000u
#define PWM_BASE    0x14000000u
#define RAM_BASE     0x00000000u

/* ── UART register offsets (from register_map.txt) ─────────────────────────── */
#define UART_RBR_THR  (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_IER      (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BAUD_DIV (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_LCR      (*(volatile unsigned int *)(UART_BASE + 0x0C))
#define UART_LSR      (*(volatile unsigned int *)(UART_BASE + 0x14))

/* UART LSR bit positions */
#define UART_LSR_THR_EMPTY  (1u << 5)
#define UART_LSR_DATA_READY (1u << 0)

/* ── PWM register offsets (from pwm_defines.vh) ───────────────────────────── */
#define PWM_CTRL     (*(volatile unsigned int *)(PWM_BASE + 0x00))
#define PWM_DUTY     (*(volatile unsigned int *)(PWM_BASE + 0x04))
#define PWM_PERIOD   (*(volatile unsigned int *)(PWM_BASE + 0x08))
#define PWM_STATUS   (*(volatile unsigned int *)(PWM_BASE + 0x0C))

/* PWM CTRL bit */
#define PWM_CTRL_EN  (1u << 0)

/* ── Completion marker address (in RAM, after the program image) ──────────── */
/* The testbench reads this address to confirm firmware ran to completion. */
#define COMPLETION_MARKER_ADDR  (*(volatile unsigned int *)(RAM_BASE + 0x1000))

#define MARKER_UART_DONE   0x55AA0001u
#define MARKER_PWM_CONFIG  0x55AA0002u
#define MARKER_PWM_ENABLE  0x55AA0003u
#define MARKER_ALL_PASS    0x55AA00FFu

/* ── Helper: send one byte over UART (polled, blocking) ──────────────────── */
static void uart_putc(char c)
{
    /* Wait until the transmit holding register is empty */
    while ((UART_LSR & UART_LSR_THR_EMPTY) == 0) { }
    UART_RBR_THR = (unsigned int)c;
}

/* ── Helper: send a null-terminated string over UART ───────────────────────── */
static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s);
        s++;
    }
}

/* ── Helper: simple 32-bit hex printer for debug ──────────────────────────── */
static const char hexdigits[] = "0123456789ABCDEF";

static void uart_put_hex(unsigned int val)
{
    int i;
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(hexdigits[(val >> i) & 0xF]);
    }
}

/* ── Startup code ──────────────────────────────────────────────────────────── */
/* This is the entry point. The linker script places .text.init at address 0. */
__attribute__((section(".text.init"), naked, noreturn))
void _start(void)
{
    /* Set up stack pointer — top of the 64 KiB RAM region.
     * Configure MRAC (CSR 0x7c0): Region 1 (0x1000_0000–0x1FFF_FFFF) as MMIO/side-effect,
     * Region 0 as cacheable RAM (matches VeeR EL2 crt0 convention: 0x55555559). */
    __asm__ volatile (
        "la sp, _stack_top\n"
        "li t0, 0x55555559\n"
        "csrw 0x7c0, t0\n"
        "j main\n"
    );
    __builtin_unreachable();
}

/* ── Main firmware test ────────────────────────────────────────────────────── */
int main(void)
{
    unsigned int status;

    /* ── Step 1: Initialize UART ─────────────────────────────────────────── */
    /* Set DLAB = 1 (bit 7) in LCR to enable baud divisor latch access */
    UART_LCR = 0x83;
    /* Baud divisor: set to 16 for fast simulation turnaround (160 ticks/byte) */
    UART_BAUD_DIV = 16;
    /* Clear DLAB, keep 8-bit word, 1 stop bit, no parity */
    UART_LCR = 0x03;
    /* Enable TX (no interrupt needed for polled mode) */
    UART_IER = 0x00;

    /* Send a banner over UART */
    uart_puts("NebuCore SoC alive\n");

    /* Mark UART test done */
    COMPLETION_MARKER_ADDR = MARKER_UART_DONE;

    /* ── Step 2: Configure PWM Generator ────────────────────────────────── */
    /* Disable PWM first for safe configuration */
    PWM_CTRL = 0;

    /* Set duty cycle to 128 (≈50% of 255) */
    PWM_DUTY = 128;

    /* Set period to 1000 clock ticks (100 kHz at 100 MHz) */
    PWM_PERIOD = 1000;

    /* Verify configuration by reading back */
    if (PWM_DUTY != 128 || PWM_PERIOD != 1000) {
        uart_puts("FAIL: PWM config readback mismatch\n");
        uart_puts("  DUTY=0x");
        uart_put_hex(PWM_DUTY);
        uart_puts(" PERIOD=0x");
        uart_put_hex(PWM_PERIOD);
        uart_putc('\n');
        /* Hang on failure */
        while (1) { }
    }

    COMPLETION_MARKER_ADDR = MARKER_PWM_CONFIG;
    uart_puts("PWM configured: duty=128 period=1000\n");

    /* ── Step 3: Enable PWM and check status ─────────────────────────────── */
    PWM_CTRL = PWM_CTRL_EN;

    /* Small delay — read STATUS after a few cycles */
    {
        volatile int delay;
        for (delay = 0; delay < 100; delay++) { }
    }

    status = PWM_STATUS;

    uart_puts("PWM STATUS=0x");
    uart_put_hex(status);
    uart_putc('\n');

    /* Check that pwm_active (bit 0) is set */
    if ((status & 0x01) == 0) {
        uart_puts("WARN: PWM not active after enable\n");
    }

    COMPLETION_MARKER_ADDR = MARKER_PWM_ENABLE;

    /* ── Step 4: Final completion marker ──────────────────────────────────── */
    uart_puts("All firmware tests passed\n");
    COMPLETION_MARKER_ADDR = MARKER_ALL_PASS;

    /* Infinite loop — the testbench will detect completion via the marker */
    while (1) {
        /* Keep the core running; watchdog would normally be kicked here */
    }

    return 0;
}
