`timescale 1ns/1ps

// AXI4-Lite Slave Interface — Extended Register Map (v2.0)
//
// Register Map (byte addresses):
//   0x00  CTRL           [0] start (write-1-to-pulse)
//   0x04  STATUS         [0] done, [1] busy, [4:2] fsm_state (RO)
//   0x08  K_DIM          Per-tile K dimension (RW)
//   0x0C  ARRAY_CFG      [15:8] COLS, [7:0] ROWS (RO)
//   0x10  PERF_TOTAL     Total cycles (RO)
//   0x14  PERF_COMPUTE   Compute cycles (RO)
//   0x18  VERSION        0x0002_0000 (v2.0) (RO)
//   0x1C  STREAM_CFG     [0] target, [1] enable (RW)
//   0x20  STREAM_STATUS  [0] a_done, [1] b_done (RO)
//   0x24  TILE_K_FULL    Full K dimension (RW)
//   0x28  TILE_STATUS    [0] tile_done, [15:8] k_tile_idx (RO)
//   0x2C  PRECISION      [0] mode (0=INT8, 1=INT16) (RW)
//   0x30  CLK_GATE_CFG   [0] enable clock gating (RW)
//   0x34  TILE_CTRL      [0] tile_start (write-1-to-pulse) (W)

module axi4_lite_slave #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6,
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter ADDR_WIDTH = 8
)(
    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  wire [2:0]                          S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output wire [1:0]                          S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  wire [2:0]                          S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,

    // AXI4-Lite Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_RDATA,
    output wire [1:0]                          S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY,

    // User Ports — Core Control
    output wire                                usr_start,
    output wire [ADDR_WIDTH-1:0]               usr_k_dim,
    input  wire                                usr_done,
    input  wire                                usr_busy,
    input  wire [2:0]                          usr_fsm_state,

    // User Ports — Stream Loader
    output wire                                usr_stream_target,   // 0=A, 1=B
    output wire                                usr_stream_enable,
    input  wire                                usr_stream_a_done,
    input  wire                                usr_stream_b_done,

    // User Ports — Tiling
    output wire                                usr_tile_start,
    output wire [15:0]                         usr_tile_k_full,
    input  wire                                usr_tile_done,
    input  wire [7:0]                          usr_tile_k_idx,

    // User Ports — Precision & Clock Gating
    output wire                                usr_precision_mode,
    output wire                                usr_clk_gate_en
);

    // Internal AXI signals
    reg                                axi_awready;
    reg                                axi_wready;
    reg [1:0]                          axi_bresp;
    reg                                axi_bvalid;
    reg                                axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0]       axi_rdata;
    reg [1:0]                          axi_rresp;
    reg                                axi_rvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0]       axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1:0]       axi_araddr;
    reg aw_en;

    // User registers
    reg        reg_start;
    reg [ADDR_WIDTH-1:0] reg_k_dim;
    reg        reg_stream_target;
    reg        reg_stream_enable;
    reg [15:0] reg_tile_k_full;
    reg        reg_tile_start;
    reg        reg_precision_mode;
    reg        reg_clk_gate_en;

    // Performance counters
    reg [31:0] perf_total;
    reg [31:0] perf_compute;
    reg        perf_running;

    // Status latches for pulses
    reg reg_status_done;
    reg reg_status_tile_done;

    // Register address decode (word-aligned, drop lower 2 bits)
    wire [3:0] wr_addr = axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2];
    wire [3:0] rd_addr = axi_araddr[C_S_AXI_ADDR_WIDTH-1:2];

    wire wr_en = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

    // AXI outputs
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // User outputs
    assign usr_start          = reg_start;
    assign usr_k_dim          = reg_k_dim;
    assign usr_stream_target  = reg_stream_target;
    assign usr_stream_enable  = reg_stream_enable;
    assign usr_tile_start     = reg_tile_start;
    assign usr_tile_k_full    = reg_tile_k_full;
    assign usr_precision_mode = reg_precision_mode;
    assign usr_clk_gate_en    = reg_clk_gate_en;

    // Write Address Channel (AW)
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
            axi_awaddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
                axi_awaddr  <= S_AXI_AWADDR;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // Write Data Channel (W)
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    // Register Write Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            reg_start          <= 1'b0;
            reg_k_dim          <= {ADDR_WIDTH{1'b0}};
            reg_stream_target  <= 1'b0;
            reg_stream_enable  <= 1'b0;
            reg_tile_k_full    <= 16'd0;
            reg_tile_start     <= 1'b0;
            reg_precision_mode <= 1'b0;
            reg_clk_gate_en    <= 1'b0;
        end else begin
            // Auto-clear pulse registers
            if (reg_start)
                reg_start <= 1'b0;
            if (reg_tile_start)
                reg_tile_start <= 1'b0;

            if (wr_en) begin
                case (wr_addr)
                    4'd0: begin // 0x00 CTRL
                        if (S_AXI_WSTRB[0])
                            reg_start <= S_AXI_WDATA[0];
                    end
                    // 4'd1: STATUS — read-only
                    4'd2: begin // 0x08 K_DIM
                        if (S_AXI_WSTRB[0])
                            reg_k_dim <= S_AXI_WDATA[ADDR_WIDTH-1:0];
                    end
                    // 4'd3: ARRAY_CFG — read-only
                    // 4'd4: PERF_TOTAL — read-only
                    // 4'd5: PERF_COMPUTE — read-only
                    // 4'd6: VERSION — read-only
                    4'd7: begin // 0x1C STREAM_CFG
                        if (S_AXI_WSTRB[0]) begin
                            reg_stream_target <= S_AXI_WDATA[0];
                            reg_stream_enable <= S_AXI_WDATA[1];
                        end
                    end
                    // 4'd8: STREAM_STATUS — read-only
                    4'd9: begin // 0x24 TILE_K_FULL
                        if (S_AXI_WSTRB[0])
                            reg_tile_k_full[7:0] <= S_AXI_WDATA[7:0];
                        if (S_AXI_WSTRB[1])
                            reg_tile_k_full[15:8] <= S_AXI_WDATA[15:8];
                    end
                    // 4'd10: TILE_STATUS — read-only
                    4'd11: begin // 0x2C PRECISION
                        if (S_AXI_WSTRB[0])
                            reg_precision_mode <= S_AXI_WDATA[0];
                    end
                    4'd12: begin // 0x30 CLK_GATE_CFG
                        if (S_AXI_WSTRB[0])
                            reg_clk_gate_en <= S_AXI_WDATA[0];
                    end
                    4'd13: begin // 0x34 TILE_CTRL
                        if (S_AXI_WSTRB[0])
                            reg_tile_start <= S_AXI_WDATA[0];
                    end
                    default: ;
                endcase
            end
        end
    end

    // Status Latch Logic
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            reg_status_done <= 1'b0;
            reg_status_tile_done <= 1'b0;
        end else begin
            if (reg_start) reg_status_done <= 1'b0;
            else if (usr_done) reg_status_done <= 1'b1;

            if (reg_tile_start) reg_status_tile_done <= 1'b0;
            else if (usr_tile_done) reg_status_tile_done <= 1'b1;
        end
    end

    // Write Response Channel (B)
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (wr_en && ~axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // Read Address Channel (AR)
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // Read Data Channel (R) + Register Read Mux
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
            axi_rdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00;

                case (rd_addr)
                    4'd0:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-1){1'b0}}, reg_start};
                    4'd1:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-5){1'b0}}, usr_fsm_state, usr_busy, reg_status_done};
                    4'd2:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-ADDR_WIDTH){1'b0}}, reg_k_dim};
                    4'd3:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-16){1'b0}}, COLS[7:0], ROWS[7:0]};
                    4'd4:  axi_rdata <= perf_total;
                    4'd5:  axi_rdata <= perf_compute;
                    4'd6:  axi_rdata <= 32'h0002_0000; // Version 2.0
                    4'd7:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-2){1'b0}}, reg_stream_enable, reg_stream_target};
                    4'd8:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-2){1'b0}}, usr_stream_b_done, usr_stream_a_done};
                    4'd9:  axi_rdata <= {{(C_S_AXI_DATA_WIDTH-16){1'b0}}, reg_tile_k_full};
                    4'd10: axi_rdata <= {{(C_S_AXI_DATA_WIDTH-9){1'b0}}, usr_tile_k_idx, reg_status_tile_done};
                    4'd11: axi_rdata <= {{(C_S_AXI_DATA_WIDTH-1){1'b0}}, reg_precision_mode};
                    4'd12: axi_rdata <= {{(C_S_AXI_DATA_WIDTH-1){1'b0}}, reg_clk_gate_en};
                    4'd13: axi_rdata <= {{(C_S_AXI_DATA_WIDTH-1){1'b0}}, reg_tile_start};
                    default: axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
                endcase
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Performance Counters
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            perf_total   <= 32'd0;
            perf_compute <= 32'd0;
            perf_running <= 1'b0;
        end else begin
            if (reg_start) begin
                perf_total   <= 32'd0;
                perf_compute <= 32'd0;
                perf_running <= 1'b1;
            end
            if (usr_done) begin
                perf_running <= 1'b0;
            end
            if (perf_running) begin
                perf_total <= perf_total + 1;
                if (usr_busy) begin
                    perf_compute <= perf_compute + 1;
                end
            end
        end
    end

endmodule
