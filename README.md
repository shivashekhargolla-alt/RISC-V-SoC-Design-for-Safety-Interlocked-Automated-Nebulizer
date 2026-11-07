# NebuCore SoC — nebulizer-soc

A RISC-V-based System-on-Chip for automated, safety-interlocked nebulizer dosage control.

---

## What the project does

The SoC accepts a caregiver-entered liquid volume (mL), converts it to a treatment duration in firmware, drives a piezoelectric nebulising element for exactly that duration, and enforces a hard hardware safety lock so the actuator cannot be silently re-enabled once the dose is complete.

The safety interlock lives entirely in hardware (Watchdog Timer) — a firmware fault or race condition cannot, by itself, leave the actuator running.

---

## 📚 Core Project Documentation

* 🏛️ **[System Architecture Specification](doc/ARCHITECTURE.md)**: Full architectural breakdown, block diagrams, VeeR EL2 core, and zero-latency hardware safety interlock.
* 🗺️ **[Master System Address & Register Map](doc/ADDRESS_MAP.md)**: Unified memory map, AXI4 interconnect ports, and complete peripheral register specifications.
* 🧪 **[Master Verification & Test Map](doc/TEST_MAP.md)**: UVM 1.2 testbench topology, test case mapping matrix, firmware milestone markers, and coverage goals.
* 📊 **[Full SoC Address Map Spreadsheet](doc/Full_SoC_Address_Map.ods)**: Master OpenDocument spreadsheet.

---

## Repository layout

```
Secure-IoT-Gateway-SoC/
├── doc/                            Architecture, signal lists, register maps, test plans
│   ├── NebuCore_Block_Diagram_Signal_List.pdf
│   ├── RISC-V_VeeR_EL2_PRM.pdf
│   ├── external.txt
│   ├── internal.txt
│   ├── register_map.txt
│   ├── spec.pdf
│   └── test_plan.md
├── firmware/                       RISC-V firmware source, linker script, and hex converter
│   ├── elf_to_hex.py
│   ├── nebulizer.ld
│   ├── nebulizer_test.c
│   ├── nebulizer_test.dis
│   ├── nebulizer_test.elf
│   ├── nebulizer_test.hex
│   └── nebulizer_test.lst
├── main                            Top-level Makefile (build entry point)
├── README.md                       Project documentation
├── rtl/                            RTL designs (SoC top, AXI interconnect, VeeR EL2 core, peripheral IPs)
│   ├── arbiter.v
│   ├── axi_interconnect.v
│   ├── axi_interconnect_wrap_3x15.v
│   ├── axi_width_adapter.sv
│   ├── priority_encoder.v
│   ├── soc_top.sv
│   ├── tb_axi_interconnect_3x15.sv
│   ├── tb_pwm_top.sv
│   ├── tb_soc_top.sv
│   ├── gpio/                       AXI-Lite GPIO IP
│   ├── pwm/                        AXI-Lite PWM Generator IP
│   ├── riscv/                      RISC-V VeeR EL2 processor core RTL
│   ├── seg7/                       AXI-Lite 7-Segment Controller IP
│   ├── timer/                      AXI-Lite Countdown Timer IP
│   ├── uart/                       AXI-Lite UART IP
│   └── wdt/                        AXI-Lite Watchdog Timer IP
├── run/                            VCS run scripts and filelists
│   ├── axi_interconnect_wrap_1x8.v
│   ├── axi_interconnect_wrap_2x8.v
│   ├── pwm_runfile.f
│   └── runfile.f
├── scripts/                        Python and helper scripts (interconnect wrappers)
│   ├── axi_interconnect_wrap.py
│   └── axi_interconnect_wrap_2x8.v
├── snapshots/                      VeeR EL2 core configuration snapshots (default)
│   └── default/
│       ├── common_defines.vh
│       ├── defines.h
│       ├── el2_param.vh
│       ├── el2_pdef.vh
│       ├── link.ld
│       ├── pd_defines.vh
│       ├── perl_configs.pl
│       ├── pic_map_auto.h
│       └── whisper.json
├── tb/                             Testbench sources and slave stubs
│   ├── axi_slave_stub.v
│   ├── tb_axi_interconnect.v
│   └── tb_axi_interconnect_2x8.v
└── verdi_config_file               Verdi / nWave waveform viewer configuration
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
  uart_tx ◄─────────│                    │  M02 ─► Timer (0x1200_0000)│  │
  uart_irq ◄────────│                    │  M03 ─► GPIO  (0x1300_0000)│  │
                    │                    │  M04 ─► PWM   (0x1400_0000)│  │◄── pwm_force_disable
                    │                    │  M05 ─► Seg7  (0x1500_0000)│  │
                    │                    │  M06 ─► WDT   (0x1600_0000)│  │
                    │                    │  M07-M14: error slave stubs │  │
                    │                    └────────────────────────┘    │──► pwm_out
                    └─────────────────────────────────────────────────┘
```

### Address map

| Address range             | Size   | Peripheral        | IC port |
|---------------------------|--------|-------------------|---------|
| `0x0000_0000–0x3FFF_FFFF` | 1 GiB  | RAM (boot + data) | M01     |
| `0x1000_0000–0x10FF_FFFF` | 16 MiB | UART              | M00     |
| `0x1200_0000–0x1200_0FFF` | 4 KiB  | Countdown Timer   | M02     |
| `0x1300_0000–0x1300_0FFF` | 4 KiB  | GPIO              | M03     |
| `0x1400_0000–0x1400_0FFF` | 4 KiB  | PWM Generator     | M04     |
| `0x1500_0000–0x1500_0FFF` | 4 KiB  | 7-Segment Display | M05     |
| `0x1600_0000–0x1600_0FFF` | 4 KiB  | Watchdog Timer    | M06     |

---

## Running simulations

All targets can be run using `./main <target>` or `make -f main <target>` from the project root:

```bash
./main sim_1x8        # 1-master / 8-slave interconnect TB
./main sim_2x8        # 2-master / 8-slave interconnect TB
./main sim_3x15       # 3-master / 15-slave interconnect TB (with UART IP)
./main sim_pwm        # Standalone PWM Generator TB
./main sim_soc        # Complete SoC TB (RISC-V + Interconnect + All Peripherals)
./main firmware       # Cross-compile firmware for RV32IMC
./main sim_firmware   # SoC simulation with firmware loaded into memory
./main clean          # Remove all generated build and simulation artefacts
```

### Waveform Viewing

```bash
# In Verdi:
verdi -rcFile verdi_config_file

# In GTKWave:
./main waves_1x8
./main waves_2x8
./main waves_pwm
./main waves_soc
```
