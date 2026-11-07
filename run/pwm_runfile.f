// =============================================================================
// pwm_runfile.f
//
// VCS -f filelist for the standalone PWM Generator testbench.
// =============================================================================

// ── AXI Interconnect core files ─────────────────────────────────────────────
rtl/priority_encoder.v
rtl/arbiter.v
rtl/axi_interconnect.v
rtl/axi_interconnect_wrap_3x15.v

// ── AXI Width Adapter ────────────────────────────────────────────────────────
rtl/axi_width_adapter.sv

// ── PWM Generator IP ─────────────────────────────────────────────────────────
rtl/pwm/src/rtl/axi_pwm_top.v

// ── Testbench ────────────────────────────────────────────────────────────────
rtl/tb_pwm_top.sv
