// =============================================================================
// pwm_runfile.f
//
// VCS -f filelist for the standalone PWM Generator testbench.
//
// Usage (from axi4-interconnect-3to15/):
//   vcs -full64 -sverilog +v2k -timescale=1ns/1ps \
//       -debug_access+all \
//       +incdir+../pwm/src/include \
//       -f run/pwm_runfile.f \
//       -top tb_pwm_top \
//       -o simv_pwm \
//       -l compile_pwm.log
//
// Or simply:
//   make sim_pwm
//
// File order matters for Verilog-2001 (non-SV) files; SV packages are
// compiled before the modules that use them.
// =============================================================================

// ── AXI Interconnect core files ─────────────────────────────────────────────
rtl/interconnect/priority_encoder.v
rtl/interconnect/arbiter.v
rtl/interconnect/axi_interconnect.v
rtl/interconnect/axi_interconnect_wrap_3x15.v

// ── AXI Width Adapter ────────────────────────────────────────────────────────
rtl/interconnect/axi_width_adapter.sv

// ── PWM Generator IP ─────────────────────────────────────────────────────────
../pwm/src/rtl/axi_pwm_top.v

// ── Testbench ────────────────────────────────────────────────────────────────
rtl/interconnect/tb_pwm_top.sv
