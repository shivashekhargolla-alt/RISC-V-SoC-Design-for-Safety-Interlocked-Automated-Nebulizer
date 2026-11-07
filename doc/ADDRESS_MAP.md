# 🗺️ NebuCore SoC — Master System Address & Register Map

This document defines the complete memory map, AXI4 interconnect port allocation, and peripheral register definitions for the **NebuCore RISC-V System-on-Chip**.

---

## 📌 1. High-Level SoC Memory Map

All memories, processor core internal regions, and peripheral control/status registers reside within a unified **32-bit physical address space** ($4\text{ GiB}$).

| Region / Subsystem | Interconnect Port | Base Address | End Address | Allocated Size | Data Width | Access Type | Description |
|---|---|---|---|---|---|---|---|
| **System Boot & Data RAM** | **M01** | `0x0000_0000` | `0x0FFF_FFFF` | 256 MiB | 64-bit | R / W / X | Main memory: firmware instructions, data buffers, and UVM testbench markers. |
| **UART Controller** | **M00** | `0x1000_0000` | `0x10FF_FFFF` | 16 MiB (4 KB decoded) | 32-bit | R / W | 16550-compatible serial communications interface. |
| **Countdown Timer** | **M02** | `0x1200_0000` | `0x1200_0FFF` | 4 KiB | 32-bit | R / W | High-resolution tick counter for real-time treatment timing. |
| **GPIO Subsystem** | **M03** | `0x1300_0000` | `0x1300_0FFF` | 4 KiB | 32-bit | R / W | 8-bit bidirectional digital I/O for switches, LEDs, and status indicators. |
| **PWM Generator** | **M04** | `0x1400_0000` | `0x1400_0FFF` | 4 KiB | 32-bit | R / W | High-frequency pulse-width modulator for piezoelectric nebulizer element. |
| **Seven-Segment Display** | **M05** | `0x1500_0000` | `0x1500_0FFF` | 4 KiB | 32-bit | R / W | 4-digit time-multiplexed 7-segment LED display controller. |
| **Watchdog Timer (WDT)** | **M06** | `0x1600_0000` | `0x1600_0FFF` | 4 KiB | 32-bit | R / W | **Hardware Safety Interlock:** Irreversible set-only actuator lockdown. |
| *Reserved Expansion Slots* | *M07–M14* | `0x1700_0000` | `0x1EFF_FFFF` | — | 32-bit | — | Reserved for Neural Network inference accelerator & DMA controller. |
| **VeeR ICCM (Internal)** | Core-internal | `0xEE00_0000` | `0xEE00_FFFF` | 64 KiB | 64-bit | R / X | Instruction Closely-Coupled Memory (direct single-cycle fetch, bypasses AXI). |
| **VeeR DCCM (Internal)** | Core-internal | `0xF004_0000` | `0xF004_FFFF` | 64 KiB | 64-bit | R / W | Data Closely-Coupled Memory (direct single-cycle load/store, bypasses AXI). |
| **VeeR PIC (Internal)** | Core-internal | `0xF00C_0000` | `0xF00C_7FFF` | 32 KiB | 32-bit | R / W | Programmable Interrupt Controller registers. |

> 📁 **Spreadsheet Reference:** A full multi-tab spreadsheet is archived in [`doc/Full_SoC_Address_Map.ods`](Full_SoC_Address_Map.ods).

---

## 🧠 2. RAM Layout & UVM Testbench Markers

The 64-bit AXI4 System RAM (`0x0000_0000`) hosts the compiled firmware and a dedicated handshake mailbox for synchronization between firmware and the UVM verification environment:

| Address | Symbol | Size | Access | Description |
|---|---|---|---|---|
| `0x0000_0000` | `_start` | — | Read / Execute | Reset vector jump instruction (`j reset_handler`). |
| `0x0000_0080` | `.text` | ~4 KB | Read / Execute | Firmware executable machine instructions. |
| `0x0000_0800` | `.data` / `.bss` | ~2 KB | Read / Write | Global variables and runtime heap. |
| `0x0000_1000` | `COMPLETION_MARKER` | 32 bits | Read / Write | **UVM Test Mailbox:** Firmware writes milestone markers (`0x55AA_xxxx`). |
| `0x0000_1004` | `TEST_MODE` | 32 bits | Read / Write | UVM testbench writes test mode selection (`0`=All, `1`=Phase 1, etc.). |
| `0x0000_1008` | `TEST_STATUS` | 32 bits | Read / Write | Test execution result flags (`0`=Running, `1`=Pass, `0xDEADFA11`=Fail). |
| `0x0000_3FF0` | `__stack_top` | — | Read / Write | Initial Stack Pointer (`sp = 0x0000_4000`). |

---

## ⚙️ 3. Detailed Peripheral Register Specifications

All peripheral registers are **32-bit word-aligned** (addresses step by `0x04`).

