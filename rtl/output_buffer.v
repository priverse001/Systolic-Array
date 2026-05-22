`timescale 1ns/1ps

module output_buffer #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 8
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Array write interface (from Accumulator Bank)
    input  wire                                we,
    input  wire [ADDR_WIDTH-1:0]               waddr,
    input  wire [(ROWS*COLS*ACC_WIDTH)-1:0]    wdata,
    
    // Host read interface
    input  wire                                re,
    input  wire [ADDR_WIDTH-1:0]               raddr,
    output reg  [(ROWS*COLS*ACC_WIDTH)-1:0]    rdata
);

    // Memory array
    reg [(ROWS*COLS*ACC_WIDTH)-1:0] mem [0:(2**ADDR_WIDTH)-1];
    
    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        if (re) begin
            rdata <= mem[raddr];
        end
    end

endmodule
