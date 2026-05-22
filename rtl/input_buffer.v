`timescale 1ns/1ps

module input_buffer #(
    parameter ROWS = 4,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Host write interface
    input  wire                                we,
    input  wire [ADDR_WIDTH-1:0]               waddr,
    input  wire [(ROWS*DATA_WIDTH)-1:0]        wdata,
    
    // Array read interface
    input  wire                                re,
    input  wire [ADDR_WIDTH-1:0]               raddr,
    output reg  [(ROWS*DATA_WIDTH)-1:0]        rdata
);

    // Memory array
    reg [(ROWS*DATA_WIDTH)-1:0] mem [0:(2**ADDR_WIDTH)-1];
    
    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        if (re) begin
            rdata <= mem[raddr];
        end
    end

endmodule
