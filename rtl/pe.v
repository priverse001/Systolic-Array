`timescale 1ns/1ps

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Inputs from neighbors
    input  wire signed [DATA_WIDTH-1:0] a_in,      // Activation from left
    input  wire signed [DATA_WIDTH-1:0] b_in,      // Weight from top
    input  wire                   valid_in,  // Data valid
    
    // Outputs to neighbors
    output wire signed [DATA_WIDTH-1:0] a_out,     // Forward activation right
    output wire signed [DATA_WIDTH-1:0] b_out,     // Forward weight down
    output wire signed [ACC_WIDTH-1:0]  acc_out,   // Accumulated result
    output wire                   valid_out  // Forward valid signal
);

    // Explicitly infer DSP block for MAC in Vivado
    (* use_dsp = "yes" *) reg signed [ACC_WIDTH-1:0] acc;
    reg signed [DATA_WIDTH-1:0] a_reg;
    reg signed [DATA_WIDTH-1:0] b_reg;
    reg valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_WIDTH{1'b0}};
            a_reg     <= {DATA_WIDTH{1'b0}};
            b_reg     <= {DATA_WIDTH{1'b0}};
            valid_reg <= 1'b0;
        end else begin
            if (valid_in) begin
                // Multiply and Accumulate
                acc <= acc + (a_in * b_in);
            end
            // Forward data to adjacent PEs
            a_reg     <= a_in;
            b_reg     <= b_in;
            valid_reg <= valid_in;
        end
    end

    assign a_out     = a_reg;
    assign b_out     = b_reg;
    assign acc_out   = acc;
    assign valid_out = valid_reg;

endmodule
