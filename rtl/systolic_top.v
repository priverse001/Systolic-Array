`timescale 1ns/1ps

module systolic_top #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 8
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Host interface
    input  wire                                start,
    input  wire [ADDR_WIDTH-1:0]               k_dim,
    output wire                                done,
    output wire                                busy,
    output wire [2:0]                           fsm_state,
    input  wire                                accumulate,
    input  wire                                precision_mode,
    input  wire                                clk_gate_en,
    
    // Host memory interface (Input Buffer)
    input  wire                                host_we_a,
    input  wire [ADDR_WIDTH-1:0]               host_addr_a,
    input  wire [(ROWS*DATA_WIDTH)-1:0]        host_wdata_a,
    
    // Host memory interface (Weight Buffer)
    input  wire                                host_we_b,
    input  wire [ADDR_WIDTH-1:0]               host_addr_b,
    input  wire [(COLS*DATA_WIDTH)-1:0]        host_wdata_b,
    
    // Host memory interface (Output Buffer)
    input  wire                                host_re_c,
    input  wire [ADDR_WIDTH-1:0]               host_addr_c,
    output wire [(ROWS*COLS*ACC_WIDTH)-1:0]    host_rdata_c
);

    // Controller signals
    wire buf_re;
    wire [ADDR_WIDTH-1:0] buf_raddr;
    wire array_valid;
    wire drain_valid;
    
    // Buffer output to Skew Controller
    wire [(ROWS*DATA_WIDTH)-1:0] a_from_buf;
    wire [(COLS*DATA_WIDTH)-1:0] b_from_buf;
    
    // Skew Controller to Systolic Array
    wire [(ROWS*DATA_WIDTH)-1:0] a_skewed;
    wire [ROWS-1:0]              valid_skewed;
    wire [(COLS*DATA_WIDTH)-1:0] b_skewed;
    
    // Systolic Array accumulator outputs
    wire [(ROWS*COLS*ACC_WIDTH)-1:0] array_acc_out;
    
    // Accumulator to Output Buffer
    wire [(ROWS*COLS*ACC_WIDTH)-1:0] final_acc_out;
    wire                             final_acc_valid;

    // Replicate scalar array_valid to a per-row valid vector
    wire [ROWS-1:0] array_valid_vec;
    assign array_valid_vec = {ROWS{array_valid}};

    // Top Controller
    top_ctrl #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .k_dim      (k_dim),
        .done       (done),
        .busy       (busy),
        .fsm_state  (fsm_state),
        .buf_re     (buf_re),
        .buf_raddr  (buf_raddr),
        .array_valid(array_valid),
        .drain_valid(drain_valid)
    );

    // Input Buffer (A — Activations)
    input_buffer #(
        .ROWS(ROWS),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_buf_a (
        .clk    (clk),
        .rst_n  (rst_n),
        .we     (host_we_a),
        .waddr  (host_addr_a),
        .wdata  (host_wdata_a),
        .re     (buf_re),
        .raddr  (buf_raddr),
        .rdata  (a_from_buf)
    );

    // Weight Buffer (B — Weights)
    weight_buffer #(
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_buf_b (
        .clk    (clk),
        .rst_n  (rst_n),
        .we     (host_we_b),
        .waddr  (host_addr_b),
        .wdata  (host_wdata_b),
        .re     (buf_re),
        .raddr  (buf_raddr),
        .rdata  (b_from_buf)
    );

    // Skew Controller
    skew_ctrl #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew (
        .clk            (clk),
        .rst_n          (rst_n),
        .a_unskewed     (a_from_buf),
        .valid_unskewed (array_valid_vec),
        .b_unskewed     (b_from_buf),
        .a_skewed       (a_skewed),
        .valid_skewed   (valid_skewed),
        .b_skewed       (b_skewed)
    );

    // Systolic Array Core
    systolic_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk            (clk),
        .rst_n          (rst_n),
        .precision_mode (precision_mode),
        .clk_gate_en    (clk_gate_en),
        .a_in           (a_skewed),
        .valid_in       (valid_skewed),
        .b_in           (b_skewed),
        .b_out          (),
        .a_out          (),
        .valid_out      (),
        .acc_out        (array_acc_out)
    );

    // Accumulator Bank
    accumulator #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_acc (
        .clk        (clk),
        .rst_n      (rst_n),
        .acc_in     (array_acc_out),
        .valid_in   (drain_valid),
        .accumulate (accumulate),
        .acc_out    (final_acc_out),
        .valid_out  (final_acc_valid)
    );

    // Output Buffer (C — Results)
    output_buffer #(
        .ROWS(ROWS),
        .COLS(COLS),
        .ACC_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_buf_c (
        .clk    (clk),
        .rst_n  (rst_n),
        .we     (final_acc_valid),
        .waddr  ({ADDR_WIDTH{1'b0}}),
        .wdata  (final_acc_out),
        .re     (host_re_c),
        .raddr  (host_addr_c),
        .rdata  (host_rdata_c)
    );

endmodule
