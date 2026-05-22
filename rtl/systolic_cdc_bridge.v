`timescale 1ns/1ps

// Systolic Array CDC Bridge (v2.0)
// Handles all signal crossings between AXI and compute domains.
// New in v2.0: precision_mode and clk_gate_en synchronizers.

module systolic_cdc_bridge #(
    parameter ADDR_WIDTH = 8
)(
    // AXI Clock Domain
    input  wire                   axi_clk,
    input  wire                   ext_rst_n,
    output wire                   axi_rst_n,

    // AXI → Core signals
    input  wire                   axi_start,
    input  wire [ADDR_WIDTH-1:0]  axi_k_dim,
    input  wire                   axi_precision_mode,
    input  wire                   axi_clk_gate_en,

    // Core → AXI signals (synchronized)
    output wire                   axi_done,
    output wire                   axi_busy,
    output wire [2:0]             axi_fsm_state,

    // Compute Core Clock Domain
    input  wire                   core_clk,
    output wire                   core_rst_n,

    // Core-domain outputs
    output wire                   core_start,
    output wire [ADDR_WIDTH-1:0]  core_k_dim,
    output wire                   core_precision_mode,
    output wire                   core_clk_gate_en,

    // Core-domain inputs
    input  wire                   core_done,
    input  wire                   core_busy,
    input  wire [2:0]             core_fsm_state
);

    // Reset Synchronizers
    cdc_reset_sync u_rst_axi (
        .dst_clk   (axi_clk),
        .ext_rst_n (ext_rst_n),
        .dst_rst_n (axi_rst_n)
    );

    cdc_reset_sync u_rst_core (
        .dst_clk   (core_clk),
        .ext_rst_n (ext_rst_n),
        .dst_rst_n (core_rst_n)
    );

    // AXI → Core: Start Pulse
    cdc_pulse_sync u_start_sync (
        .src_clk   (axi_clk),
        .src_rst_n (axi_rst_n),
        .src_pulse (axi_start),
        .dst_clk   (core_clk),
        .dst_rst_n (core_rst_n),
        .dst_pulse (core_start)
    );

    // AXI → Core: K_DIM (quasi-static)
    cdc_sync_2ff #(
        .WIDTH(ADDR_WIDTH),
        .RESET_VAL(0)
    ) u_kdim_sync (
        .dst_clk   (core_clk),
        .dst_rst_n (core_rst_n),
        .src_sig   (axi_k_dim),
        .dst_sig   (core_k_dim)
    );

    // AXI → Core: Precision Mode (quasi-static, set before start)
    cdc_sync_2ff #(
        .WIDTH(1),
        .RESET_VAL(0)
    ) u_precision_sync (
        .dst_clk   (core_clk),
        .dst_rst_n (core_rst_n),
        .src_sig   (axi_precision_mode),
        .dst_sig   (core_precision_mode)
    );

    // AXI → Core: Clock Gate Enable (quasi-static)
    cdc_sync_2ff #(
        .WIDTH(1),
        .RESET_VAL(0)
    ) u_clkgate_sync (
        .dst_clk   (core_clk),
        .dst_rst_n (core_rst_n),
        .src_sig   (axi_clk_gate_en),
        .dst_sig   (core_clk_gate_en)
    );

    // Core → AXI: Done (level)
    cdc_pulse_sync u_done_sync (
        .src_clk   (core_clk),
        .src_rst_n (core_rst_n),
        .src_pulse (core_done),
        .dst_clk   (axi_clk),
        .dst_rst_n (axi_rst_n),
        .dst_pulse (axi_done)
    );

    // Core → AXI: Busy (level)
    cdc_sync_2ff #(
        .WIDTH(1),
        .RESET_VAL(0)
    ) u_busy_sync (
        .dst_clk   (axi_clk),
        .dst_rst_n (axi_rst_n),
        .src_sig   (core_busy),
        .dst_sig   (axi_busy)
    );

    // Core → AXI: FSM State (debug, 3-bit)
    cdc_sync_2ff #(
        .WIDTH(3),
        .RESET_VAL(0)
    ) u_fsm_state_sync (
        .dst_clk   (axi_clk),
        .dst_rst_n (axi_rst_n),
        .src_sig   (core_fsm_state),
        .dst_sig   (axi_fsm_state)
    );

endmodule
