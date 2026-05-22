# Contributing

Thank you for your interest in contributing to this project!

## Getting Started

1. **Fork** the repository and create your branch from `main`.
2. Ensure your Verilog follows the **Verilog-2001** standard (no SystemVerilog syntax in RTL).
3. Run the simulation suite before submitting a PR to confirm nothing regresses.

## Simulation Check

```cmd
cd scripts
python golden_model.py --seed 42
run_sim.bat
```

All four testbenches (`tb_pe`, `tb_systolic_top`, `tb_systolic_top_axi`, `tb_systolic_top_cdc`) must report `*** PASS ***`.

## RTL Coding Style

- Use **`parameter`** (not `localparam`) for top-level configurable dimensions.
- All synchronous logic must use **active-low reset** (`rst_n`).
- Flip-flops must be clocked on the **positive edge** only.
- Include the `(* use_dsp = "yes" *)` pragma on any MAC accumulator.
- CDC signals must be synchronized with the appropriate primitive (`cdc_sync_2ff`, `cdc_pulse_sync`, `cdc_reset_sync`).

## Pull Request Checklist

- [ ] New RTL module added to `scripts/create_project.tcl`
- [ ] Corresponding testbench added or updated in `tb/`
- [ ] `docs/ARCHITECTURE.md` updated if the design changes
- [ ] No generated files committed (`.wdb`, `.jou`, `.log`, `.pb`, `*.bit`, etc.)

## Reporting Issues

Open an issue with:
- Vivado version
- OS and shell used
- Exact error message or simulation output
