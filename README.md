# NebuCore SoC — nebulizer-soc

A RISC-V-based System-on-Chip for automated, safety-interlocked nebulizer dosage control.

---

## What the project does

The SoC accepts a caregiver-entered liquid volume (mL), converts it to a treatment duration in firmware, drives a piezoelectric nebulising element for exactly that duration, and enforces a hard hardware safety lock so the actuator cannot be silently re-enabled once the dose is complete.

The safety interlock lives entirely in hardware (Watchdog Timer) — a firmware fault or race condition cannot, by itself, leave the actuator running.

---

## Repository layout

```
project/
├── riscv/                          RISC-V VeeR EL2 processor core
│   ├── design/                     RTL source (SV/V)
│   ├── testbench/                  Simulation testbench & hex images
│   ├── verification/               Block-level verification (pyUVM/cocotb)
│   ├── tools/                      Config scripts, riscv-dv, riscof
│   └── docs/                       VeeR EL2 PRM and source docs
│
├── axi4-interconnect-3to15/        AXI4 3-master × 15-slave interconnect
│   ├── rtl/interconnect/           Interconnect RTL + SoC top + testbenches
│   │   ├── axi_interconnect.v      Core crossbar logic
│   │   ├── axi_interconnect_wrap_3x15.v   Parameterised wrapper
│   │   ├── arbiter.v / priority_encoder.v
│   │   ├── axi_width_adapter.sv    64-bit IC ↔ 32-bit peripheral bridge
│   │   ├── soc_top.sv              SoC integration top (RISC-V + IC + IPs)
│   │   ├── tb_soc_top.sv           Full SoC testbench
│   │   ├── tb_axi_interconnect_3x15.sv    Interconnect + UART testbench
│   │   └── tb_pwm_top.sv           Standalone PWM testbench  ← new
│   ├── tb/                         Earlier 2x8 testbenches
│   ├── run/
│   │   ├── runfile.f               2x8 filelist
│   │   └── pwm_runfile.f           PWM standalone filelist   ← new
│   └── Makefile                    All simulation targets
│
├── uart/                           AXI-Lite UART IP (external, BSC/CIC-IPN)
│   └── src/rtl/                    axi_uart_top.v + sub-modules
│
├── pwm/                            AXI-Lite PWM Generator IP  ← new
│   ├── README.md
│   ├── project.config
│   ├── scripts/filelist
│   └── src/
│       ├── include/pwm_defines.vh  Register-map & AXI width defines
│       └── rtl/axi_pwm_top.v       PWM Generator RTL
│
├── spec.pdf                        NebuCore SoC specification
└── NebuCore_Block_Diagram_Signal_List.pdf
```

---

## SoC architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │                   NebuCore SoC                   │
                    │                                                   │
  rst_n ──────────►│  ┌─────────────┐   AXI4 (LSU/IFU/SB)            │
  clk  ──────────►│  │ RISC-V      ├──────────────────────┐           │
                    │  │ VeeR EL2    │                      ▼           │
  rst_vec ─────────►│  │ (el2_veer_  │   ┌────────────────────────┐    │
  nmi_int ─────────►│  │  wrapper)   │   │  AXI4 3×15 Interconnect │    │
                    │  └─────────────┘   │                          │    │
                    │                    │  M00 ─► UART  (0x1000_0000)│  │
  uart_rx ─────────►│                    │  M01 ─► RAM   (0x0000_0000)│  │
  uart_tx ◄─────────│                    │  M04 ─► PWM   (0x1400_0000)│  │◄── pwm_force_disable
  uart_irq ◄────────│                    │  M02-M03,M05-M14: stubs    │  │
                    │                    └────────────────────────┘    │──► pwm_out
                    └─────────────────────────────────────────────────┘
