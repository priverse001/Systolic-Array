`timescale 1ns/1ps

module accumulator #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter ACC_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Inputs from Systolic Array
    input  wire [(ROWS*COLS*ACC_WIDTH)-1:0]    acc_in,
    input  wire                                valid_in,     // High when array is draining
    input  wire                                accumulate,   // 1 to add to existing, 0 to overwrite
    
    // Outputs to Output Buffer
    output wire [(ROWS*COLS*ACC_WIDTH)-1:0]    acc_out,
    output reg                                 valid_out
);

    reg signed [ACC_WIDTH-1:0] stored_acc [0:(ROWS*COLS)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
        end
    end

    genvar i;
    generate
        for (i = 0; i < ROWS*COLS; i = i + 1) begin : acc_loop
            wire signed [ACC_WIDTH-1:0] in_val = acc_in[(i*ACC_WIDTH) +: ACC_WIDTH];
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    stored_acc[i] <= {ACC_WIDTH{1'b0}};
                end else if (valid_in) begin
                    if (accumulate) begin
                        stored_acc[i] <= stored_acc[i] + in_val;
                    end else begin
                        stored_acc[i] <= in_val;
                    end
                end
            end
            
            assign acc_out[(i*ACC_WIDTH) +: ACC_WIDTH] = stored_acc[i];
        end
    endgenerate

endmodule
