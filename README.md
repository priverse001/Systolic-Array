<div align="center">

# ⚡ Parameterized Systolic Array — AI Tensor Accelerator

**A fully parameterized N×N systolic array for matrix multiplication, targeting deep learning inference workloads.**

Written in pure **Verilog-2001** · **AXI4-Lite** control plane · **Full CDC infrastructure** · Verified with **NumPy golden model** on Xilinx Vivado XSim

---

![Verilog](https://img.shields.io/badge/Language-Verilog--2001-blue?style=for-the-badge&logo=verilog)
![Vivado](https://img.shields.io/badge/Vivado-2022.1+-orange?style=for-the-badge)
![Target](https://img.shields.io/badge/Target-Virtex--7%20%7C%20Zynq-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)
![Status](https://img.shields.io/badge/Simulation-PASSING-brightgreen?style=for-the-badge)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Repository Structure](#-repository-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Test Data & Matrix Sizes](#-test-data--matrix-sizes)
- [Switching to 8×8 Mode](#-switching-to-8×8-mode)
- [Parameterization](#-parameterization)
- [AXI4-Lite Register Map](#-axi4-lite-register-map)
- [Testbench Suite](#-testbench-suite)
- [Simulation Output](#-simulation-output)
- [Synthesis Estimates](#-synthesis-estimates)
- [Module Hierarchy](#-module-hierarchy)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🔍 Overview

This project implements a **hardware-accelerated matrix multiplier** using the systolic array architecture — the same fundamental structure used in Google's TPU, Apple's Neural Engine, and NVIDIA's Tensor Cores.

The design computes `C = A × B` where A, B, and C are integer matrices, with the following key properties:

- Each **Processing Element (PE)** performs one Multiply-Accumulate (MAC) per clock cycle
- Operands **flow through** the PE mesh rather than being fetched from memory, eliminating the memory-bandwidth bottleneck
- The array is **fully parameterized** — change `ROWS`, `COLS`, and `DATA_WIDTH` at elaboration time with no RTL edits required
- Three **integration levels** are provided, from a bare compute core to a full dual-clock SoC-ready subsystem

```
  axi_clk (100 MHz)               core_clk (250 MHz)
  ┌───────────────────┐            ┌────────────────────────┐
  │  AXI4-Lite Slave  │            │  Systolic Compute Core │
  │  (7 registers)    │──CDC Brdg─▶│  skew → array → accum  │
  │  CTRL / STATUS    │◀──────────│  DSP48 MAC units        │
  │  PERF counters    │  2FF/Pulse │  Input/Weight/Output   │
  └───────────────────┘  sync     │  SRAMs                 │
                                   └────────────────────────┘
```

---

## ✨ Key Features

| Feature | Details |
|---------|---------|
| **Parameterized PE Array** | N×N grid, fully generated via `generate` blocks |
| **DSP48 Inference** | `(* use_dsp = "yes" *)` pragma maps every MAC to a hard DSP block |
| **Weight-Stationary Dataflow** | Weights loaded once; activations stream through rows |
| **Skew Controller** | Diagonal shift-register network for precise wavefront alignment |
| **AXI4-Lite Slave** | 7-register memory map (CTRL, STATUS, K_DIM, PERF counters, VERSION) |
| **Full CDC Infrastructure** | 2FF sync, toggle pulse sync, async-assert/sync-deassert reset sync |
| **Self-Checking Testbenches** | Bit-exact verification against Python/NumPy golden reference |
| **Three Integration Levels** | Standalone → AXI single-clock → AXI + dual-clock CDC |
| **K-Dimension Tiling** | Accumulator supports multi-tile operation for matrices larger than the array |
| **Clock Gating** | Integrated cell gate (ICG) on idle PEs for power reduction |
| **Dual Precision Mode** | Runtime-switchable INT8 / INT16 via `pe_dual_mode` |

---

## 🏗 Architecture

### Processing Element (PE)

Each PE is a single registered MAC unit:

```
  a_in ──▶[REG]──▶ a_out    (flows right)
  b_in ──▶[REG]──▶ b_out    (flows down)
            │
            ▼
     acc <= acc + (a_in × b_in)    (* use_dsp = "yes" *)
```

### 4×4 Array Interconnect

```
         b[0]    b[1]    b[2]    b[3]
          ↓       ↓       ↓       ↓
a[0] → [PE00] → [PE01] → [PE02] → [PE03]
          ↓       ↓       ↓       ↓
a[1] → [PE10] → [PE11] → [PE12] → [PE13]
          ↓       ↓       ↓       ↓
a[2] → [PE20] → [PE21] → [PE22] → [PE23]
          ↓       ↓       ↓       ↓
a[3] → [PE30] → [PE31] → [PE32] → [PE33]
```

### FSM Controller States

```
IDLE → PREFETCH → COMPUTE → WAIT → DRAIN → DONE → IDLE
         (1cy)   (K_DIM cy) (N+M-2)  (1cy)
```

| State | Duration | Action |
|-------|----------|--------|
| `IDLE` | — | Wait for `start` |
| `PREFETCH` | 1 cycle | Prime SRAM read pipeline |
| `COMPUTE` | `K_DIM` cycles | Stream data through skew → array |
| `WAIT` | `ROWS+COLS−2` cycles | Drain wavefront to last PE |
| `DRAIN` | 1 cycle | Latch all accumulator results |
| `DONE` | — | Assert `done`; wait for `start` deassert |

### Clock Domain Crossing Architecture

```
  axi_clk domain                    core_clk domain
  ┌──────────────────┐ CDC Bridge   ┌──────────────────┐
  │ AXI4-Lite Slave  │              │  systolic_top    │
  │                  │              │                  │
  │  start (pulse) ──┼──pulse_sync──┼──▶ start         │
  │  k_dim (static) ─┼──2ff_sync ──┼──▶ k_dim         │
  │                  │              │                  │
  │  done  ◀─────────┼──2ff_sync ──┼─── done          │
  │  busy  ◀─────────┼──2ff_sync ──┼─── busy          │
  │  state ◀─────────┼──2ff_sync ──┼─── fsm_state     │
  │                  │              │                  │
  │  ext_rst_n ──────┼─reset_sync──┼──▶ core_rst_n    │
  │            ──────┼─reset_sync──┼──▶ axi_rst_n     │
  └──────────────────┘              └──────────────────┘
```

---

## 📁 Repository Structure

```
systolic-array/
│
├── 📄 README.md                    ← You are here
├── 📄 LICENSE                      ← MIT License
├── 📄 CONTRIBUTING.md              ← Contribution guide
├── 📄 CHANGELOG.md                 ← Version history
├── 📄 .gitignore
│
├── rtl/                            ← Synthesizable Verilog (20 modules)
│   │
│   ├── ── Processing Elements ──
│   ├── pe.v                        ← MAC unit (DSP48 pragma)
│   ├── pe_dual_mode.v              ← INT8/INT16 switchable PE
│   ├── pe_clock_gate.v             ← Power-gated PE wrapper
│   │
│   ├── ── Compute Core ──
│   ├── systolic_array.v            ← N×N PE mesh (generate blocks)
│   ├── skew_ctrl.v                 ← Diagonal skew shift registers
│   ├── input_buffer.v              ← Activation SRAM (A matrix)
│   ├── weight_buffer.v             ← Weight SRAM (B matrix)
│   ├── output_buffer.v             ← Result SRAM (C matrix)
│   ├── accumulator.v               ← Per-element accumulator bank
│   ├── top_ctrl.v                  ← Master FSM (6 states)
│   ├── systolic_top.v              ← Standalone compute core
│   │
│   ├── ── AXI4 Integration ──
│   ├── axi4_lite_slave.v           ← AMBA AXI4-Lite slave (5 channels)
│   ├── axi4_stream_loader.v        ← AXI4-Stream data loader
│   ├── tiling_ctrl.v               ← K-dimension tile sequencer
│   ├── systolic_top_axi.v          ← Single-clock AXI wrapper
│   │
│   └── ── Clock Domain Crossing ──
│       ├── cdc_sync_2ff.v          ← 2-flop synchronizer (ASYNC_REG)
│       ├── cdc_pulse_sync.v        ← Toggle-based pulse synchronizer
│       ├── cdc_reset_sync.v        ← Async-assert / sync-deassert reset
│       ├── systolic_cdc_bridge.v   ← Full CDC bridge module
│       └── systolic_top_cdc.v      ← Dual-clock synthesis top
│
├── tb/                             ← Testbenches (4 files)
│   ├── tb_pe.v                     ← PE unit test (4 cases)
│   ├── tb_systolic_top.v           ← Basic integration test
│   ├── tb_systolic_top_axi.v       ← AXI register + compute test
│   └── tb_systolic_top_cdc.v       ← Dual-clock CDC test (100/250 MHz)
│
├── scripts/
│   ├── golden_model.py             ← NumPy reference + hex generator
│   ├── create_project.tcl          ← Vivado project creation (v2.1)
│   ├── run_sim.bat                 ← CLI simulation (basic + AXI)
│   └── run_sim_cdc.bat             ← CLI simulation (CDC dual-clock)
│
├── data/                           ← 4×4 test vectors (default, gitignored)
│   ├── matrix_a.hex                ← A[4×4] — 16 signed INT8 values
│   ├── matrix_b.hex                ← B[4×4] — 16 signed INT8 values
│   └── matrix_c_expected.hex       ← C[4×4] = A×B — 16 INT32 values
│
├── data_8x8/                       ← 8×8 test vectors (optional)
│   ├── matrix_a.hex                ← A[8×8] — 64 signed INT8 values
│   ├── matrix_b.hex                ← B[8×8] — 64 signed INT8 values
│   └── matrix_c_expected.hex       ← C[8×8] = A×B — 64 INT32 values
│
├── sim/                            ← XSim working directory
│   ├── matrix_a.hex                ← Copied here by run_sim.bat
│   ├── matrix_b.hex
│   ├── matrix_c_expected.hex
│   └── run_sim.tcl
│
├── systolic_array_project/         ← Vivado simulation project (DO NOT DELETE)
│   └── systolic_array_project.xpr ← Open this in Vivado to run GUI simulation
│
└── docs/
    ├── ARCHITECTURE.md             ← Full microarchitecture documentation
    ├── INTERVIEW_PREP.md           ← RTL interview Q&A (8 questions)
    ├── project_report.pdf          ← Full PDF design report
    ├── project_report.tex          ← LaTeX source
    └── Systolic_Array_PRD.docx     ← Product Requirements Document
```

---

## 🔧 Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Xilinx Vivado](https://www.xilinx.com/support/download.html) | 2020.1+ (tested 2022.1) | Synthesis, simulation |
| Python 3 | 3.7+ | Golden model / test vector generation |
| NumPy | any | Matrix computation in golden model |

Install NumPy:
```cmd
pip install numpy
```

---

## 🚀 Quick Start

### Option A — Vivado GUI (Recommended)

#### Step 1 — Generate test vectors
```cmd
cd "path\to\systolic-array\scripts"
python golden_model.py --rows 4 --cols 4 --k_dim 4 --data_width 8 --seed 42
```
This writes `matrix_a.hex`, `matrix_b.hex`, and `matrix_c_expected.hex` to the `data/` folder.

#### Step 2 — Open the pre-built Vivado project
The project is already set up. Simply open Vivado and load:
```
systolic_array_project/systolic_array_project.xpr
```
Or create a fresh project from the TCL script (in the Vivado Tcl Console):
```tcl
cd {path/to/systolic-array}
source scripts/create_project.tcl
```

#### Step 3 — Run simulation
In the Vivado Flow Navigator:
1. Click **Run Simulation → Run Behavioral Simulation**
2. The default testbench is `tb_systolic_top_cdc` (dual-clock CDC)

To switch testbench, in the Tcl Console:
```tcl
# Basic compute-only
set_property top tb_systolic_top [get_filesets sim_1]

# AXI single-clock
set_property top tb_systolic_top_axi [get_filesets sim_1]

# PE unit test
set_property top tb_pe [get_filesets sim_1]
```

---

### Option B — Command-Line (Windows)

Make sure Vivado is on your `PATH` (use the **Vivado Developer Command Prompt**):

```cmd
cd "path\to\systolic-array\scripts"
python golden_model.py --seed 42
run_sim.bat
```

---

## 📊 Test Data & Matrix Sizes

Two sets of pre-generated test vectors are included:

| Directory | Matrix Size | Files | Use Case |
|-----------|------------|-------|---------|
| `data/` | **4×4** (default) | `matrix_a.hex` (16 entries), `matrix_b.hex` (16 entries), `matrix_c_expected.hex` (16 entries) | All testbenches as shipped |
| `data_8x8/` | **8×8** | `matrix_a.hex` (64 entries), `matrix_b.hex` (64 entries), `matrix_c_expected.hex` (64 entries) | Larger array validation |

> **Note:** The `data/` directory is listed in `.gitignore` since the vectors are fully reproducible via `golden_model.py`. The `data_8x8/` vectors are committed as a convenience for 8×8 testing without requiring Python.

You can regenerate vectors for any size at any time:
```cmd
python scripts/golden_model.py --rows 4 --cols 4 --k_dim 4 --seed 42   # 4×4
python scripts/golden_model.py --rows 8 --cols 8 --k_dim 8 --seed 42   # 8×8
```

---

## 🔄 Switching to 8×8 Mode

The testbenches default to a **4×4 array** (`ROWS=4, COLS=4, K_DIM=4`). To run a full **8×8 simulation**, follow these three steps:

### Step 1 — Copy 8×8 hex vectors to the sim working directory

```cmd
copy /Y data_8x8\matrix_a.hex         sim\
copy /Y data_8x8\matrix_b.hex         sim\
copy /Y data_8x8\matrix_c_expected.hex sim\
```

### Step 2 — Edit the testbench parameters

Open the desired testbench in `tb/` and change the top-level parameters:

```verilog
// tb/tb_systolic_top.v  (or tb_systolic_top_axi.v / tb_systolic_top_cdc.v)

// ── Change these three lines ──────────────────────────
parameter ROWS       = 8;   // was 4
parameter COLS       = 8;   // was 4
parameter K_DIM      = 8;   // was 4
// ─────────────────────────────────────────────────────

// DATA_WIDTH and ACC_WIDTH stay the same
parameter DATA_WIDTH = 8;
parameter ACC_WIDTH  = 32;
parameter ADDR_WIDTH = 8;
```

### Step 3 — Update the RTL top parameters (if using Vivado GUI)

In the Vivado Tcl Console, override the parameters during elaboration:
```tcl
set_property generic {ROWS=8 COLS=8} [get_filesets sim_1]
```

Or simply edit the `parameter` defaults in `rtl/systolic_top.v`:
```verilog
module systolic_top #(
    parameter ROWS       = 8,   // was 4
    parameter COLS       = 8,   // was 4
    ...
```

### Step 4 — Re-run simulation

The testbench will now load the 64-entry hex files and verify all 64 output elements of the 8×8 result matrix.

> **Tip:** You can generate 8×8 fresh vectors anytime with:
> ```cmd
> python scripts/golden_model.py --rows 8 --cols 8 --k_dim 8 --seed 42 --out_dir data_8x8
> ```

---

## ⚙️ Parameterization

All parameters cascade from the top-level modules. Change them in one place — the entire hierarchy adapts automatically.

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `ROWS` | `4` | 1–256 | Number of PE array rows (output matrix M dimension) |
| `COLS` | `4` | 1–256 | Number of PE array columns (output matrix N dimension) |
| `DATA_WIDTH` | `8` | 4–16 | Input operand width in bits (INT8 default) |
| `ACC_WIDTH` | `32` | 16–64 | Accumulator register width (must be ≥ 2×DATA_WIDTH + log2(K_DIM)) |
| `ADDR_WIDTH` | `8` | 4–16 | SRAM address width (buffer depth = 2^ADDR_WIDTH) |

**Resource scaling:** Each PE maps to one DSP48 block. An N×N array uses **N² DSP48s**. A Zynq-7020 has 220 DSP48s, comfortably fitting a 14×14 array.

---

## 🗺 AXI4-Lite Register Map

Base address is design-specific (configured in your address map). All registers are 32-bit wide.

| Offset | Name | Access | Reset | Description |
|--------|------|--------|-------|-------------|
| `0x00` | `CTRL` | W | `0x0` | `[0]` start — write-1-to-pulse, auto-clears next cycle |
| `0x04` | `STATUS` | R | `0x0` | `[0]` done · `[1]` busy · `[4:2]` FSM state (0–5) |
| `0x08` | `K_DIM` | RW | `0x4` | Inner-loop dimension (number of accumulation steps) |
| `0x0C` | `ARRAY_CFG` | R | hardwired | `[15:8]` COLS · `[7:0]` ROWS (read-only hardware constant) |
| `0x10` | `PERF_TOTAL` | R | `0x0` | Total clock cycles from start assertion to done assertion |
| `0x14` | `PERF_COMPUTE` | R | `0x0` | Cycles where FSM was actively computing (busy=1) |
| `0x18` | `VERSION` | R | `0x00020000` | Design version register |

### Software Driver Flow

```c
// Pseudo-code — adapt to your HAL
axi_write(BASE + 0x08, K_DIM);         // Set K dimension
axi_write(BASE + 0x00, 0x1);           // Pulse start
while (!(axi_read(BASE + 0x04) & 0x1)) // Poll done bit
    ;
uint32_t cycles = axi_read(BASE + 0x10); // Read perf counter
```

---

## 🧪 Testbench Suite

| Testbench | DUT | Clock Setup | What It Tests |
|-----------|-----|------------|---------------|
| `tb_pe` | `pe` | 100 MHz single | 4 unit tests: single MAC, accumulation, data forwarding, reset clear |
| `tb_systolic_top` | `systolic_top` | 100 MHz single | Full pipeline: load buffers → compute → verify all C[i][j] |
| `tb_systolic_top_axi` | `systolic_top_axi` | 100 MHz single | AXI register read/write, VERSION/ARRAY_CFG checks, compute + verify |
| `tb_systolic_top_cdc` | `systolic_top_cdc` | AXI=100 MHz, Core=250 MHz | Full dual-clock CDC: pulse sync, 2FF sync, reset sync, compute verify |

All system-level testbenches use the same self-checking flow:
1. `$readmemh` loads the golden hex vectors
2. Buffers are written, K_DIM configured, start pulsed
3. FSM runs to completion (`done` asserted)
4. Every element of the output matrix is compared against the Python reference
5. Detailed PASS/FAIL with mismatch count is printed

---

## 📟 Simulation Output

### Expected CDC Testbench Output (`tb_systolic_top_cdc`)

```
CDC Testbench: axi_clk=100MHz, core_clk=250MHz
[AXI] VERSION = 0x00020000
[TB] Loading buffers (core_clk domain)...
[AXI] Writing K_DIM = 4
[AXI] Writing CTRL = 1 (start pulse)
[AXI] Polling STATUS for done...
[AXI] STATUS = 0x00000021 (done=1, busy=0, state=5) after N polls
[AXI] PERF_TOTAL   = ... axi_clk cycles
[AXI] PERF_COMPUTE = ... axi_clk cycles

[ PASS ] CDC SIMULATION PASSED! Clocks: axi=100MHz, core=250MHz
```

### Expected AXI Testbench Output (`tb_systolic_top_axi`)

```
[AXI] VERSION  = 0x00020000 (expected 0x00020000)
[AXI] ARRAY_CFG = 0x00000404 (COLS=4, ROWS=4)
[TB] Loading Input Buffer A...
[TB] Loading Weight Buffer B...
[AXI] Writing K_DIM = 4
[AXI] Writing CTRL = 1 (start)
[AXI] Polling STATUS register...
[AXI] PERF_TOTAL   = ... cycles
[AXI] PERF_COMPUTE = ... cycles

[ PASS ] AXI SIMULATION PASSED!
```

---

## 📐 Synthesis Estimates

Targeting **Virtex-7 xc7vx485t** (via `scripts/create_project.tcl`). Estimates for default 4×4, INT8 configuration:

| Resource | Estimated | Available (VX485T) | % Used |
|----------|-----------|-------------------|--------|
| DSP48E1 | **16** (1 per PE) | 2,800 | < 1% |
| BRAM (36K) | **3** (input + weight + output) | 1,030 | < 1% |
| LUTs | ~2,000 (FSM + skew + CDC + AXI) | 303,600 | < 1% |
| Flip-Flops | ~1,500 (sync + pipeline stages) | 607,200 | < 1% |

**Fmax:** The DSP48 chain is the critical path. Expected Fmax ~400–500 MHz on Virtex-7; ~250 MHz on Zynq-7020.

---

## 🌲 Module Hierarchy

```
systolic_top_cdc                    ← Synthesis top (dual-clock)
 ├── axi4_lite_slave                ← AXI4-Lite 5-channel slave
 ├── cdc_reset_sync  × 2           ← Reset sync (axi_clk, core_clk)
 └── systolic_cdc_bridge            ← All clock-domain crossings
      ├── cdc_pulse_sync            ← start pulse (AXI→core)
      └── cdc_sync_2ff  × N        ← done/busy/state/k_dim (core→AXI)
 └── systolic_top                   ← Pure compute core
      ├── top_ctrl                  ← Master FSM (6 states)
      ├── input_buffer              ← Activation SRAM (A)
      ├── weight_buffer             ← Weight SRAM (B)
      ├── skew_ctrl                 ← Diagonal skew network
      ├── systolic_array            ← ROWS×COLS PE mesh
      │    ├── pe_clock_gate  × 1  ← Integrated cell gate
      │    └── pe  × (ROWS×COLS)   ← MAC units
      ├── accumulator               ← Result latch bank
      └── output_buffer             ← Result SRAM (C)
```

---

## 📚 Documentation

| Document | Location | Description |
|----------|----------|-------------|
| Architecture Guide | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Deep-dive: PE, skew, FSM, AXI, CDC, verification methodology, synthesis notes |
| Design Report (PDF) | [`docs/project_report.pdf`](docs/project_report.pdf) | Full project report with waveforms and analysis |
| Changelog | [`CHANGELOG.md`](CHANGELOG.md) | Version history (v1.0 → v2.0) |

---

## 🤝 Contributing

Contributions are welcome! Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a PR. The short version:

1. Fork → branch → code → test → PR
2. All four testbenches must report `*** PASS ***`
3. No generated files (`.wdb`, `.log`, `.jou`, `.pb`) should be committed
4. RTL must target Verilog-2001 (no SystemVerilog in `rtl/`)

---

## 📄 License

This project is licensed under the **MIT License** — see the [`LICENSE`](LICENSE) file for details.

---

<div align="center">

**Built to demonstrate production-quality RTL design practices**  
*Systolic dataflow · AXI4-Lite integration · CDC infrastructure · Self-checking verification*

</div>
