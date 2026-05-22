`timescale 1ns/1ps

module tiling_ctrl #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Host configuration (from AXI4-Lite)
    input  wire                   tile_start,    // Pulse to begin tiling
    input  wire [ADDR_WIDTH-1:0]  k_tile_size,   // Per-tile K (= array K_DIM)
    input  wire [15:0]            k_full,        // Full K dimension of the matrix
    output wire                   tile_done,     // All K-tiles completed
    output wire [7:0]             k_tile_idx,    // Current K-tile index (for status)

    // Interface to compute core (top_ctrl)
    output reg                    core_start,    // Start pulse to top_ctrl
    input  wire                   core_done,     // Done from top_ctrl
    output reg                    accumulate,    // 0 for first tile, 1 for subsequent
    output reg  [ADDR_WIDTH-1:0]  k_dim_out      // K_DIM value for current tile
);

    localparam ST_IDLE    = 3'd0;
    localparam ST_LOAD    = 3'd1;  // Wait for host to load buffers
    localparam ST_START   = 3'd2;  // Pulse start to core
    localparam ST_WAIT    = 3'd3;  // Wait for core_done
    localparam ST_NEXT    = 3'd4;  // Advance to next K-tile
    localparam ST_DONE    = 3'd5;

    reg [2:0]  state;
    reg [15:0] k_remaining;
    reg [7:0]  tile_count;
    reg        done_reg;

    assign tile_done  = done_reg;
    assign k_tile_idx = tile_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            k_remaining <= 16'd0;
            tile_count  <= 8'd0;
            core_start  <= 1'b0;
            accumulate  <= 1'b0;
            k_dim_out   <= {ADDR_WIDTH{1'b0}};
            done_reg    <= 1'b0;
        end else begin
            // Auto-clear pulses
            core_start <= 1'b0;
            done_reg   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (tile_start) begin
                        k_remaining <= k_full;
                        tile_count  <= 8'd0;
                        accumulate  <= 1'b0;
                        state       <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    // Compute K_DIM for this tile
                    if (k_remaining > {8'd0, k_tile_size}) begin
                        k_dim_out <= k_tile_size;
                    end else begin
                        k_dim_out <= k_remaining[ADDR_WIDTH-1:0];
                    end
                    state <= ST_START;
                end

                ST_START: begin
                    core_start <= 1'b1;
                    state      <= ST_WAIT;
                end

                ST_WAIT: begin
                    if (core_done) begin
                        state <= ST_NEXT;
                    end
                end

                ST_NEXT: begin
                    if (k_remaining > {8'd0, k_tile_size}) begin
                        k_remaining <= k_remaining - {8'd0, k_tile_size};
                    end else begin
                        k_remaining <= 16'd0;
                    end
                    tile_count <= tile_count + 1;

                    if (k_remaining <= {8'd0, k_tile_size}) begin
                        // All K-tiles done
                        done_reg <= 1'b1;
                        state    <= ST_DONE;
                    end else begin
                        // More tiles to process
                        accumulate <= 1'b1;  // Subsequent tiles accumulate
                        state      <= ST_LOAD;
                    end
                end

                ST_DONE: begin
                    if (!tile_start) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
