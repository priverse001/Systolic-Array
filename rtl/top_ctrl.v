`timescale 1ns/1ps

// Top Controller FSM
// Manages the lifecycle of a single MatMul tile:
//   IDLE -> COMPUTE (feed data) -> WAIT (pipeline drain) -> DRAIN (latch result) -> DONE
//
// Key timing:
//   - Buffers have 1-cycle read latency. buf_re is asserted one cycle BEFORE
//     the data is needed at the skew controller input.
//   - After the last data word is fed, the pipeline needs (ROWS+COLS-2) extra
//     cycles for the wavefront to fully propagate to PE[ROWS-1][COLS-1].

module top_ctrl #(
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter ADDR_WIDTH = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Host interface
    input  wire                   start,
    input  wire [ADDR_WIDTH-1:0]  k_dim,    // Number of K-dimension steps
    output reg                    done,
    output wire                   busy,        // High when FSM is not IDLE/DONE
    output wire [2:0]             fsm_state,   // Current FSM state (debug/AXI)
    
    // Buffer control (active 1 cycle before data needed)
    output reg                    buf_re,
    output reg  [ADDR_WIDTH-1:0]  buf_raddr,
    
    // Array control (active when data is valid at skew input)
    output reg                    array_valid,
    
    // Drain trigger (single-cycle pulse to latch accumulator)
    output reg                    drain_valid
);

    // FSM States
    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_PREFETCH= 3'd1;  // 1-cycle buffer prefetch
    localparam [2:0] ST_COMPUTE = 3'd2;  // Feeding data to array
    localparam [2:0] ST_WAIT    = 3'd3;  // Pipeline drain (no new data)
    localparam [2:0] ST_DRAIN   = 3'd4;  // Latch accumulators
    localparam [2:0] ST_DONE    = 3'd5;

    reg [2:0] state, next_state;
    reg [ADDR_WIDTH-1:0] feed_count;     // How many K-steps we have fed
    reg [ADDR_WIDTH:0]   wait_count;     // Pipeline drain counter
    
    localparam PIPELINE_DEPTH = ROWS + COLS - 2;

    // Sequential: state transitions and counters
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            feed_count <= {ADDR_WIDTH{1'b0}};
            wait_count <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            state <= next_state;
            
            case (state)
                ST_IDLE: begin
                    feed_count <= {ADDR_WIDTH{1'b0}};
                    wait_count <= {(ADDR_WIDTH+1){1'b0}};
                end
                
                ST_PREFETCH: begin
                    feed_count <= {ADDR_WIDTH{1'b0}};
                end
                
                ST_COMPUTE: begin
                    if (feed_count < k_dim) begin
                        feed_count <= feed_count + 1;
                    end
                end
                
                ST_WAIT: begin
                    wait_count <= wait_count + 1;
                end
                
                default: ;
            endcase
        end
    end

    // Combinational: next state and outputs
    always @(*) begin
        next_state  = state;
        done        = 1'b0;
        buf_re      = 1'b0;
        buf_raddr   = {ADDR_WIDTH{1'b0}};
        array_valid = 1'b0;
        drain_valid = 1'b0;
        
        case (state)
            ST_IDLE: begin
                if (start) begin
                    next_state = ST_PREFETCH;
                end
            end
            
            // Issue first buffer read; data arrives next cycle
            ST_PREFETCH: begin
                buf_re    = 1'b1;
                buf_raddr = {ADDR_WIDTH{1'b0}};
                next_state = ST_COMPUTE;
            end
            
            ST_COMPUTE: begin
                // Data from the previous cycle's buf_re is now valid
                array_valid = 1'b1;
                
                // Issue next buffer read (pipelined)
                if (feed_count + 1 < k_dim) begin
                    buf_re    = 1'b1;
                    buf_raddr = feed_count + 1;
                end
                
                // After the last feed, enter pipeline drain
                if (feed_count >= k_dim - 1) begin
                    next_state = ST_WAIT;
                end
            end
            
            ST_WAIT: begin
                if (wait_count >= PIPELINE_DEPTH) begin
                    next_state = ST_DRAIN;
                end
            end
            
            ST_DRAIN: begin
                drain_valid = 1'b1;
                next_state  = ST_DONE;
            end
            
            ST_DONE: begin
                done = 1'b1;
                if (!start) begin
                    next_state = ST_IDLE;
                end
            end
            
            default: next_state = ST_IDLE;
        endcase
    end

    // Status outputs for AXI4-Lite visibility
    assign busy      = (state != ST_IDLE) && (state != ST_DONE);
    assign fsm_state = state;

endmodule
