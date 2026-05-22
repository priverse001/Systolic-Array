# Interview Preparation Guide

This guide prepares you for hardware engineering, RTL design, and ASIC verification interviews at companies like Google, Apple, NVIDIA, and Qualcomm — all referencing this project.

---

### 1. "Why did you use a Systolic Array instead of a standard CPU/GPU approach?"

**Answer:** Matrix multiplication is fundamentally bottlenecked by memory bandwidth ("The Memory Wall"). In a standard CPU, fetching operands from cache/RAM for every MAC wastes >60% of energy on data movement. A systolic array mitigates this by passing operands directly between PEs in a mesh — each element is loaded once and propagates through the entire row/column. This achieves near-100% MAC utilization and dramatically reduces DRAM accesses, which is why Google's TPU, Apple's Neural Engine, and NVIDIA's Tensor Cores all use systolic or systolic-like architectures.

---

### 2. "How did you verify your design?"

**Answer:** I used a three-tier verification strategy:
1. **Golden Model:** A Python/NumPy script generates random signed INT8 matrices and computes the expected result using `int64` intermediate arithmetic to prevent overflow. It outputs hex files for `$readmemh`.
2. **Self-Checking Testbenches:** The Verilog testbench loads the hex vectors, runs the FSM to completion, reads every output element, and compares bit-exactly against the golden reference. It reports PASS/FAIL with mismatch counts.
3. **Multi-Clock CDC Testbench:** A separate testbench drives two asynchronous clocks (100 MHz AXI, 250 MHz core) to stress-test the CDC synchronizers under realistic conditions.

---

### 3. "What happens when your matrix is larger than the 4×4 array?"

**Answer:** The architecture uses **tiling**. A 1024×1024 MatMul is partitioned into 4×4 sub-tiles. The control FSM feeds one tile at a time. For the K-dimension, the `accumulator` block keeps a running total of partial sums across tiles (via its `accumulate` input). The FSM schedules tiles sequentially, essentially implementing a triple-nested loop: for each (M-tile, N-tile, K-tile), load data, compute, and accumulate.

---

### 4. "Why did you add an AXI4-Lite interface?"

**Answer:** In any real SoC, hardware accelerators don't exist in isolation — they're controlled by a CPU via a standard bus protocol. AXI4-Lite is the industry standard for low-bandwidth control registers. My implementation provides:
- **CTRL register** with a write-1-to-pulse start mechanism.
- **STATUS register** for software polling of completion.
- **Performance counters** for total and compute-active cycles, which are essential for profiling and driver development.

This demonstrates that I understand how accelerators integrate into production SoC architectures, not just how to build the compute datapath.

---

### 5. "Explain your CDC strategy. What are the risks?"

**Answer:** The AXI bus and compute array run on independent clocks. I implemented three types of synchronizers:

1. **2-Flop Synchronizer** (for `done`, `busy`): Classic metastability mitigation. Both flops carry `ASYNC_REG` for same-slice placement. Only safe for level signals that change slowly relative to the destination clock.

2. **Toggle-Based Pulse Synchronizer** (for `start`): The source domain toggles a flip-flop on each pulse. The toggle crosses via 2FF, and an XOR edge-detector in the destination domain regenerates a single-cycle pulse. This guarantees no lost pulses, with the constraint that consecutive source pulses must be separated by at least 2 destination clock cycles.

3. **Reset Synchronizer** (async assert, sync deassert): The reset asserts immediately (asynchronous — no clock needed), but deasserts only after 2 rising edges of the destination clock. This prevents metastability on the critical deassertion edge.

**Risk I considered:** For `fsm_state` (3-bit), I use per-bit 2FF synchronization. This can produce transient invalid state encodings during transitions (e.g., state 3→4 might briefly read as 7). I accepted this because it's a debug register read by polling software — the CPU simply re-reads if the value looks inconsistent. For a safety-critical signal, I would use Gray coding or a handshake protocol instead.

---

### 6. "What was the most challenging RTL bug you encountered?"

**Answer:** The skew controller timing alignment. A systolic array relies on perfectly staggered data waves — if row 1 is not delayed by exactly 1 clock cycle relative to row 0, it multiplies with the wrong weights, corrupting the entire output matrix. The initial implementation used a Verilog `generate` loop with `[0 +: 0]` bit selects for the passthrough case (row 0), which is a zero-width illegal slice in Verilog-2001. This caused silent elaboration failures. I rewrote the skew controller with explicit special-casing for rows 0 and 1, and used proper shift register chains for rows ≥ 2.

Additionally, the FSM originally transitioned directly from IDLE to COMPUTE, missing the 1-cycle SRAM read latency of the buffers. The first data word arrived one cycle late, causing a systematic off-by-one error in all results. Adding the `PREFETCH` state fixed this.

---

### 7. "How would you extend this to a production-quality design?"

**Answer:** Several key additions:
1. **AXI4-Stream for data paths:** Replace raw buffer ports with TVALID/TREADY/TDATA handshaking for backpressure-aware DMA integration.
2. **Double buffering:** Load the next tile's data while the current tile computes.
3. **Tiling controller:** On-chip logic to manage the M×N×K tile loop automatically, removing the CPU from the inner loop.
4. **Mixed-precision:** Runtime-switchable INT8/INT16 modes via a configuration register.
5. **Formal verification:** Use property-based assertions (SVA) for protocol compliance checking on the AXI interface.
6. **Power management:** Clock gating on idle PEs and automatic clock shutdown when `done`.

---

### 8. "What DSP inference pragmas did you use and why?"

**Answer:** I used `(* use_dsp = "yes" *)` on the accumulator register inside the PE. This forces Vivado to map the `acc <= acc + (a_in * b_in)` pattern directly into a `DSP48E1` (7-series) or `DSP48E2` (UltraScale) hard macro. Without this, Vivado might infer LUT-based multipliers for small operand widths (8-bit), which would be functionally correct but:
- Use ~5× more LUT resources.
- Have worse timing due to longer combinational paths.
- Miss the dedicated fast carry chains inside the DSP block.

For a 4×4 array, this means 16 DSP blocks are used — well within the budget of even small FPGAs like the Zynq-7020 (80 DSPs available).
