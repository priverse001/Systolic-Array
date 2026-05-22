`timescale 1ns/1ps

module axi4_stream_loader #(
    parameter DATA_WIDTH_BUF = 1024, // Buffer word width (ROWS*DATA_WIDTH or COLS*DATA_WIDTH)
    parameter ADDR_WIDTH     = 8
)(
    input  wire                        clk,
    input  wire                        rst_n,

    // AXI4-Stream Slave Interface
    input  wire [DATA_WIDTH_BUF-1:0]   S_AXIS_TDATA,
    input  wire                        S_AXIS_TVALID,
    output wire                        S_AXIS_TREADY,
    input  wire                        S_AXIS_TLAST,

    // Control (from AXI4-Lite registers)
    input  wire                        stream_enable,  // 1 = accept data
    output wire                        stream_done,    // pulse on TLAST
    output wire [ADDR_WIDTH-1:0]       words_loaded,

    // Buffer write interface
    output wire                        buf_we,
    output wire [ADDR_WIDTH-1:0]       buf_addr,
    output wire [DATA_WIDTH_BUF-1:0]   buf_wdata
);

    reg [ADDR_WIDTH-1:0] addr_counter;
    reg                   done_reg;
    reg                   active;

    wire handshake = S_AXIS_TVALID & S_AXIS_TREADY;

    assign S_AXIS_TREADY = stream_enable & active;
    assign buf_we         = handshake;
    assign buf_addr       = addr_counter;
    assign buf_wdata      = S_AXIS_TDATA;
    assign stream_done    = done_reg;
    assign words_loaded   = addr_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_counter <= {ADDR_WIDTH{1'b0}};
            done_reg     <= 1'b0;
            active       <= 1'b0;
        end else begin
            // Auto-clear done after 1 cycle
            if (done_reg)
                done_reg <= 1'b0;

            if (stream_enable && !active && !done_reg) begin
                // Arm the loader
                active       <= 1'b1;
                addr_counter <= {ADDR_WIDTH{1'b0}};
            end

            if (handshake) begin
                addr_counter <= addr_counter + 1;
                if (S_AXIS_TLAST) begin
                    done_reg <= 1'b1;
                    active   <= 1'b0;
                end
            end

            if (!stream_enable) begin
                active <= 1'b0;
            end
        end
    end

endmodule
