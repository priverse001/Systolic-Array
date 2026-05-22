`timescale 1ns/1ps

// Systolic Array Top — Dual-Clock with CDC + AXI4-Lite (v2.0)
// Adds AXI4-Stream, tiling, precision mode, and clock gating.

module systolic_top_cdc #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6
)(
    // Dual clocks
    input  wire                                axi_clk,
    input  wire                                core_clk,
    input  wire                                ext_rst_n,

    // AXI4-Lite Slave Interface (axi_clk domain)
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  wire [2:0]                          S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,

    output wire [1:0]                          S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  wire [2:0]                          S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,

    output wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_RDATA,
    output wire [1:0]                          S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY,

    // Data Plane (core_clk domain)
    input  wire                                host_we_a,
    input  wire [ADDR_WIDTH-1:0]               host_addr_a,
    input  wire [(ROWS*DATA_WIDTH)-1:0]        host_wdata_a,

    input  wire                                host_we_b,
    input  wire [ADDR_WIDTH-1:0]               host_addr_b,
    input  wire [(COLS*DATA_WIDTH)-1:0]        host_wdata_b,

    input  wire                                host_re_c,
    input  wire [ADDR_WIDTH-1:0]               host_addr_c,
    output wire [(ROWS*COLS*ACC_WIDTH)-1:0]    host_rdata_c
);

    // Domain-local resets
    wire axi_rst_n;
    wire core_rst_n;

    // AXI domain signals
    wire        axi_start_pulse;
    wire [ADDR_WIDTH-1:0] axi_k_dim;
    wire        axi_done;
    wire        axi_busy;
    wire [2:0]  axi_fsm_state;
    wire        axi_precision_mode;
    wire        axi_clk_gate_en;

    // Stream loader signals (axi domain — directly driven by AXI slave)
    wire        axi_stream_target;
    wire        axi_stream_enable;

    // Tiling signals (axi domain)
    wire        axi_tile_start;
    wire [15:0] axi_tile_k_full;
    wire        axi_tile_done;
    wire [7:0]  axi_tile_k_idx;

    // Core domain signals
    wire        core_start_pulse;
    wire [ADDR_WIDTH-1:0] core_k_dim;
    wire        core_done;
    wire        core_busy;
    wire [2:0]  core_fsm_state;
    wire        core_precision_mode;
    wire        core_clk_gate_en;

    // AXI4-Lite Slave (runs on axi_clk)
    axi4_lite_slave #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .ROWS(ROWS),
        .COLS(COLS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_axi_slave (
        .S_AXI_ACLK    (axi_clk),
        .S_AXI_ARESETN (axi_rst_n),
        .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID),
        .S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),
        .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID),
        .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID),
        .S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),
        .S_AXI_RVALID  (S_AXI_RVALID),
        .S_AXI_RREADY  (S_AXI_RREADY),
        .usr_start     (axi_start_pulse),
        .usr_k_dim     (axi_k_dim),
        .usr_done      (axi_done),
        .usr_busy      (axi_busy),
        .usr_fsm_state (axi_fsm_state),
        .usr_stream_target  (axi_stream_target),
        .usr_stream_enable  (axi_stream_enable),
        .usr_stream_a_done  (1'b0),  // Stream loaders not in CDC path (future)
        .usr_stream_b_done  (1'b0),
        .usr_tile_start     (axi_tile_start),
        .usr_tile_k_full    (axi_tile_k_full),
        .usr_tile_done      (axi_tile_done),
        .usr_tile_k_idx     (axi_tile_k_idx),
        .usr_precision_mode (axi_precision_mode),
        .usr_clk_gate_en    (axi_clk_gate_en)
    );

    // CDC Bridge (axi_clk <-> core_clk)
    systolic_cdc_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_cdc (
        .axi_clk            (axi_clk),
        .ext_rst_n          (ext_rst_n),
        .axi_rst_n          (axi_rst_n),
        .axi_start          (axi_start_pulse),
        .axi_k_dim          (axi_k_dim),
        .axi_precision_mode (axi_precision_mode),
        .axi_clk_gate_en    (axi_clk_gate_en),
        .axi_done           (axi_done),
        .axi_busy           (axi_busy),
        .axi_fsm_state      (axi_fsm_state),
        .core_clk           (core_clk),
        .core_rst_n         (core_rst_n),
        .core_start         (core_start_pulse),
        .core_k_dim         (core_k_dim),
        .core_precision_mode(core_precision_mode),
        .core_clk_gate_en   (core_clk_gate_en),
        .core_done          (core_done),
        .core_busy          (core_busy),
        .core_fsm_state     (core_fsm_state)
    );

    // Systolic Array Compute Core (runs on core_clk)
    systolic_top #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_core (
        .clk            (core_clk),
        .rst_n          (core_rst_n),
        .start          (core_start_pulse),
        .k_dim          (core_k_dim),
        .done           (core_done),
        .busy           (core_busy),
        .fsm_state      (core_fsm_state),
        .accumulate     (1'b0),
        .precision_mode (core_precision_mode),
        .clk_gate_en    (core_clk_gate_en),
        .host_we_a      (host_we_a),
        .host_addr_a    (host_addr_a),
        .host_wdata_a   (host_wdata_a),
        .host_we_b      (host_we_b),
        .host_addr_b    (host_addr_b),
        .host_wdata_b   (host_wdata_b),
        .host_re_c      (host_re_c),
        .host_addr_c    (host_addr_c),
        .host_rdata_c   (host_rdata_c)
    );

endmodule
