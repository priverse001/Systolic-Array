# Changelog

All notable changes to this project are documented here.

---

## [2.0.0] — Current

### Added
- **AXI4-Lite slave** (`axi4_lite_slave.v`) with 7-register memory map
- **AXI4-Stream loader** (`axi4_stream_loader.v`) for DMA-style data ingestion
- **Clock Domain Crossing infrastructure**:
  - `cdc_sync_2ff.v` — 2-flop synchronizer with `ASYNC_REG` attribute
  - `cdc_pulse_sync.v` — Toggle-based pulse synchronizer for the `start` signal
  - `cdc_reset_sync.v` — Async-assert / sync-deassert reset synchronizer
  - `systolic_cdc_bridge.v` — Top-level CDC wrapper connecting AXI ↔ core domains
- **Dual-clock top module** `systolic_top_cdc.v` (synthesis top, 100 MHz AXI / 250 MHz core)
- **Tiling controller** `tiling_ctrl.v` for K-dimension partitioning
- **Dual-mode PE** `pe_dual_mode.v` for runtime INT8/INT16 precision switching
- **Clock-gated PE** `pe_clock_gate.v` with integrated cell clock gate (ICG)
- **CDC testbench** `tb_systolic_top_cdc.v` exercising async 100/250 MHz clocks
- **AXI testbench** `tb_systolic_top_axi.v` with register read/write + compute verification
- Performance counters: `PERF_TOTAL`, `PERF_COMPUTE` in AXI register map
- Pre-generated 8×8 test vectors in `data_8x8/` for larger-array testing
- `scripts/create_project.tcl` v2.1 — auto-creates Vivado project from source

### Changed
- `systolic_top.v` refactored to be a pure compute core (no AXI dependency)
- `top_ctrl.v` FSM extended with `PREFETCH` state to handle 1-cycle SRAM latency
- `accumulator.v` now supports tiled accumulation via `accumulate` input
- `skew_ctrl.v` rewritten with explicit passthrough for rows/cols 0 and 1 (fixes Verilog-2001 zero-width slice bug)

---

## [1.0.0] — Initial Release

### Added
- Parameterized N×N systolic array (`systolic_array.v`) using nested `generate` blocks
- Processing Element (`pe.v`) with DSP48 pragma and signed MAC
- Skew controller (`skew_ctrl.v`) for wavefront alignment
- Input, weight, and output SRAM buffers
- Master FSM controller (`top_ctrl.v`)
- Standalone top module `systolic_top.v`
- Basic integration testbench `tb_systolic_top.v`
- PE unit testbench `tb_pe.v`
- NumPy golden model `scripts/golden_model.py` for hex vector generation
- Self-checking testbenches with bit-exact PASS/FAIL output
- Pre-generated 4×4 test vectors in `data/`
