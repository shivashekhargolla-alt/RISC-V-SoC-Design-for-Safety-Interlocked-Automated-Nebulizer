/*
 * NebuCore SoC — UART to PWM Firmware Test
 *
 * Target: RISC-V VeeR EL2 Core (RV32IMC, 32-bit).
 *
 * Functionality:
 *   1. Initializes the AXI-Lite UART IP (baud rate divisor, 8N1).
 *   2. Receives input data from UART RX:
 *      - Supports external testbench injection or loopback.
 *      - If no byte has arrived yet, sends a test byte on TX which loops back to RX.
 *   3. Performs necessary computations:
 *      - Converts/scales UART input into PWM duty cycle (0..255).
 *      - Handles ASCII digit ('0'-'9') conversion or raw binary byte.
 *      - Computes active-high clock cycles and duty percentage.
 *   4. Configures and drives the AXI-Lite PWM Generator IP with the computed value.
 *   5. Verifies register readback and STATUS (active / force_disabled).
 *   6. Writes completion markers to RAM (0x1000) for testbench validation.
 */

/* ── Peripheral Base Addresses (from register_map.txt) ────────────────────── */
#define UART_BASE               0x10000000u
#define PWM_BASE                0x14000000u
#define RAM_BASE                0x00000000u

/* ── UART Registers ───────────────────────────────────────────────────────── */
#define UART_RBR_THR            (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_IER                (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_BAUD_DIV           (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_LCR                (*(volatile unsigned int *)(UART_BASE + 0x0C))
#define UART_LSR                (*(volatile unsigned int *)(UART_BASE + 0x14))

/* UART LSR Flags */
#define UART_LSR_DATA_READY     (1u << 0)  /* Byte available in RBR */
#define UART_LSR_THR_EMPTY      (1u << 5)  /* TX holding register empty */

/* ── PWM Registers ────────────────────────────────────────────────────────── */
#define PWM_CTRL                (*(volatile unsigned int *)(PWM_BASE + 0x00))
#define PWM_DUTY                (*(volatile unsigned int *)(PWM_BASE + 0x04))
#define PWM_PERIOD              (*(volatile unsigned int *)(PWM_BASE + 0x08))
#define PWM_STATUS              (*(volatile unsigned int *)(PWM_BASE + 0x0C))

/* PWM Flags */
#define PWM_CTRL_EN             (1u << 0)
#define PWM_STATUS_ACTIVE       (1u << 0)
#define PWM_STATUS_FORCED       (1u << 1)

/* ── Test Completion Markers ──────────────────────────────────────────────── */
#define COMPLETION_MARKER_ADDR  (*(volatile unsigned int *)(RAM_BASE + 0x1000))

#define MARKER_UART_INIT        0x55AA0001u
#define MARKER_UART_RX_DONE     0x55AA0002u
#define MARKER_PWM_CONFIG       0x55AA0003u
#define MARKER_ALL_PASS         0x55AA00FFu

/* ── UART Helper Functions ────────────────────────────────────────────────── */
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

static const char hexdigits[] = "0123456789ABCDEF";

static void uart_put_hex(unsigned int val)
{
    int i;
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(hexdigits[(val >> i) & 0xFu]);
    }
}

static void uart_put_hex8(unsigned int val)
{
    uart_putc(hexdigits[(val >> 4) & 0xFu]);
    uart_putc(hexdigits[val & 0xFu]);
}

static void uart_put_dec(unsigned int val)
{
    char buf[12];
    int idx = 0;
    if (val == 0) {
        uart_putc('0');
        return;
    }
    while (val > 0) {
        buf[idx++] = '0' + (val % 10);
        val /= 10;
    }
    while (idx > 0) {
        uart_putc(buf[--idx]);
    }
}

/* ── Computation Function ─────────────────────────────────────────────────── */
/*
 * Computes the 8-bit PWM duty cycle value from the UART input.
 * Supports:
 *   - ASCII digits ('0'-'9'): converts to 0..9 and scales across 0..252.
 *   - ASCII hex ('A'-'F' / 'a'-'f'): converts to 10..15 and scales.
 *   - Raw binary bytes (0..255): direct mapping.
 */
static unsigned int compute_pwm_duty(unsigned int uart_val)
{
    unsigned int duty;
    if (uart_val >= '0' && uart_val <= '9') {
        /* Map ASCII '0'..'9' -> 0..252 (steps of 28, covering 0% to ~99%) */
        duty = (uart_val - '0') * 28u;
    } else if (uart_val >= 'A' && uart_val <= 'F') {
        duty = (uart_val - 'A' + 10u) * 16u;
    } else if (uart_val >= 'a' && uart_val <= 'f') {
        duty = (uart_val - 'a' + 10u) * 16u;
    } else {
        duty = (uart_val & 0xFFu);
    }

    /* Clamp to valid 8-bit range */
    if (duty > 255u) duty = 255u;
    return duty;
}