### 3.1 UART Controller (`0x1000_0000`, Interconnect Port: M00)
* **Bus Protocol:** AXI4-Lite (via 64b $\rightarrow$ 32b width adapter)
* **Clock Rate:** 100 MHz | **Default Baud Rate:** 115200 (Divisor = 868)

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **RBR / THR** | RW | `0x0000_0000` | **Read:** Receive Buffer (RBR [7:0])<br>**Write:** Transmit Holding Register (THR [7:0]) |
| `+0x04` | **IER** | RW | `0x0000_0000` | **Interrupt Enable:** Bit 0: RX Data Available, Bit 1: TX Empty, Bit 2: Line Status |
| `+0x08` | **BAUD_DIV** | RW | `0x0000_0364` | **Baud Rate Divisor:** Formula: $Div = \frac{f_{\text{clk}}}{16 \times \text{Baud}}$ |
| `+0x0C` | **LCR** | RW | `0x0000_0003` | **Line Control:** Bits [1:0]: Word length (11 = 8 bits), Bit 3: Parity Enable |
| `+0x14` | **LSR** | RO | `0x0000_0060` | **Line Status:** Bit 0: Data Ready (DR), Bit 5: THR Empty (THRE), Bit 6: Transmitter Empty |

---

### 3.2 Countdown Timer (`0x1200_0000`, Interconnect Port: M02)
Used by dosage control firmware to calculate treatment duration down to microsecond resolution.

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **TIMER_CTRL** | RW | `0x0000_0000` | Bit 0: Timer Enable (`EN`), Bit 1: Auto-reload (`RELOAD`), Bit 2: IRQ Enable |
| `+0x04` | **TIMER_LOAD** | RW | `0x0000_0000` | Initial reload count value ($32\text{-bit}$). |
| `+0x08` | **TIMER_CURRENT** | RO | `0x0000_0000` | Live countdown register value ($32\text{-bit}$). Decrements every clock cycle. |
| `+0x0C` | **TIMER_STATUS** | W1C | `0x0000_0000` | Bit 0: Countdown Expired Interrupt Flag (`1` = expired, write `1` to clear). |

---

### 3.3 GPIO Controller (`0x1300_0000`, Interconnect Port: M03)
Connects dosage entry switches (`gpio_pin_i[7:0]`) and status LEDs (`gpio_pin_o[7:0]`).

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **GPIO_DATA_IN** | RO | `0x0000_0000` | Bits [7:0]: Live state of input switches (caregiver medication volume selection). |
| `+0x04` | **GPIO_DATA_OUT** | RW | `0x0000_0000` | Bits [7:0]: Output pin state (driven to board LEDs and interlock telemetry). |
| `+0x08` | **GPIO_DIR** | RW | `0x0000_0000` | Bits [7:0]: Pin Output Enable (`0` = High-Z / Input, `1` = Output driver active). |
| `+0x0C` | **GPIO_INT_EN** | RW | `0x0000_0000` | Bits [7:0]: Pin-change interrupt enable mask. |
| `+0x10` | **GPIO_INT_STATUS**| W1C | `0x0000_0000` | Bits [7:0]: Interrupt pending flags (write `1` to clear). |

---

### 3.4 PWM Generator Subsystem (`0x1400_0000`, Interconnect Port: M04)
Generates high-frequency excitation pulses for the piezoelectric nebulizer mesh.

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **PWM_CTRL** | RW | `0x0000_0000` | Bit 0: PWM Core Enable (`pwm_en`). When `0`, PWM output is held low. |
| `+0x04` | **PWM_PERIOD** | RW | `0x0000_03E8` | PWM Period Counter ($16\text{-bit}$, e.g. `1000` cycles = 100 kHz at 100 MHz clock). |
| `+0x08` | **PWM_DUTY** | RW | `0x0000_0080` | PWM Duty Count ($8\text{-bit}$, e.g. `128` = ~50% duty cycle modulation). |
| `+0x0C` | **PWM_STATUS** | RO | `0x0000_0000` | Bit 0: Active running status (`1` = pulsing), Bit 1: Hardware Force-Disable Active. |

---

### 3.5 Seven-Segment Display Controller (`0x1500_0000`, Interconnect Port: M05)
Multiplexes 4-digit numeric treatment dosage and remaining time onto 7-segment cathodes.

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **SEG_DATA** | RW | `0x0000_0000` | Bits [6:0]: 7-Segment cathode encoding (`A, B, C, D, E, F, G`). |
| `+0x04` | **DIGIT_SEL** | RW | `0x0000_0001` | Bits [3:0]: One-hot active digit select anode driver. |
| `+0x08` | **SEG_CTRL** | RW | `0x0000_0001` | Bit 0: Display Enable, Bit 1: Auto-scan multiplexing engine enable. |

---

### 3.6 Watchdog Timer & Safety Interlock Core (`0x1600_0000`, Interconnect Port: M06)
**Hard Hardware Safety Enforcement Core:** Protects against software lockups and medication overdosing.

| Offset | Register Name | Access | Reset Value | Description & Bitfields |
|---|---|---|---|---|
| `+0x00` | **WDT_LOAD** | RW | `0x0000_0000` | Timeout threshold value ($32\text{-bit}$). |
| `+0x04` | **WDT_CURRENT** | RO | `0x0000_0000` | Current live counter value ($32\text{-bit}$). Decrements every clock cycle. |
| `+0x08` | **WDT_CTRL** | RW | `0x0000_0000` | Bit 0: Watchdog Enable, Bit 1: Hard Interlock Enable (`SAFETY_EN`). |
| `+0x0C` | **WDT_LOCK** | **RO / SET** | `0x0000_0000` | **`wdt_locked` Hardware Status:** When asserted, forcibly pulls `pwm_out_o` to `0` with zero latency. **Cannot be cleared by software.** Requires physical `rst_n`. |
| `+0x10` | **WDT_KICK** | WO | `0x0000_0000` | Writing `0x55AA` kicks the watchdog before timeout expires. |
