# Architecture Document — Parameterized Systolic Array

## 1. Overview

This project implements a fully parameterized N×N systolic array for matrix multiplication, targeting deep-learning inference workloads. The design is written in pure Verilog-2001 and includes three progressive integration levels:

| Level | Top Module | Description |
|-------|-----------|-------------|
| **Basic** | `systolic_top` | Standalone compute core with raw buffer I/O |
| **AXI4-Lite** | `systolic_top_axi` | Single-clock, with CPU-accessible register interface |
| **CDC + AXI** | `systolic_top_cdc` | Dual-clock, with full clock-domain-crossing infrastructure |

---

## 2. Compute Core Architecture

### 2.1 Processing Element (PE)

Each PE performs a single Multiply-Accumulate (MAC) operation per clock cycle:

```
acc <= acc + (a_in × b_in)
```

- **DSP Mapping:** The `(* use_dsp = "yes" *)` pragma forces Xilinx tools to infer a `DSP48E1/E2` hard macro, saving LUTs and improving Fmax.
- **Data Forwarding:** Each PE registers its inputs (`a_in`, `b_in`) and passes them to the adjacent PE (right and down, respectively) on the next clock cycle. This creates the systolic data flow.
- **Signed Arithmetic:** Both inputs and the accumulator use `signed` types for correct two's-complement operation.

### 2.2 Systolic Array (N×N PE Mesh)

The `systolic_array` module instantiates a ROWS × COLS grid of PEs using nested `generate` blocks.

**Interconnect topology:**
```
        b_in[0]  b_in[1]  b_in[2]  b_in[3]
           ↓        ↓        ↓        ↓
a_in[0] → [PE00] → [PE01] → [PE02] → [PE03] → a_out[0]
           ↓        ↓        ↓        ↓
a_in[1] → [PE10] → [PE11] → [PE12] → [PE13] → a_out[1]
           ↓        ↓        ↓        ↓
a_in[2] → [PE20] → [PE21] → [PE22] → [PE23] → a_out[2]
           ↓        ↓        ↓        ↓
a_in[3] → [PE30] → [PE31] → [PE32] → [PE33] → a_out[3]
           ↓        ↓        ↓        ↓
        b_out[0] b_out[1] b_out[2] b_out[3]
```

- **Activations (a):** Flow left-to-right.
- **Weights (b):** Flow top-to-bottom.
- **Accumulations:** Remain local within each PE until drained.

### 2.3 Skew Controller

For correct wavefront alignment, row `i` must be delayed by `i` cycles and column `j` by `j` cycles. The `skew_ctrl` module implements this using parameterized shift register chains:

- **Row 0 / Col 0:** Direct passthrough (zero delay).
- **Row 1 / Col 1:** Single flip-flop (1-cycle delay).
- **Row i / Col j (≥2):** Chain of `i` or `j` flip-flops via generate loop.

This ensures PE[i][j] receives its operands at exactly the right time.

### 2.4 Master FSM (`top_ctrl`)

The controller manages the compute lifecycle through six states:

```
IDLE → PREFETCH → COMPUTE → WAIT → DRAIN → DONE → IDLE
```

| State | Cycles | Action |
|-------|--------|--------|
| `IDLE` | — | Wait for `start` signal |
| `PREFETCH` | 1 | Issue first buffer read (1-cycle SRAM latency) |
| `COMPUTE` | K_DIM | Feed data to skew controller; pipeline buffer reads |
| `WAIT` | ROWS+COLS−2 | Pipeline drain; wavefront propagates to PE[N-1][N-1] |
| `DRAIN` | 1 | Pulse `drain_valid` to latch accumulator results |
| `DONE` | — | Assert `done`; wait for `start` to deassert |

### 2.5 Memory Buffers

Three single-port SRAMs provide data staging:

| Buffer | Width | Depth | Purpose |
|--------|-------|-------|---------|
| `input_buffer` | ROWS × DATA_WIDTH | 2^ADDR_WIDTH | Activation matrix (A) |
| `weight_buffer` | COLS × DATA_WIDTH | 2^ADDR_WIDTH | Weight matrix (B) |
| `output_buffer` | ROWS × COLS × ACC_WIDTH | 2^ADDR_WIDTH | Result matrix (C) |

### 2.6 Accumulator Bank

Captures PE results on `drain_valid`. Supports two modes:
- **Overwrite** (`accumulate=0`): Direct latch for single-tile operation.
- **Accumulate** (`accumulate=1`): Adds to existing stored value for K-dimension tiling.

---

## 3. AXI4-Lite Integration

### 3.1 Bus Interface (`axi4_lite_slave`)

Implements the full AMBA AXI4-Lite protocol (5 channels: AW, W, B, AR, R) following Xilinx coding conventions. The slave provides a memory-mapped register bank for CPU control.

### 3.2 Register Map

| Address | Name | Access | Description |
|---------|------|--------|-------------|
| `0x00` | CTRL | W | `[0]` start — write-1-to-pulse, auto-clears |
| `0x04` | STATUS | R | `[0]` done, `[1]` busy, `[4:2]` fsm_state |
| `0x08` | K_DIM | RW | Inner loop dimension |
| `0x0C` | ARRAY_CFG | R | `[15:8]` COLS, `[7:0]` ROWS (hardwired) |
| `0x10` | PERF_TOTAL | R | Total clock cycles from start to done |
| `0x14` | PERF_COMPUTE | R | Active compute cycles only |
| `0x18` | VERSION | R | Design version `0x00010000` |

### 3.3 Performance Counters

Two hardware counters run in the AXI clock domain:
- **PERF_TOTAL:** Increments every cycle from start to done.
- **PERF_COMPUTE:** Increments only when `busy=1` (FSM is actively computing, not idle/done).

