`timescale 1ns/1ps

// 2-Flop Synchronizer (Level Signal)
//
// Safely transfers a slow-changing or level signal from one
// clock domain to another. Mitigates metastability risk by
// passing the signal through two back-to-back flip-flops
// clocked in the destination domain.
//
// IMPORTANT: This is ONLY safe for single-bit signals that
// change slowly relative to the destination clock. Do NOT use
// for multi-bit buses that can change simultaneously — use a
// gray-coded FIFO or handshake protocol instead.
//
// Synthesis: Vivado will infer ASYNC_REG attribute automatically
// when it detects this pattern, but we add it explicitly to
// guarantee correct placement (same slice).

module cdc_sync_2ff #(
    parameter WIDTH = 1,
    parameter RESET_VAL = 0
)(
    input  wire             dst_clk,
    input  wire             dst_rst_n,
    input  wire [WIDTH-1:0] src_sig,      // Signal from source clock domain
    output wire [WIDTH-1:0] dst_sig       // Synchronized output in dst_clk domain
);

    // Synthesis attribute: place both flops in the same slice
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff2;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_ff1 <= RESET_VAL[WIDTH-1:0];
            sync_ff2 <= RESET_VAL[WIDTH-1:0];
        end else begin
            sync_ff1 <= src_sig;
            sync_ff2 <= sync_ff1;
        end
    end

    assign dst_sig = sync_ff2;

endmodule
