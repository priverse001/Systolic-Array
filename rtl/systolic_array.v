`timescale 1ns/1ps

module systolic_array #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                precision_mode, // 0=INT8, 1=INT16
    input  wire                                clk_gate_en,    // 1=gate clock when idle

    // Left edge inputs (Activations)
    input  wire [(ROWS*DATA_WIDTH)-1:0]        a_in,
    input  wire [ROWS-1:0]                     valid_in,

    // Top edge inputs (Weights)
    input  wire [(COLS*DATA_WIDTH)-1:0]        b_in,

    // Bottom edge outputs (Weights passing through)
    output wire [(COLS*DATA_WIDTH)-1:0]        b_out,

    // Right edge outputs (Activations passing through)
    output wire [(ROWS*DATA_WIDTH)-1:0]        a_out,
    output wire [ROWS-1:0]                     valid_out,

    // Accumulated results from all PEs
    output wire [(ROWS*COLS*ACC_WIDTH)-1:0]    acc_out
);

    // Clock gating: gate PE clocks when array is idle
    // Clock gating: only gate when explicitly enabled via register.
    // When clk_gate_en=0 (default), pe_clk_enable=1 always (no gating).
    // When clk_gate_en=1, gate based on valid data presence.
    wire any_valid = |valid_in;
    wire pe_clk_enable = clk_gate_en ? any_valid : 1'b1;
    wire gated_clk;

    pe_clock_gate u_icg (
        .clk       (clk),
        .enable    (pe_clk_enable),
        .gated_clk (gated_clk)
    );

    // Interconnect wires
    wire signed [DATA_WIDTH-1:0] a_wire [0:ROWS-1][0:COLS];
    wire signed [DATA_WIDTH-1:0] b_wire [0:ROWS][0:COLS-1];
    wire                         valid_wire [0:ROWS-1][0:COLS];
    wire signed [ACC_WIDTH-1:0]  pe_acc_out [0:ROWS-1][0:COLS-1];

    genvar i, j;
    generate
        // Connect left edge (Activations)
        for (i = 0; i < ROWS; i = i + 1) begin : left_edge
            assign a_wire[i][0]     = a_in[(i*DATA_WIDTH) +: DATA_WIDTH];
            assign valid_wire[i][0] = valid_in[i];
        end

        // Connect top edge (Weights)
        for (j = 0; j < COLS; j = j + 1) begin : top_edge
            assign b_wire[0][j]     = b_in[(j*DATA_WIDTH) +: DATA_WIDTH];
        end

        // Connect right edge (Activations out)
        for (i = 0; i < ROWS; i = i + 1) begin : right_edge
            assign a_out[(i*DATA_WIDTH) +: DATA_WIDTH] = a_wire[i][COLS];
            assign valid_out[i] = valid_wire[i][COLS];
        end

        // Connect bottom edge (Weights out)
        for (j = 0; j < COLS; j = j + 1) begin : bottom_edge
            assign b_out[(j*DATA_WIDTH) +: DATA_WIDTH] = b_wire[ROWS][j];
        end

        // Instantiate PE grid with gated clock
        for (i = 0; i < ROWS; i = i + 1) begin : row
            for (j = 0; j < COLS; j = j + 1) begin : col
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk       (gated_clk),
                    .rst_n     (rst_n),
                    .a_in      (a_wire[i][j]),
                    .b_in      (b_wire[i][j]),
                    .valid_in  (valid_wire[i][j]),
                    .a_out     (a_wire[i][j+1]),
                    .b_out     (b_wire[i+1][j]),
                    .acc_out   (pe_acc_out[i][j]),
                    .valid_out (valid_wire[i][j+1])
                );

                // Map 2D accumulator array to 1D output
                assign acc_out[((i * COLS + j)*ACC_WIDTH) +: ACC_WIDTH] = pe_acc_out[i][j];
            end
        end
    endgenerate

endmodule