---

## 4. Clock Domain Crossing (CDC)

### 4.1 Motivation

In a real SoC, the CPU/AXI bus and the compute array typically run on different clocks:
- **AXI clock:** ~100 MHz (matches CPU/interconnect).
- **Compute clock:** ~250–500 MHz (maximizes throughput).

The CDC infrastructure enables safe operation across these asynchronous domains.

### 4.2 CDC Primitives

| Module | Type | Use Case |
|--------|------|----------|
| `cdc_sync_2ff` | 2-Flop Synchronizer | Level signals: `done`, `busy`, `fsm_state`, `k_dim` |
| `cdc_pulse_sync` | Toggle-based Pulse Sync | Single-cycle pulses: `start` |
| `cdc_reset_sync` | Async Assert / Sync Deassert | Reset: generates clean `rst_n` in each domain |

All synchronizer flip-flops carry the `(* ASYNC_REG = "TRUE" *)` attribute, which instructs Vivado to place both flops in the same slice for minimal routing delay, reducing MTBF (Mean Time Between Failures due to metastability).

### 4.3 Signal Crossing Strategy

```
   AXI Clock Domain                    Core Clock Domain
  ┌──────────────────┐  CDC Bridge   ┌──────────────────┐
  │ AXI4-Lite Slave  │              │ Systolic Core     │
  │                  │              │                   │
  │  start (pulse) ──┼──pulse_sync──┼──► start          │
  │  k_dim (static) ─┼──2ff_sync───┼──► k_dim          │
  │                  │              │                   │
  │  done ◄──────────┼──2ff_sync───┼─── done            │
  │  busy ◄──────────┼──2ff_sync───┼─── busy            │
  │  fsm_state ◄─────┼──2ff_sync───┼─── fsm_state      │
  │                  │              │                   │
  │  ext_rst_n ──────┼─reset_sync──┼──► core_rst_n     │
  │            ──────┼─reset_sync──┼──► axi_rst_n      │
  └──────────────────┘              └──────────────────┘
```

**Safety rationale for each crossing:**
- **start:** Single-cycle pulse → toggle-based synchronizer (guarantees no lost pulses).
- **k_dim:** Quasi-static — written before `start`, does not change during computation → safe with 2FF per bit.
- **done, busy:** Level signals that change slowly → standard 2FF synchronizer.
- **fsm_state:** 3-bit debug register, read by software that can tolerate a momentary glitch → 2FF per bit (acceptable for status polling).
- **Performance counters:** Read only when `done=1`, meaning the values are stable → no synchronizer needed on data, only on the `done` flag.

### 4.4 Architecture Block Diagram

```
  ┌──────────────────────────────────────────────────────┐
  │  axi_clk domain                                      │
  │  ┌─────────────────┐                                 │
  │  │ AXI4-Lite Slave │◄── CPU / Interconnect           │
  │  └────────┬────────┘                                 │
  │           │ (registers)                              │
  │  ┌────────▼────────┐                                 │
  │  │   CDC Bridge    │ 2FF, Pulse Sync, Reset Sync     │
  │  └────────┬────────┘                                 │
  ├───────────┼──────────────────────────────────────────┤
  │  core_clk │ domain                                   │
  │  ┌────────▼────────┐                                 │
  │  │  systolic_top   │ buffers → skew → array → acc    │
  │  └─────────────────┘                                 │
  └──────────────────────────────────────────────────────┘
```

---

## 5. Verification Methodology

### 5.1 Golden Model (`golden_model.py`)

- Generates random signed INT8 matrices A[ROWS×K] and B[K×COLS].
- Computes `C = A @ B` using `int64` intermediate precision to prevent overflow.
- Outputs hex files (`$readmemh` format) for Verilog testbench consumption.
- Deterministic via `--seed` flag for reproducible CI.

### 5.2 Testbench Hierarchy

| Testbench | Scope | Clock Setup |
|-----------|-------|-------------|
| `tb_pe` | Unit: single PE MAC, forwarding, reset | Single clock, 100 MHz |
| `tb_systolic_top` | Integration: full compute pipeline | Single clock, 100 MHz |
| `tb_systolic_top_axi` | AXI register read/write + compute | Single clock, 100 MHz |
| `tb_systolic_top_cdc` | Full dual-clock CDC exercise | AXI=100 MHz, Core=250 MHz |

### 5.3 Self-Checking Flow

All system-level testbenches:
1. Load hex vectors via `$readmemh`.
2. Write buffers, configure K_DIM, assert start.
3. Wait for `done` (direct or via AXI STATUS polling).
4. Read output buffer and compare every element against the golden reference.
5. Report PASS/FAIL with mismatch count.

---

## 6. Synthesis & Implementation

### 6.1 Resource Expectations (4×4, 8-bit, Virtex-7)

| Resource | Expected Usage |
|----------|---------------|
| DSP48E1 | 16 (one per PE) |
| BRAM | 3 (input, weight, output buffers) |
| LUTs | ~2000 (FSM, skew, CDC, AXI) |
| Flip-Flops | ~1500 (synchronizers, pipelines) |

### 6.2 Fmax Considerations

- DSP48 blocks are the timing bottleneck at ~500 MHz on Virtex-7.
- The CDC path adds 2 flip-flop stages (~1 ns), well within typical margins.
- The AXI4-Lite slave uses registered outputs, ensuring clean timing closure.

---

## 7. Memory & Tiling (Future)

The current implementation handles a single N×N tile. For matrices larger than the array size:

1. Partition the K-dimension into chunks of K_DIM.
2. For each chunk, load a new set of A/B data, compute, and accumulate (`accumulate=1`).
3. After all K-chunks, drain the final result.

This requires a host-side double-loop or an on-chip tiling controller (not yet implemented).