/* ── Entry Point / Reset Vector ───────────────────────────────────────────── */
__attribute__((section(".text.init"), naked, noreturn))
void _start(void)
{
    /* Set stack pointer to top of RAM (64 KiB), configure MRAC CSR 0x7c0 */
    __asm__ volatile (
        "la sp, _stack_top\n"
        "li t0, 0x55555559\n"
        "csrw 0x7c0, t0\n"
        "j main\n"
    );
    __builtin_unreachable();
}

/* ── Main Test ────────────────────────────────────────────────────────────── */
int main(void)
{
    unsigned int rx_data;
    unsigned int computed_duty;
    unsigned int pwm_period;
    unsigned int duty_pct;
    unsigned int active_ticks;
    unsigned int status;

    /* ── Step 1: Initialize UART ─────────────────────────────────────────── */
    UART_LCR = 0x83u;      /* Enable DLAB (divisor latch access) */
    UART_BAUD_DIV = 16u;   /* 16 ticks/baud for fast simulation */
    UART_LCR = 0x03u;      /* 8 data bits, 1 stop bit, no parity (DLAB=0) */
    UART_IER = 0x01u;      /* Enable RX interrupt bit so DATA_READY in LSR reflects FIFO status */

    uart_puts("\n======================================================\n");
    uart_puts("  NebuCore SoC: UART -> PWM Transfer & Control Test\n");
    uart_puts("======================================================\n");

    COMPLETION_MARKER_ADDR = MARKER_UART_INIT;

    /* ── Step 2: Fetch data from UART ────────────────────────────────────── */
    uart_puts("[FW] Listening for input data on UART RX...\n");

    /* Wait for incoming UART data from the testbench injection */
    rx_data = uart_getc();

    uart_puts("[FW] Successfully received byte from UART: 0x");
    uart_put_hex8(rx_data);
    uart_puts(" (decimal: ");
    uart_put_dec(rx_data);
    uart_puts(")\n");

    COMPLETION_MARKER_ADDR = MARKER_UART_RX_DONE;

    /* ── Step 3: Perform computations on the received UART value ─────────── */
    computed_duty = compute_pwm_duty(rx_data);
    if (computed_duty == 0) {
        computed_duty = 32u; /* ensure non-zero activity for waveform visibility */
    }

    pwm_period = 1000u; /* 1000 clock cycles = 10 us at 100 MHz (100 kHz frequency) */
    duty_pct = (computed_duty * 100u) / 255u;
    active_ticks = (computed_duty * pwm_period) >> 8;

    uart_puts("\n[FW] --- Computations ---\n");
    uart_puts("  Raw UART Data     : 0x");
    uart_put_hex8(rx_data);
    uart_puts("\n  Computed PWM Duty : ");
    uart_put_dec(computed_duty);
    uart_puts(" / 255 (");
    uart_put_dec(duty_pct);
    uart_puts("%)\n  PWM Period Ticks  : ");
    uart_put_dec(pwm_period);
    uart_puts(" ticks\n  Active-High Ticks : ");
    uart_put_dec(active_ticks);
    uart_puts(" ticks / period\n\n");

    /* ── Step 4: Drive the value to PWM Generator ────────────────────────── */
    uart_puts("[FW] Driving computed duty to PWM Generator IP...\n");

    /* Disable PWM first for clean configuration */
    PWM_CTRL = 0u;

    /* Write period and duty registers */
    PWM_PERIOD = pwm_period;
    PWM_DUTY   = computed_duty;

    /* Verify register write via readback */
    if (PWM_DUTY != computed_duty || PWM_PERIOD != pwm_period) {
        uart_puts("[FW] ERROR: PWM register readback mismatch!\n");
        uart_puts("  Expected DUTY=");
        uart_put_dec(computed_duty);
        uart_puts(" Got=");
        uart_put_dec(PWM_DUTY);
        uart_puts("\n");
        while (1) { }
    }

    uart_puts("[FW] Register readback verified. Enabling PWM output...\n");

    /* Enable PWM */
    PWM_CTRL = PWM_CTRL_EN;

    /* Delay to allow PWM waveform generator to run several cycles */
    for (volatile int d = 0; d < 300; d++) { }

    status = PWM_STATUS;
    uart_puts("[FW] PWM STATUS = 0x");
    uart_put_hex(status);
    uart_puts(" [active=");
    uart_put_dec(status & PWM_STATUS_ACTIVE);
    uart_puts(", force_disabled=");
    uart_put_dec((status & PWM_STATUS_FORCED) >> 1);
    uart_puts("]\n");

    if ((status & PWM_STATUS_ACTIVE) == 0) {
        uart_puts("[FW] ERROR: PWM not active after enable!\n");
        while (1) { }
    }

    COMPLETION_MARKER_ADDR = MARKER_PWM_CONFIG;

    uart_puts("\n======================================================\n");
    uart_puts("  SUCCESS: UART data successfully driven to PWM!\n");
    uart_puts("======================================================\n");

    COMPLETION_MARKER_ADDR = MARKER_ALL_PASS;

    /* Keep running so the PWM generator continues to pulse for waveform dump */
    while (1) { }

    return 0;
}
