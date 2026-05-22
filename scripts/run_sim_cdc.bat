@echo off
setlocal

echo ============================================================
echo  Parameterized Systolic Array - 128x128 CDC Simulation
echo ============================================================

if not exist "%~dp0..\sim" mkdir "%~dp0..\sim"
copy /Y "%~dp0..\data\matrix_a.hex" "%~dp0..\sim\" > nul
copy /Y "%~dp0..\data\matrix_b.hex" "%~dp0..\sim\" > nul
copy /Y "%~dp0..\data\matrix_c_expected.hex" "%~dp0..\sim\" > nul

cd /d "%~dp0..\sim"

echo Compiling Verilog sources...
call E:\Vivado\Vivado\2022.1\settings64.bat
call xvlog "%~dp0..\rtl\pe.v" "%~dp0..\rtl\skew_ctrl.v" "%~dp0..\rtl\systolic_array.v" "%~dp0..\rtl\input_buffer.v" "%~dp0..\rtl\weight_buffer.v" "%~dp0..\rtl\output_buffer.v" "%~dp0..\rtl\accumulator.v" "%~dp0..\rtl\top_ctrl.v" "%~dp0..\rtl\systolic_top.v" "%~dp0..\rtl\axi4_lite_slave.v" "%~dp0..\rtl\cdc_sync_2ff.v" "%~dp0..\rtl\cdc_pulse_sync.v" "%~dp0..\rtl\cdc_reset_sync.v" "%~dp0..\rtl\systolic_cdc_bridge.v" "%~dp0..\rtl\systolic_top_cdc.v" "%~dp0..\tb\tb_systolic_top_cdc.v"

echo Elaborating...
call xelab -debug typical -top tb_systolic_top_cdc -snapshot systolic_sim_cdc

echo Running...
call xsim systolic_sim_cdc -runall

cd /d "%~dp0"
endlocal
