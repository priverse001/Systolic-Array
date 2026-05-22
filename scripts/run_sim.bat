@echo off
setlocal

REM Systolic Array - Command-Line Simulation Runner
REM Runs: golden_model.py -> xvlog -> xelab -> xsim
REM Must be run from: scripts/ directory
REM Requires: Vivado bin in PATH (use Vivado Developer Command Prompt)

echo  Parameterized Systolic Array - Simulation Runner
echo.

REM Step 1: Generate test vectors
echo [1/5] Generating test vectors with Python golden model...
python "%~dp0golden_model.py" --rows 128 --cols 128 --k_dim 128 --data_width 8 --out_dir "%~dp0..\data" --seed 128

if %ERRORLEVEL% neq 0 (
    echo ERROR: Python golden model failed!
    exit /b %ERRORLEVEL%
)
echo       Done.
echo.

REM Step 2: Prepare simulation working directory
echo [2/5] Preparing simulation directory...
if not exist "%~dp0..\sim" mkdir "%~dp0..\sim"

REM Copy hex files to sim directory (xsim working dir)
copy /Y "%~dp0..\data\matrix_a.hex" "%~dp0..\sim\" > nul
copy /Y "%~dp0..\data\matrix_b.hex" "%~dp0..\sim\" > nul
copy /Y "%~dp0..\data\matrix_c_expected.hex" "%~dp0..\sim\" > nul
echo       Hex files copied to sim/
echo.

REM Change to sim directory (xvlog/xelab/xsim work from here)
cd /d "%~dp0..\sim"

REM Step 3: Compile all Verilog sources
echo [3/5] Compiling Verilog sources with xvlog...
call xvlog "%~dp0..\rtl\pe.v" "%~dp0..\rtl\skew_ctrl.v" "%~dp0..\rtl\systolic_array.v" "%~dp0..\rtl\input_buffer.v" "%~dp0..\rtl\weight_buffer.v" "%~dp0..\rtl\output_buffer.v" "%~dp0..\rtl\accumulator.v" "%~dp0..\rtl\top_ctrl.v" "%~dp0..\rtl\systolic_top.v" "%~dp0..\tb\tb_pe.v" "%~dp0..\tb\tb_systolic_top.v"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Verilog compilation failed!
    exit /b %ERRORLEVEL%
)
echo       Compilation successful.
echo.

REM Step 4: Elaborate
echo [4/5] Elaborating design...
call xelab -debug typical -top tb_systolic_top -snapshot systolic_sim -log elaborate.log

if %ERRORLEVEL% neq 0 (
    echo ERROR: Elaboration failed! Check sim/elaborate.log
    exit /b %ERRORLEVEL%
)
echo       Elaboration successful.
echo.

REM Step 5: Run simulation
echo [5/5] Running simulation...
call xsim systolic_sim -runall -log simulate.log

echo.
echo  Simulation complete. Logs saved to sim/ directory.

cd /d "%~dp0"
endlocal
