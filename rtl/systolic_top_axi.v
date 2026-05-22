`timescale 1ns/1ps

// Systolic Array Top — AXI4-Lite Wrapper (v2.0)
// Integrates AXI4-Lite slave + tiling controller + stream loaders
// with the systolic compute core in a single clock domain.

module systolic_top_axi #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // AXI4-Lite Slave Interface
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

    // AXI4-Stream Slave — Input Buffer A loading
    input  wire [(ROWS*DATA_WIDTH)-1:0]        S_AXIS_A_TDATA,
    input  wire                                S_AXIS_A_TVALID,
    output wire                                S_AXIS_A_TREADY,
    input  wire                                S_AXIS_A_TLAST,

    // AXI4-Stream Slave — Weight Buffer B loading
    input  wire [(COLS*DATA_WIDTH)-1:0]        S_AXIS_B_TDATA,
    input  wire                                S_AXIS_B_TVALID,
    output wire                                S_AXIS_B_TREADY,
    input  wire                                S_AXIS_B_TLAST,

    // Data Plane (raw buffer interfaces, optional legacy)
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

    // AXI slave control signals
    wire        axi_start;
    wire [ADDR_WIDTH-1:0] axi_k_dim;
    wire        core_done;
    wire        core_busy;
    wire [2:0]  core_fsm_state;

    // Stream loader signals
    wire        stream_target, stream_enable;
    wire        stream_a_done, stream_b_done;
    wire        stream_a_we, stream_b_we;
    wire [ADDR_WIDTH-1:0] stream_a_addr, stream_b_addr;
    wire [(ROWS*DATA_WIDTH)-1:0] stream_a_wdata;
    wire [(COLS*DATA_WIDTH)-1:0] stream_b_wdata;

    // Tiling controller signals
    wire        tile_start, tile_done;
    wire [15:0] tile_k_full;
    wire [7:0]  tile_k_idx;
    wire        tile_core_start;
    wire        tile_accumulate;
    wire [ADDR_WIDTH-1:0] tile_k_dim_out;

    // Precision and clock gating
    wire        precision_mode;
    wire        clk_gate_en;

    // Mux: use tiling controller start if tile mode active, else direct AXI start
    wire core_start_mux  = (tile_k_full != 16'd0) ? tile_core_start : axi_start;
    wire core_accum_mux  = (tile_k_full != 16'd0) ? tile_accumulate : 1'b0;
    wire [ADDR_WIDTH-1:0] core_kdim_mux = (tile_k_full != 16'd0) ? tile_k_dim_out : axi_k_dim;

    // Buffer write mux: stream loader takes priority when enabled
    wire        eff_we_a    = stream_enable ? stream_a_we    : host_we_a;
    wire [ADDR_WIDTH-1:0] eff_addr_a = stream_enable ? stream_a_addr : host_addr_a;
    wire [(ROWS*DATA_WIDTH)-1:0] eff_wdata_a = stream_enable ? stream_a_wdata : host_wdata_a;

    wire        eff_we_b    = stream_enable ? stream_b_we    : host_we_b;
    wire [ADDR_WIDTH-1:0] eff_addr_b = stream_enable ? stream_b_addr : host_addr_b;
    wire [(COLS*DATA_WIDTH)-1:0] eff_wdata_b = stream_enable ? stream_b_wdata : host_wdata_b;

    // AXI4-Lite Slave
    axi4_lite_slave #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .ROWS(ROWS),
        .COLS(COLS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_axi_slave (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (rst_n),
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
        .usr_start     (axi_start),
        .usr_k_dim     (axi_k_dim),
        .usr_done      (core_done),
        .usr_busy      (core_busy),
        .usr_fsm_state (core_fsm_state),
        .usr_stream_target  (stream_target),
        .usr_stream_enable  (stream_enable),
        .usr_stream_a_done  (stream_a_done),
        .usr_stream_b_done  (stream_b_done),
        .usr_tile_start     (tile_start),
        .usr_tile_k_full    (tile_k_full),
        .usr_tile_done      (tile_done),
        .usr_tile_k_idx     (tile_k_idx),
        .usr_precision_mode (precision_mode),
        .usr_clk_gate_en    (clk_gate_en)
    );

    // AXI4-Stream Loader — Input Buffer A
    axi4_stream_loader #(
        .DATA_WIDTH_BUF(ROWS * DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_stream_a (
        .clk           (clk),
        .rst_n         (rst_n),
        .S_AXIS_TDATA  (S_AXIS_A_TDATA),
        .S_AXIS_TVALID (S_AXIS_A_TVALID),
        .S_AXIS_TREADY (S_AXIS_A_TREADY),
        .S_AXIS_TLAST  (S_AXIS_A_TLAST),
        .stream_enable (stream_enable & ~stream_target),
        .stream_done   (stream_a_done),
        .words_loaded  (),
        .buf_we        (stream_a_we),
        .buf_addr      (stream_a_addr),
        .buf_wdata     (stream_a_wdata)
    );

    // AXI4-Stream Loader — Weight Buffer B
    axi4_stream_loader #(
        .DATA_WIDTH_BUF(COLS * DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_stream_b (
        .clk           (clk),
        .rst_n         (rst_n),
        .S_AXIS_TDATA  (S_AXIS_B_TDATA),
        .S_AXIS_TVALID (S_AXIS_B_TVALID),
        .S_AXIS_TREADY (S_AXIS_B_TREADY),
        .S_AXIS_TLAST  (S_AXIS_B_TLAST),
        .stream_enable (stream_enable & stream_target),
        .stream_done   (stream_b_done),
        .words_loaded  (),
        .buf_we        (stream_b_we),
        .buf_addr      (stream_b_addr),
        .buf_wdata     (stream_b_wdata)
    );

    // Tiling Controller
    tiling_ctrl #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_tiling (
        .clk          (clk),
        .rst_n        (rst_n),
        .tile_start   (tile_start),
        .k_tile_size  (axi_k_dim),
        .k_full       (tile_k_full),
        .tile_done    (tile_done),
        .k_tile_idx   (tile_k_idx),
        .core_start   (tile_core_start),
        .core_done    (core_done),
        .accumulate   (tile_accumulate),
        .k_dim_out    (tile_k_dim_out)
    );

    // Systolic Array Compute Core
    systolic_top #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (core_start_mux),
        .k_dim          (core_kdim_mux),
        .done           (core_done),
        .busy           (core_busy),
        .fsm_state      (core_fsm_state),
        .accumulate     (core_accum_mux),
        .precision_mode (precision_mode),
        .clk_gate_en    (clk_gate_en),
        .host_we_a      (eff_we_a),
        .host_addr_a    (eff_addr_a),
        .host_wdata_a   (eff_wdata_a),
        .host_we_b      (eff_we_b),
        .host_addr_b    (eff_addr_b),
        .host_wdata_b   (eff_wdata_b),
        .host_re_c      (host_re_c),
        .host_addr_c    (host_addr_c),
        .host_rdata_c   (host_rdata_c)
    );

endmodule
