`timescale 1ns/1ps

// Reset Synchronizer (Async Assert, Sync Deassert)
//
// Generates a clean, synchronous reset in the destination
// clock domain from an asynchronous external reset.
//
// Behavior:
//   - When ext_rst_n goes LOW: output immediately asserts LOW
//     (asynchronous assertion — no clock needed)
//   - When ext_rst_n goes HIGH: output deasserts HIGH after
//     2 rising edges of dst_clk (synchronous deassertion)
//
// This prevents metastability on the deassertion edge, which
// is the critical path where flip-flops could enter an
// indeterminate state if reset releases near a clock edge.

module cdc_reset_sync (
    input  wire dst_clk,
    input  wire ext_rst_n,    // Asynchronous reset (active low)
    output wire dst_rst_n     // Synchronized reset (active low)
);

    (* ASYNC_REG = "TRUE" *) reg rst_ff1;
    (* ASYNC_REG = "TRUE" *) reg rst_ff2;

    always @(posedge dst_clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_ff1 <= 1'b0;
            rst_ff2 <= 1'b0;
        end else begin
            rst_ff1 <= 1'b1;
            rst_ff2 <= rst_ff1;
        end
    end

    assign dst_rst_n = rst_ff2;

endmodule
