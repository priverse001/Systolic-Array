# Parameterized Systolic Array

This project is a parameterized, RTL-level implementation of a systolic array designed for accelerating Matrix Multiplication (MatMul), commonly found in Deep Learning workloads (e.g., Transformer networks, CNNs). It is written in pure Verilog-2001 and verified using Vivado Simulator with a Python-based Golden Model.

## Project Structure

- `rtl/`: Contains the Verilog source files for the Processing Elements (PE), array core, buffers, skew controller, and top-level FSM.
- `tb/`: Contains the testbenches.
- `scripts/`: Contains Python scripts for golden model reference and batch scripts to run Vivado simulations.
- `docs/`: Additional architecture notes and interview preparation material.
- `data/`: Directory where test vectors are generated and read from.

## Quick Start (Vivado Simulator)

### 1. Generate Test Vectors
Ensure you have Python and NumPy installed. This will generate `matrix_a.hex`, `matrix_b.hex`, and `matrix_c_expected.hex` in the `data/` directory.

```bash
cd scripts
python golden_model.py --rows 4 --cols 4 --k_dim 4 --data_width 8 --out_dir ../data
```

### 2. Run Simulation
In a command prompt with Vivado environment variables sourced (e.g., Vivado Developer Command Prompt):

```cmd
cd scripts
run_sim.bat
```

The testbench (`tb_systolic_top.v`) will load the hex files into the host-facing buffers, start the array computation, wait for completion, and automatically verify the accumulated output against the expected Python output.

## Architecture Highlights
- **Weight / Output Stationary Hybrid:** Supports a pipelined MAC execution where activations stream horizontally and weights stream vertically. 
- **Skew Controller:** Precisely shifts data inputs in a staggered fashion, ensuring data arrives at the correct PE at the correct clock cycle.
- **DSP Mapping:** PEs explicitly map multiplication to DSP blocks (`use_dsp = "yes"`), preventing excessive LUT consumption and maintaining high Fmax.

See `docs/ARCHITECTURE.md` for a deeper dive into the dataflow.
