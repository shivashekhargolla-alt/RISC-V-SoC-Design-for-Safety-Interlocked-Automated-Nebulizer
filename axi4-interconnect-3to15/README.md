# NebuCore AXI Interconnect — RTL Verification Project

AXI4 interconnect for the NebuCore SoC, connecting 2 masters and 8 slaves.
Simulated with Synopsys VCS and visualised in Verdi.

---

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Address Map](#address-map)
- [RTL Architecture](#rtl-architecture)
- [Testbench & Test Plan](#testbench--test-plan)
- [Simulation Flow](#simulation-flow)
- [Waveform Viewing (Verdi)](#waveform-viewing-verdi)
- [Tool Requirements](#tool-requirements)
- [Clean Up](#clean-up)

---

## Overview

| Parameter    | Value          |
|-------------|----------------|
| Protocol     | AXI4           |
| Masters      | 2 (M0 = RISC-V core, M1 = DMA/debug) |
| Slaves       | 8 (IMEM, DMEM, UART, TIMER, GPIO, PWM, 7SEG, WDT) |
| Data width   | 32-bit         |
| Address width| 32-bit         |
| ID width     | 8-bit          |
| Clock        | 100 MHz (10 ns period) |
| Simulator    | Synopsys VCS U-2023.03 |
| Waveform     | Synopsys Verdi / FSDB  |

---

## Directory Structure

```
project_dir/
├── rtl/
│   └── interconnect/
│       ├── axi_interconnect.v       # Core AXI4 interconnect (parameterised, NxM)
│       ├── arbiter.v                # Round-robin / priority arbiter
│       └── priority_encoder.v      # Priority encoder helper
├── script/
│   ├── axi_interconnect_wrap_2x8.v  # Generated 2-master × 8-slave wrapper
│   └── axi_interconnect_wrap.py     # Python script to regenerate the wrapper
├── run/
│   ├── axi_interconnect_wrap_2x8.v  # Copy of wrapper used during compile
│   └── runfile.f                    # VCS file list for sim_2x8 target
├── tb/
│   ├── tb_axi_interconnect_2x8.v   # 2×8 testbench (this project)
│   ├── tb_axi_interconnect.v        # 1×8 testbench (reference)
│   └── axi_slave_stub.v             # Parameterisable AXI slave model
├── extra/
│   └── axi_slave_stub.v             # Alternate location of slave stub
├── doc/
│   ├── spec.pdf                     # NebuCore SoC specification
│   └── RISC-V_VeeR_EL2_PRM.pdf      # RISC-V VeeR EL2 programmer reference
├── Makefile                         # Build & simulation targets
└── README.md                        # This file
```

---

## Address Map

| Slave | Peripheral | Base Address   | Region Width |
|-------|-----------|----------------|-------------|
| S0    | IMEM      | `0x0000_0000`  | 14-bit (16 KB) |
| S1    | DMEM      | `0x0001_0000`  | 14-bit (16 KB) |
| S2    | UART      | `0x0002_0000`  | 12-bit (4 KB)  |
| S3    | TIMER     | `0x0003_0000`  | 12-bit (4 KB)  |
| S4    | GPIO      | `0x0004_0000`  | 12-bit (4 KB)  |
| S5    | PWM       | `0x0005_0000`  | 12-bit (4 KB)  |
| S6    | 7SEG      | `0x0006_0000`  | 12-bit (4 KB)  |
| S7    | WDT       | `0x0007_0000`  | 12-bit (4 KB)  |

Any address outside the above ranges returns a `DECERR` response.

---

## RTL Architecture

```
          ┌──────────┐        ┌──────────────────────────┐        ┌──────────┐
  M0      │          │        │                          │        │  IMEM S0 │
 (RISC-V) ├──────────┤        │   axi_interconnect       │        ├──────────┤
          │ s00_axi  ├───────►│   (arbiter +             ├───────►│  DMEM S1 │
  M1      │          │        │    address decoder)      │        ├──────────┤
  (DMA)   ├──────────┤        │                          │  ...   │  UART S2 │
          │ s01_axi  ├───────►│   Wrapper:               │        ├──────────┤
          │          │        │   axi_interconnect_       │        │  ...     │
          └──────────┘        │   wrap_2x8               │        │  WDT  S7 │
                              └──────────────────────────┘        └──────────┘
```

- `axi_interconnect.v` — generic NxM crossbar with configurable masters, slaves, data/address/ID widths, and optional sideband signals.
- `arbiter.v` — handles simultaneous requests from multiple masters to the same slave; serialises them without deadlock.
- `axi_interconnect_wrap_2x8.v` — auto-generated wrapper that locks in `S_COUNT=2`, `M_COUNT=8` and flattens all port parameters for the NebuCore address map.

---

## Testbench & Test Plan

**Top module:** `tb_axi_interconnect_2x8`

**Slave model:** `axi_slave_stub` — a simple memory-backed AXI4 slave with a programmable response delay (`DELAY` parameter). The WDT slave uses `DELAY=4` to exercise back-pressure paths.

| TC   | Description                                              | Masters involved |
|------|----------------------------------------------------------|-----------------|
| TC01 | Reset — no spurious signals on either master port        | M0, M1          |
| TC02 | M0 writes to every slave → OKAY response                 | M0              |
| TC03 | M0 reads back from every slave → correct data            | M0              |
| TC04 | M1 writes to every slave → OKAY response                 | M1              |
| TC05 | M1 reads back from every slave → correct data            | M1              |
| TC06 | Simultaneous access — M0→IMEM and M1→TIMER (different slaves) | M0, M1     |
| TC07 | Arbitration — M0 and M1 both target DMEM simultaneously  | M0, M1          |
| TC08 | Address decode error from each master → DECERR           | M0, M1          |
| TC09 | Back-pressure — WDT slave (DELAY=4), both masters        | M0, M1          |
| TC10 | Boundary addresses — first/last word of IMEM and DMEM    | M0, M1          |

**Timeout:** Each transaction has a per-cycle watchdog of 1000 cycles. A global watchdog kills the simulation if it exceeds `200 × TIMEOUT × 10 ns`.

**Output files generated by simulation:**

| File                               | Contents              |
|------------------------------------|-----------------------|
| `sim_2x8.log`                      | Pass/fail summary     |
| `tb_axi_interconnect_2x8.vcd`      | VCD waveform (GTKWave)|
| `tb_axi_interconnect_2x8.fsdb`     | FSDB waveform (Verdi) |

---

## Simulation Flow

All commands are run from `project_dir/`.

### Compile + run (2×8 target)

```bash
make sim_2x8
```

This compiles all RTL and the testbench, then runs the simulation. Results are printed to the terminal and saved in `sim_2x8.log`.

### Run only (after a successful compile)

```bash
./simv_2x8 -l sim_2x8.log
```

### Manual VCS compile using runfile

```bash
vcs -full64 -sverilog +v2k -timescale=1ns/1ps -debug_access+all \
    -top tb_axi_interconnect_2x8 \
    -f run/runfile.f \
    -o simv_2x8 -l compile_2x8.log
```

### File list (`run/runfile.f`)

```
rtl/interconnect/arbiter.v
rtl/interconnect/priority_encoder.v
rtl/interconnect/axi_interconnect.v
script/axi_interconnect_wrap_2x8.v
extra/axi_slave_stub.v
tb/tb_axi_interconnect_2x8.v
```

---

## Waveform Viewing (Verdi)

Make sure the simulation has been run first so the FSDB file exists.

```bash
verdi -sv -f run/runfile.f \
      -top tb_axi_interconnect_2x8 \
      -ssf tb_axi_interconnect_2x8.fsdb &
```

In Verdi:
1. Use the **nWave** panel to browse the design hierarchy.
2. Drag signals into the waveform window.
3. Use **Ctrl+F** to search for signal names.

To open a VCD file in GTKWave instead:

```bash
gtkwave tb_axi_interconnect_2x8.vcd &
```

---

## Tool Requirements

| Tool             | Version         | Purpose              |
|-----------------|-----------------|----------------------|
| Synopsys VCS     | U-2023.03       | Simulation           |
| Synopsys Verdi   | (matching VCS)  | Waveform debug       |
| GTKWave          | any             | VCD waveform viewer  |
| Python 3         | 3.6+            | Wrapper regeneration |
| GNU Make         | any             | Build automation     |

**License server** must be running before invoking VCS or Verdi:

```bash
cd /home/install/LMGR && ./lmgrd -c license.lic
```

Set the license path:

```bash
export LM_LICENSE_FILE=/home/install/LMGR/license.lic
```

---

## Clean Up

Remove all generated simulation artefacts:

```bash
make clean
```

This removes `simv_2x8`, `simv_2x8.daidir`, `csrc`, compile/sim logs, VCD, and FSDB files.
# axi4-interconnect-2x8
