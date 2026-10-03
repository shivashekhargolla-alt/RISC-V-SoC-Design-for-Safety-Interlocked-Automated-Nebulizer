# ============================================================
# Makefile — NebuCore AXI Interconnect Testbenches
# Simulator: Synopsys VCS  (U-2023.03)
#
# Targets:
#   make sim_1x8   — compile + run 1-master / 8-slave TB
#   make sim_2x8   — compile + run 2-master / 8-slave TB  ← new
#   make waves_1x8 — open 1x8 VCD in GTKWave
#   make waves_2x8 — open 2x8 VCD in GTKWave
#   make clean     — remove all generated artefacts
#
# NOTE: The Synopsys license server must be running.
#       If you see "Vendor daemon is down" start it with:
#         cd /home/install/LMGR && ./lmgrd -c license.lic
# ============================================================

VCS_HOME        := /home/student/snps_tools_target/vcs/U-2023.03
VCS             := $(VCS_HOME)/linux64/bin/vcs
LM_LICENSE_FILE := /home/install/LMGR/license.lic

export VCS_HOME
export LM_LICENSE_FILE

# ── Common RTL ───────────────────────────────────────────
RTL_COMMON := \
    rtl/interconnect/priority_encoder.v \
    rtl/interconnect/arbiter.v \
    rtl/interconnect/axi_interconnect.v

VCS_OPTS := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -debug_access+all

# ════════════════════════════════════════════════════════
# 1x8 target
# ════════════════════════════════════════════════════════
SRCS_1X8 := \
    $(RTL_COMMON) \
    run/axi_interconnect_wrap_1x8.v \
    tb/axi_slave_stub.v \
    tb/tb_axi_interconnect.v

SIM_1X8  := simv_1x8
TOP_1X8  := tb_axi_interconnect
VCD_1X8  := tb_axi_interconnect.vcd

sim_1x8: $(SIM_1X8)
	@echo ">>> Running 1x8 simulation..."
	./$(SIM_1X8) -l sim_1x8.log
	@echo ">>> Done. Log: sim_1x8.log"

$(SIM_1X8): $(SRCS_1X8)
	@echo ">>> Compiling 1x8 TB..."
	$(VCS) $(VCS_OPTS) -top $(TOP_1X8) $(SRCS_1X8) -o $(SIM_1X8) -l compile_1x8.log
	@echo ">>> Compilation done."

waves_1x8:
	@command -v gtkwave >/dev/null 2>&1 \
	    && gtkwave $(VCD_1X8) & \
	    || echo "GTKWave not found — open $(VCD_1X8) manually."

# ════════════════════════════════════════════════════════
# 2x8 target  (new)
# ════════════════════════════════════════════════════════
SRCS_2X8 := \
    $(RTL_COMMON) \
    rtl/interconnect/axi_slave.v \
    run/axi_interconnect_wrap_2x8.v \
    tb/axi_slave_stub.v \
    tb/tb_axi_interconnect_2x8.v

SIM_2X8  := simv_2x8
TOP_2X8  := tb_axi_interconnect_2x8
VCD_2X8  := tb_axi_interconnect_2x8.vcd

sim_2x8: $(SIM_2X8)
	@echo ">>> Running 2x8 simulation..."
	./$(SIM_2X8) -l sim_2x8.log
	@echo ">>> Done. Log: sim_2x8.log"

$(SIM_2X8): $(SRCS_2X8)
	@echo ">>> Compiling 2x8 TB..."
	$(VCS) $(VCS_OPTS) -top $(TOP_2X8) $(SRCS_2X8) -o $(SIM_2X8) -l compile_2x8.log
	@echo ">>> Compilation done."

waves_2x8:
	@command -v gtkwave >/dev/null 2>&1 \
	    && gtkwave $(VCD_2X8) & \
	    || echo "GTKWave not found — open $(VCD_2X8) manually."

# ════════════════════════════════════════════════════════
# 3x15 target  (AXI interconnect with real UART IP on M00)
# ════════════════════════════════════════════════════════
UART_RTL := \
    ../uart/src/rtl/axi_uart_top.v \
    ../uart/src/rtl/uart_controller.v \
    ../uart/src/rtl/uart_transmitter.v \
    ../uart/src/rtl/uart_receiver.v \
    ../uart/src/rtl/uart_parity_bit_compute.v \
    ../uart/src/rtl/axi_internal_fifo.v

VCS_OPTS_3X15 := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -debug_access+all \
    +incdir+../uart/src/include

SRCS_3X15 := \
    $(RTL_COMMON) \
    rtl/interconnect/axi_interconnect_wrap_3x15.v \
    $(UART_RTL) \
    rtl/interconnect/tb_axi_interconnect_3x15.sv

