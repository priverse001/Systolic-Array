`timescale 1ns/1ps

// Pulse Synchronizer (Toggle-Based)
//
// Safely transfers a single-clock-cycle pulse from the source
// clock domain to the destination clock domain. This works even
// when the clocks have no frequency relationship.
//
// Algorithm:
//   1. Source domain: Pulse toggles a local T flip-flop
//   2. The toggle signal is synchronized to dst_clk via 2FF
//   3. Destination domain: Edge-detect on the synchronized
//      toggle produces a single-cycle pulse in dst_clk
//
// Constraint: Source pulses must be separated by at least
// 2 destination clock cycles to avoid lost pulses.

module cdc_pulse_sync (
    // Source clock domain
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,    // Single-cycle pulse in src_clk
    
    // Destination clock domain
    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse     // Single-cycle pulse in dst_clk
);

    // Toggle flip-flop in source domain
    reg src_toggle;
    
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n)
            src_toggle <= 1'b0;
        else if (src_pulse)
            src_toggle <= ~src_toggle;
    end

    // Synchronize toggle to destination domain
    wire dst_toggle_sync;
    
    cdc_sync_2ff #(
        .WIDTH(1),
        .RESET_VAL(0)
    ) u_sync_toggle (
        .dst_clk   (dst_clk),
        .dst_rst_n (dst_rst_n),
        .src_sig   (src_toggle),
        .dst_sig   (dst_toggle_sync)
    );

    // Edge detect in destination domain
    reg dst_toggle_prev;
    
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n)
            dst_toggle_prev <= 1'b0;
        else
            dst_toggle_prev <= dst_toggle_sync;
    end

    assign dst_pulse = dst_toggle_sync ^ dst_toggle_prev;

endmodule
