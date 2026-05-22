`timescale 1ns/1ps

module pe_clock_gate (
    input  wire clk,
    input  wire enable,
    output wire gated_clk
);

    // Latch-based ICG (Integrated Clock Gate)
    // Standard pattern recognized by Xilinx/ASIC synthesis tools:
    //   - Latch is transparent when clk=0 (negative level)
    //   - AND gate combines latched enable with clock
    // This prevents glitches on the gated clock output.

    reg enable_latched;

    always @(*) begin
        if (!clk)
            enable_latched = enable;
    end

    assign gated_clk = clk & enable_latched;

endmodule