SIM_3X15  := simv_3x15
TOP_3X15  := tb_axi_interconnect_3x15

sim_3x15: $(SIM_3X15)
	@echo ">>> Running 3x15 simulation..."
	./$(SIM_3X15) -l sim_3x15.log
	@echo ">>> Done. Log: sim_3x15.log"

$(SIM_3X15): $(SRCS_3X15)
	@echo ">>> Compiling 3x15 TB (with UART IP on M00)..."
	$(VCS) $(VCS_OPTS_3X15) -top $(TOP_3X15) $(SRCS_3X15) -o $(SIM_3X15) -l compile_3x15.log
	@echo ">>> Compilation done."

# ════════════════════════════════════════════════════════
# soc_top target  (RISC-V VeeR EL2 + AXI Interconnect + UART)
# ════════════════════════════════════════════════════════
#
# Source layout:
#   RISC-V VeeR EL2 design files  → ../riscv/design/
#   UART AXI-Lite IP               → ../uart/src/rtl/
#   AXI interconnect               → rtl/interconnect/
#   Width adapter + SoC top + TB   → rtl/interconnect/
#
# Key compilation options:
#   +define+RV_BUILD_AXI4        – selects the AXI4 bus build in VeeR
#   +incdir+../riscv/design/include  – finds el2_def.sv, el2_param.vh, ...
#   +incdir+../uart/src/include      – finds axi_uart_defines.vh, axi_uart.vh

RISCV_DESIGN := ../riscv/design

RISCV_RTL := \
    $(RISCV_DESIGN)/el2_mubi_pkg.sv \
    $(RISCV_DESIGN)/el2_mem.sv \
    $(RISCV_DESIGN)/el2_dma_ctrl.sv \
    $(RISCV_DESIGN)/el2_pic_ctrl.sv \
    $(RISCV_DESIGN)/el2_pmp.sv \
    $(RISCV_DESIGN)/dbg/el2_dbg.sv \
    $(RISCV_DESIGN)/dmi/dmi_wrapper.v \
    $(RISCV_DESIGN)/dmi/dmi_jtag_to_core_sync.v \
    $(RISCV_DESIGN)/dmi/dmi_mux.v \
    $(RISCV_DESIGN)/dmi/rvjtag_tap.v \
    $(RISCV_DESIGN)/lib/beh_lib.sv \
    $(RISCV_DESIGN)/lib/mem_lib.sv \
    $(RISCV_DESIGN)/lib/el2_lib.sv \
    $(RISCV_DESIGN)/lib/el2_assert.sv \
    $(RISCV_DESIGN)/lib/el2_mem_if.sv \
    $(RISCV_DESIGN)/lib/el2_regfile_if.sv \
    $(RISCV_DESIGN)/lib/el2_prim_buf.sv \
    $(RISCV_DESIGN)/lib/el2_prim_generic_buf.sv \
    $(RISCV_DESIGN)/lib/axi4_to_ahb.sv \
    $(RISCV_DESIGN)/lib/ahb_to_axi4.sv \
    $(RISCV_DESIGN)/include/el2_def.sv \
    $(RISCV_DESIGN)/dec/el2_dec.sv \
    $(RISCV_DESIGN)/dec/el2_dec_decode_ctl.sv \
    $(RISCV_DESIGN)/dec/el2_dec_tlu_ctl.sv \
    $(RISCV_DESIGN)/dec/el2_dec_ib_ctl.sv \
    $(RISCV_DESIGN)/dec/el2_dec_gpr_ctl.sv \
    $(RISCV_DESIGN)/dec/el2_dec_pmp_ctl.sv \
    $(RISCV_DESIGN)/dec/el2_dec_trigger.sv \
    $(RISCV_DESIGN)/exu/el2_exu.sv \
    $(RISCV_DESIGN)/exu/el2_exu_alu_ctl.sv \
    $(RISCV_DESIGN)/exu/el2_exu_mul_ctl.sv \
    $(RISCV_DESIGN)/exu/el2_exu_div_ctl.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_bus_buffer.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_bus_intf.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_dccm_ctl.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_dccm_mem.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_ecc.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_lsc_ctl.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_stbuf.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_trigger.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_clkdomain.sv \
    $(RISCV_DESIGN)/lsu/el2_lsu_addrcheck.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_mem_ctl.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_ifc_ctl.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_aln_ctl.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_bp_ctl.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_compress_ctl.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_ic_mem.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_iccm_mem.sv \
    $(RISCV_DESIGN)/ifu/el2_ifu_tb_memread.sv \
    $(RISCV_DESIGN)/el2_veer.sv \
    $(RISCV_DESIGN)/el2_veer_wrapper.sv

