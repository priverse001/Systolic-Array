`timescale 1ns/1ps

// Skew Controller
// Delays row i of activations by i clock cycles,
// and column j of weights by j clock cycles.
// This ensures data arrives at PE[i][j] at the correct time
// for proper systolic wavefront alignment.

module skew_ctrl #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Unskewed inputs from buffers
    input  wire [(ROWS*DATA_WIDTH)-1:0]        a_unskewed,
    input  wire [ROWS-1:0]                     valid_unskewed,
    input  wire [(COLS*DATA_WIDTH)-1:0]        b_unskewed,
    
    // Skewed outputs to systolic array
    output wire [(ROWS*DATA_WIDTH)-1:0]        a_skewed,
    output wire [ROWS-1:0]                     valid_skewed,
    output wire [(COLS*DATA_WIDTH)-1:0]        b_skewed
);

    genvar gi, gj;
    generate
        // Skew Activations (a): Row i delayed by i cycles
        
        // Row 0: no delay (passthrough)
        assign a_skewed[0 +: DATA_WIDTH] = a_unskewed[0 +: DATA_WIDTH];
        assign valid_skewed[0] = valid_unskewed[0];
        
        // Row 1: delay by exactly 1 cycle (special case — single register)
        if (ROWS > 1) begin : a_skew_row1
            reg signed [DATA_WIDTH-1:0] a_d1;
            reg                         v_d1;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_d1 <= {DATA_WIDTH{1'b0}};
                    v_d1 <= 1'b0;
                end else begin
                    a_d1 <= a_unskewed[1*DATA_WIDTH +: DATA_WIDTH];
                    v_d1 <= valid_unskewed[1];
                end
            end
            
            assign a_skewed[1*DATA_WIDTH +: DATA_WIDTH] = a_d1;
            assign valid_skewed[1] = v_d1;
        end
        
        // Rows 2+: delay by i cycles using a shift register chain
        for (gi = 2; gi < ROWS; gi = gi + 1) begin : a_skew_gen
            // Shift register: gi stages, each DATA_WIDTH bits wide
            reg signed [DATA_WIDTH-1:0] a_sr [0:gi-1];
            reg                         v_sr [0:gi-1];
            integer d;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (d = 0; d < gi; d = d + 1) begin
                        a_sr[d] <= {DATA_WIDTH{1'b0}};
                        v_sr[d] <= 1'b0;
                    end
                end else begin
                    // Stage 0 captures the input
                    a_sr[0] <= a_unskewed[gi*DATA_WIDTH +: DATA_WIDTH];
                    v_sr[0] <= valid_unskewed[gi];
                    // Remaining stages shift
                    for (d = 1; d < gi; d = d + 1) begin
                        a_sr[d] <= a_sr[d-1];
                        v_sr[d] <= v_sr[d-1];
                    end
                end
            end
            
            assign a_skewed[gi*DATA_WIDTH +: DATA_WIDTH] = a_sr[gi-1];
            assign valid_skewed[gi] = v_sr[gi-1];
        end
        
        // Skew Weights (b): Column j delayed by j cycles
        
        // Column 0: no delay (passthrough)
        assign b_skewed[0 +: DATA_WIDTH] = b_unskewed[0 +: DATA_WIDTH];
        
        // Column 1: delay by exactly 1 cycle
        if (COLS > 1) begin : b_skew_col1
            reg signed [DATA_WIDTH-1:0] b_d1;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    b_d1 <= {DATA_WIDTH{1'b0}};
                end else begin
                    b_d1 <= b_unskewed[1*DATA_WIDTH +: DATA_WIDTH];
                end
            end
            
            assign b_skewed[1*DATA_WIDTH +: DATA_WIDTH] = b_d1;
        end
        
        // Columns 2+: delay by j cycles using a shift register chain
        for (gj = 2; gj < COLS; gj = gj + 1) begin : b_skew_gen
            reg signed [DATA_WIDTH-1:0] b_sr [0:gj-1];
            integer d;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (d = 0; d < gj; d = d + 1) begin
                        b_sr[d] <= {DATA_WIDTH{1'b0}};
                    end
                end else begin
                    b_sr[0] <= b_unskewed[gj*DATA_WIDTH +: DATA_WIDTH];
                    for (d = 1; d < gj; d = d + 1) begin
                        b_sr[d] <= b_sr[d-1];
                    end
                end
            end
            
            assign b_skewed[gj*DATA_WIDTH +: DATA_WIDTH] = b_sr[gj-1];
        end
    endgenerate

endmodule
