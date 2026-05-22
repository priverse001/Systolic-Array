# Vivado Project Setup Script for Parameterized Systolic Array
# Version : 2.1 (with AXI4-Stream, CDC, Tiling, Clock Gating)
# Usage   : Open Vivado Tcl Console, then run:
#             cd {path/to/systolic-array}
#             source scripts/create_project.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize "$script_dir/.."]

puts " Systolic Array - Vivado Project Builder v2.1"
puts " Project root: $project_dir"
puts ""

# 1. Clean Up Old Projects
foreach old_dir {systolic_array_project project_1.cache project_1.hw project_1.ip_user_files project_1.sim} {
    set p "$project_dir/$old_dir"
    if {[file exists $p]} {
        puts "  Removing old: $old_dir"
        file delete -force $p
    }
}
foreach old_xpr {project_1.xpr} {
    set p "$project_dir/$old_xpr"
    if {[file exists $p]} {
        file delete -force $p
    }
}

# 2. Create Vivado Project
create_project systolic_array_project "$project_dir/systolic_array_project" -part xc7vx485tffg1157-1

puts ""
puts " Adding RTL sources..."

# 3. RTL Sources — 20 modules organized by subsystem

# Processing Elements
set rtl_pe [list \
    "$project_dir/rtl/pe.v" \
    "$project_dir/rtl/pe_dual_mode.v" \
    "$project_dir/rtl/pe_clock_gate.v" \
]

# Systolic Array Core
set rtl_core [list \
    "$project_dir/rtl/systolic_array.v" \
    "$project_dir/rtl/skew_ctrl.v" \
    "$project_dir/rtl/input_buffer.v" \
    "$project_dir/rtl/weight_buffer.v" \
    "$project_dir/rtl/output_buffer.v" \
    "$project_dir/rtl/accumulator.v" \
    "$project_dir/rtl/top_ctrl.v" \
    "$project_dir/rtl/systolic_top.v" \
]

# AXI4 Integration
set rtl_axi [list \
    "$project_dir/rtl/axi4_lite_slave.v" \
    "$project_dir/rtl/axi4_stream_loader.v" \
    "$project_dir/rtl/tiling_ctrl.v" \
    "$project_dir/rtl/systolic_top_axi.v" \
]

# Clock Domain Crossing
set rtl_cdc [list \
    "$project_dir/rtl/cdc_sync_2ff.v" \
    "$project_dir/rtl/cdc_pulse_sync.v" \
    "$project_dir/rtl/cdc_reset_sync.v" \
    "$project_dir/rtl/systolic_cdc_bridge.v" \
    "$project_dir/rtl/systolic_top_cdc.v" \
]

# Combine all RTL and add
set all_rtl [concat $rtl_pe $rtl_core $rtl_axi $rtl_cdc]

# Verify each file exists before adding
set missing_files {}
foreach f $all_rtl {
    if {![file exists $f]} {
        lappend missing_files [file tail $f]
    }
}
if {[llength $missing_files] > 0} {
    puts "ERROR: Missing RTL files: $missing_files"
    puts "       Aborting project creation."
    return -code error "Missing RTL files"
}

add_files -norecurse $all_rtl
puts "  [llength $all_rtl] RTL files added."

# Synthesis top = dual-clock CDC version
set_property top systolic_top_cdc [current_fileset]

# 4. Simulation Sources — 4 testbenches
puts " Adding simulation sources..."

set all_tb [list \
    "$project_dir/tb/tb_pe.v" \
    "$project_dir/tb/tb_systolic_top.v" \
    "$project_dir/tb/tb_systolic_top_axi.v" \
    "$project_dir/tb/tb_systolic_top_cdc.v" \
]

foreach f $all_tb {
    if {![file exists $f]} {
        puts "WARNING: Missing testbench: [file tail $f]"
    }
}

add_files -fileset sim_1 -norecurse $all_tb
puts "  [llength $all_tb] testbenches added."

# Default simulation top = CDC testbench
set_property top tb_systolic_top_cdc [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# 5. Hex Data Files (golden model test vectors)
puts " Adding data files..."

set hex_files [list \
    "$project_dir/data/matrix_a.hex" \
    "$project_dir/data/matrix_b.hex" \
    "$project_dir/data/matrix_c_expected.hex" \
]

set hex_exist 1
foreach f $hex_files {
    if {![file exists $f]} {
        set hex_exist 0
        break
    }
}

if {$hex_exist} {
    add_files -fileset sim_1 -norecurse $hex_files
    set_property file_type "Data Files" [get_files -of_objects [get_filesets sim_1] *.hex]
    puts "  3 hex data files added."
} else {
    puts "  WARNING: Hex files missing. Run: python scripts/golden_model.py"
}

# 6. Simulation Settings
set_property -name {xsim.simulate.runtime} -value {500us} -objects [get_filesets sim_1]

# 7. Update Compile Order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 8. Print Summary
puts ""
puts " Project created successfully!"
puts ""
puts " RTL Modules:    [llength $all_rtl] files"
puts " Testbenches:    [llength $all_tb] files"
puts " Data Files:     3 hex files"
puts ""
puts " Synthesis top:  systolic_top_cdc"
puts "   (dual-clock CDC + AXI4-Lite + clock gating)"
puts ""
puts " Module Hierarchy:"
puts "   systolic_top_cdc"
puts "     +-- axi4_lite_slave       (AXI4-Lite register map)"
puts "     +-- cdc_reset_sync  x2    (reset synchronizers)"
puts "     +-- systolic_cdc_bridge   (clock domain crossing)"
puts "     |     +-- cdc_pulse_sync  (start/done pulse sync)"
puts "     |     +-- cdc_sync_2ff    (k_dim, busy, state, etc.)"
puts "     +-- systolic_top          (compute core)"
puts "           +-- top_ctrl        (FSM controller)"
puts "           +-- input_buffer    (activation SRAM)"
puts "           +-- weight_buffer   (weight SRAM)"
puts "           +-- skew_ctrl       (diagonal skew network)"
puts "           +-- systolic_array  (PE grid + clock gate)"
puts "           |     +-- pe_clock_gate (ICG cell)"
puts "           |     +-- pe x(NxN)    (MAC units)"
puts "           +-- accumulator     (output accumulation)"
puts "           +-- output_buffer   (result SRAM)"
puts ""
puts " Available testbenches (set_property top <name> [get_filesets sim_1]):"
puts "   tb_systolic_top_cdc  - Dual-clock CDC + AXI (DEFAULT)"
puts "   tb_systolic_top_axi  - Single-clock AXI wrapper"
puts "   tb_systolic_top      - Basic compute-only"
puts "   tb_pe                - PE unit test"
