`timescale 1ns/1ps

module pe_dual_mode #(
    parameter MAX_DATA_WIDTH = 16,
    parameter ACC_WIDTH = 32
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          precision_mode, // 0=INT8, 1=INT16

    input  wire signed [MAX_DATA_WIDTH-1:0] a_in,
    input  wire signed [MAX_DATA_WIDTH-1:0] b_in,
    input  wire                          valid_in,

    output wire signed [MAX_DATA_WIDTH-1:0] a_out,
    output wire signed [MAX_DATA_WIDTH-1:0] b_out,
    output wire signed [ACC_WIDTH-1:0]      acc_out,
    output wire                          valid_out
);

    // Runtime precision selection:
    //   INT8:  sign-extend a_in[7:0] and b_in[7:0] to 16 bits
    //   INT16: use full a_in[15:0] and b_in[15:0]
    wire signed [MAX_DATA_WIDTH-1:0] a_eff;
    wire signed [MAX_DATA_WIDTH-1:0] b_eff;

    assign a_eff = precision_mode ? a_in : {{(MAX_DATA_WIDTH-8){a_in[7]}}, a_in[7:0]};
    assign b_eff = precision_mode ? b_in : {{(MAX_DATA_WIDTH-8){b_in[7]}}, b_in[7:0]};

    (* use_dsp = "yes" *) reg signed [ACC_WIDTH-1:0] acc;
    reg signed [MAX_DATA_WIDTH-1:0] a_reg;
    reg signed [MAX_DATA_WIDTH-1:0] b_reg;
    reg valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_WIDTH{1'b0}};
            a_reg     <= {MAX_DATA_WIDTH{1'b0}};
            b_reg     <= {MAX_DATA_WIDTH{1'b0}};
            valid_reg <= 1'b0;
        end else begin
            if (valid_in) begin
                acc <= acc + (a_eff * b_eff);
            end
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