VCS_OPTS_SOC := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -debug_access+all \
    +define+RV_BUILD_AXI4 \
    +incdir+$(RISCV_DESIGN)/include \
    +incdir+../uart/src/include

SRCS_SOC := \
    $(RTL_COMMON) \
    rtl/interconnect/axi_interconnect_wrap_3x15.v \
    $(UART_RTL) \
    $(RISCV_RTL) \
    rtl/interconnect/axi_width_adapter.sv \
    rtl/interconnect/soc_top.sv \
    rtl/interconnect/tb_soc_top.sv

SIM_SOC  := simv_soc
TOP_SOC  := tb_soc_top

sim_soc: $(SIM_SOC)
	@echo ">>> Running SoC simulation (RISC-V + AXI Interconnect + UART)..."
	./$(SIM_SOC) -l sim_soc.log
	@echo ">>> Done. Log: sim_soc.log"

$(SIM_SOC): $(SRCS_SOC)
	@echo ">>> Compiling SoC TB (RISC-V VeeR EL2 + AXI 3x15 + UART)..."
	$(VCS) $(VCS_OPTS_SOC) -top $(TOP_SOC) $(SRCS_SOC) -o $(SIM_SOC) -l compile_soc.log
	@echo ">>> Compilation done. Log: compile_soc.log"

waves_soc:
	@command -v gtkwave >/dev/null 2>&1 \
	    && gtkwave soc_top.fsdb & \
	    || echo "Use Verdi/DVE to open soc_top.fsdb"

# ════════════════════════════════════════════════════════
# sim_pwm target — Standalone PWM Generator testbench
#
# DUT chain:  AXI 3×15 Interconnect
#               └─ M04 → axi_width_adapter → axi_pwm_top
#
# Source list: run/pwm_runfile.f
# Include dir: ../pwm/src/include  (pwm_defines.vh)
# Top module:  tb_pwm_top
# ════════════════════════════════════════════════════════

VCS_OPTS_PWM := \
    -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/1ps \
    -debug_access+all \
    +incdir+../pwm/src/include

SIM_PWM  := simv_pwm
TOP_PWM  := tb_pwm_top
VCD_PWM  := tb_pwm_top.vcd

sim_pwm: $(SIM_PWM)
	@echo ">>> Running PWM standalone simulation..."
	./$(SIM_PWM) -l sim_pwm.log
	@echo ">>> Done. Log: sim_pwm.log  Waveform: $(VCD_PWM)"

$(SIM_PWM): run/pwm_runfile.f \
            rtl/interconnect/priority_encoder.v \
            rtl/interconnect/arbiter.v \
            rtl/interconnect/axi_interconnect.v \
            rtl/interconnect/axi_interconnect_wrap_3x15.v \
            rtl/interconnect/axi_width_adapter.sv \
            ../pwm/src/rtl/axi_pwm_top.v \
            rtl/interconnect/tb_pwm_top.sv
	@echo ">>> Compiling PWM TB..."
	$(VCS) $(VCS_OPTS_PWM) -top $(TOP_PWM) -f run/pwm_runfile.f \
	    -o $(SIM_PWM) -l compile_pwm.log
	@echo ">>> Compilation done. Log: compile_pwm.log"

waves_pwm:
	@command -v gtkwave >/dev/null 2>&1 \
	    && gtkwave $(VCD_PWM) & \
	    || echo "GTKWave not found — open $(VCD_PWM) manually."

# ── Convenience ──────────────────────────────────────────
.PHONY: all sim_1x8 sim_2x8 sim_3x15 sim_soc sim_pwm \
        waves_1x8 waves_2x8 waves_soc waves_pwm clean

all: sim_1x8 sim_2x8 sim_3x15 sim_soc sim_pwm

clean:
	rm -rf simv_1x8 simv_1x8.daidir \
	       simv_2x8 simv_2x8.daidir \
	       simv_3x15 simv_3x15.daidir \
	       simv_soc  simv_soc.daidir \
	       simv_pwm  simv_pwm.daidir \
	       csrc \
	       compile_1x8.log compile_2x8.log compile_3x15.log \
	       compile_soc.log compile_pwm.log \
	       sim_1x8.log sim_2x8.log sim_3x15.log \
	       sim_soc.log sim_pwm.log \
	       $(VCD_1X8) $(VCD_2X8) $(VCD_PWM) \
	       *.vpd *.fsdb ucli.key vc_hdrs.h DVEfiles
	@echo ">>> Clean done."