```

### Address map

| Address range             | Size   | Peripheral        | IC port |
|---------------------------|--------|-------------------|---------|
| `0x0000_0000–0x3FFF_FFFF` | 1 GiB  | RAM (boot + data) | M01     |
| `0x1000_0000–0x10FF_FFFF` | 16 MiB | UART              | M00     |
| `0x1400_0000–0x1400_0FFF` | 4 KiB  | PWM Generator     | M04     |

---

## Peripheral IPs

### Already integrated

| IP | Bus port | Notes |
|----|----------|-------|
| UART (axi_uart_top) | M00 | Serial logging; AXI-Lite 32-bit via width adapter |
| RAM (behavioural) | M01 | 64-bit AXI4; exposed as soc_top ports for TB |

### Added in this session

| IP | Bus port | Notes |
|----|----------|-------|
| **PWM Generator** (axi_pwm_top) | M04 | AXI-Lite 32-bit via width adapter |

### Still to add (per spec)

| IP | Suggested port |
|----|----------------|
| Timer (countdown + IRQ) | M02 |
| GPIO (volume switches + alarm) | M03 |
| Seven-Segment Display Controller | M05 |
| Watchdog Timer (safety interlock) | M06 |

---

## PWM Generator — what was built

### Files

| File | Description |
|------|-------------|
| `pwm/src/include/pwm_defines.vh` | AXI widths, register offsets, reset defaults |
| `pwm/src/rtl/axi_pwm_top.v` | AXI-Lite slave PWM Generator RTL |
| `axi4-interconnect-3to15/rtl/interconnect/tb_pwm_top.sv` | Standalone testbench |
| `axi4-interconnect-3to15/run/pwm_runfile.f` | VCS filelist |

### Register map

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| `0x00` | CTRL   | R/W    | `[0]` pwm_en — firmware must refresh once per Timer tick |
| `0x04` | DUTY   | R/W    | `[7:0]` duty cycle numerator (0 = 0 %, 255 ≈ 100 %) |
| `0x08` | PERIOD | R/W    | `[15:0]` period in clock ticks (default 1000 → 100 kHz @ 100 MHz) |
| `0x0C` | STATUS | R      | `[0]` pwm_active, `[1]` force_disabled |

### Safety mechanism

`pwm_force_disable_i` is a **combinational** input driven by the Watchdog Timer (`wdt_locked`). When asserted it forces `pwm_out` LOW with zero clock-cycle latency — independent of the `pwm_en` register or any firmware activity.

```
pwm_out = ctrl_pwm_en  AND  (counter < duty_threshold)  AND  NOT pwm_force_disable_i
```

### How it is wired into the SoC

```
soc_top.sv
  ├── axi_interconnect_wrap_3x15  M04 → m04_* wires
  ├── axi_width_adapter           64-bit IC ↔ 32-bit PWM
  └── axi_pwm_top                 u_pwm
        ├── pwm_force_disable_i ← soc_top port  (→ Watchdog, future)
        └── pwm_out_o           → soc_top port  (→ Piezo Driver)
```

---

## Running simulations

All targets are driven from `axi4-interconnect-3to15/`:

```bash
cd axi4-interconnect-3to15
```

| Command | What it runs |
|---------|-------------|
| `make sim_pwm` | **PWM standalone TB** (new) |
| `make sim_3x15` | AXI interconnect + UART TB |
| `make sim_soc` | Full SoC TB (RISC-V + IC + UART) |
| `make sim_2x8` | Earlier 2-master interconnect TB |
| `make waves_pwm` | Open `tb_pwm_top.vcd` in GTKWave |
| `make clean` | Remove all generated artefacts |

### PWM simulation in detail

```bash
make sim_pwm
# compiles:  compile_pwm.log
# simulates: sim_pwm.log
# waveform:  tb_pwm_top.vcd
```

The testbench runs 5 self-checking tests and prints `PASS` or `FAIL (N errors)`:

| Test | Checks |
|------|--------|
| 1 | Reset defaults (CTRL=0, DUTY=128, PERIOD=1000, STATUS=0) |
| 2 | Write DUTY=0x40 + PERIOD=0x100, read-back both |
| 3 | Enable PWM — `pwm_out` toggles high within 2 periods |
| 4 | Assert `pwm_force_disable` — `pwm_out` stays LOW (combinational) |
| 5 | Clear `pwm_en` — output stays LOW after force_disable released |

### Simulator requirements

- Synopsys VCS U-2023.03 (set `VCS_HOME` in Makefile if path differs)
- License server: `/home/install/LMGR/license.lic`
- GTKWave (optional, for waveform viewing)

---

## Spec documents

- `spec.pdf` — Full NebuCore SoC specification (architecture, signal list, data/control paths)
- `NebuCore_Block_Diagram_Signal_List.pdf` — Block diagram and per-IP signal tables
