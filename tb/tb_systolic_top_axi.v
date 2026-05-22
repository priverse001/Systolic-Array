`timescale 1ns/1ps

module tb_systolic_top_axi;


    parameter ROWS = 4;
    parameter COLS = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter K_DIM = 4;
    parameter C_S_AXI_DATA_WIDTH = 32;
    parameter C_S_AXI_ADDR_WIDTH = 6;

    // AXI register addresses
    localparam ADDR_CTRL      = 6'h00;
    localparam ADDR_STATUS    = 6'h04;
    localparam ADDR_KDIM      = 6'h08;
    localparam ADDR_ARRAY_CFG = 6'h0C;
    localparam ADDR_PERF_TOT  = 6'h10;
    localparam ADDR_PERF_COMP = 6'h14;
    localparam ADDR_VERSION   = 6'h18;
    localparam ADDR_PRECISION = 6'h2C;
    localparam ADDR_CLK_GATE  = 6'h30;


    reg clk;
    reg rst_n;
    
    always #5 clk = ~clk;


    reg  [C_S_AXI_ADDR_WIDTH-1:0]     axi_awaddr;
    reg  [2:0]                        axi_awprot;
    reg                               axi_awvalid;
    wire                              axi_awready;

    reg  [C_S_AXI_DATA_WIDTH-1:0]     axi_wdata;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_wstrb;
    reg                               axi_wvalid;
    wire                              axi_wready;

    wire [1:0]                        axi_bresp;
    wire                              axi_bvalid;
    reg                               axi_bready;

    reg  [C_S_AXI_ADDR_WIDTH-1:0]     axi_araddr;
    reg  [2:0]                        axi_arprot;
    reg                               axi_arvalid;
    wire                              axi_arready;

    wire [C_S_AXI_DATA_WIDTH-1:0]     axi_rdata;
    wire [1:0]                        axi_rresp;
    wire                              axi_rvalid;
    reg                               axi_rready;


    reg                               host_we_a;
    reg  [ADDR_WIDTH-1:0]             host_addr_a;
    reg  [(ROWS*DATA_WIDTH)-1:0]      host_wdata_a;

    reg                               host_we_b;
    reg  [ADDR_WIDTH-1:0]             host_addr_b;
    reg  [(COLS*DATA_WIDTH)-1:0]      host_wdata_b;

    reg                               host_re_c;
    reg  [ADDR_WIDTH-1:0]             host_addr_c;
    wire [(ROWS*COLS*ACC_WIDTH)-1:0]  host_rdata_c;


    reg [DATA_WIDTH-1:0] mem_a [0:(ROWS*K_DIM)-1];
    reg [DATA_WIDTH-1:0] mem_b [0:(K_DIM*COLS)-1];
    reg [ACC_WIDTH-1:0]  mem_c_exp [0:(ROWS*COLS)-1];

    integer i, j, err_cnt, timeout;
    reg [(ROWS*DATA_WIDTH)-1:0] a_row;
    reg [(COLS*DATA_WIDTH)-1:0] b_row;
    reg [ACC_WIDTH-1:0] act_val, exp_val;
    
    // For AXI read task
    reg [C_S_AXI_DATA_WIDTH-1:0] read_data;


    systolic_top_axi #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .S_AXI_AWADDR  (axi_awaddr),
        .S_AXI_AWPROT  (axi_awprot),
        .S_AXI_AWVALID (axi_awvalid),
        .S_AXI_AWREADY (axi_awready),
        .S_AXI_WDATA   (axi_wdata),
        .S_AXI_WSTRB   (axi_wstrb),
        .S_AXI_WVALID  (axi_wvalid),
        .S_AXI_WREADY  (axi_wready),
        .S_AXI_BRESP   (axi_bresp),
        .S_AXI_BVALID  (axi_bvalid),
        .S_AXI_BREADY  (axi_bready),
        .S_AXI_ARADDR  (axi_araddr),
        .S_AXI_ARPROT  (axi_arprot),
        .S_AXI_ARVALID (axi_arvalid),
        .S_AXI_ARREADY (axi_arready),
        .S_AXI_RDATA   (axi_rdata),
        .S_AXI_RRESP   (axi_rresp),
        .S_AXI_RVALID  (axi_rvalid),
        .S_AXI_RREADY  (axi_rready),
        .S_AXIS_A_TDATA  ({(ROWS*DATA_WIDTH){1'b0}}),
        .S_AXIS_A_TVALID (1'b0),
        .S_AXIS_A_TREADY (),
        .S_AXIS_A_TLAST  (1'b0),
        .S_AXIS_B_TDATA  ({(COLS*DATA_WIDTH){1'b0}}),
        .S_AXIS_B_TVALID (1'b0),
        .S_AXIS_B_TREADY (),
        .S_AXIS_B_TLAST  (1'b0),
        .host_we_a     (host_we_a),
        .host_addr_a   (host_addr_a),
        .host_wdata_a  (host_wdata_a),
        .host_we_b     (host_we_b),
        .host_addr_b   (host_addr_b),
        .host_wdata_b  (host_wdata_b),
        .host_re_c     (host_re_c),
        .host_addr_c   (host_addr_c),
        .host_rdata_c  (host_rdata_c)
    );


    task axi_write;
        input [C_S_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            axi_awaddr  <= addr;
            axi_awprot  <= 3'b000;
            axi_awvalid <= 1'b1;
            axi_wdata   <= data;
            axi_wstrb   <= 4'hF;
            axi_wvalid  <= 1'b1;
            axi_bready  <= 1'b1;
            
            // Wait for both handshakes
            @(posedge clk);
            while (!(axi_awready && axi_wready)) begin
                @(posedge clk);
            end
            
            axi_awvalid <= 1'b0;
            axi_wvalid  <= 1'b0;
            
            // Wait for write response
            while (!axi_bvalid) begin
                @(posedge clk);
            end
            @(posedge clk);
            axi_bready <= 1'b0;
        end
    endtask


    task axi_read;
        input  [C_S_AXI_ADDR_WIDTH-1:0] addr;
        output [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            axi_araddr  <= addr;
            axi_arprot  <= 3'b000;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;
            
            // Wait for address handshake
            @(posedge clk);
            while (!axi_arready) begin
                @(posedge clk);
            end
            axi_arvalid <= 1'b0;
            
            // Wait for read data
            while (!axi_rvalid) begin
                @(posedge clk);
            end
            data = axi_rdata; // Data output from task is still blocking to return
            @(posedge clk);
            axi_rready <= 1'b0;
        end
    endtask


    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        axi_awaddr = 0; axi_awprot = 0; axi_awvalid = 0;
        axi_wdata = 0; axi_wstrb = 0; axi_wvalid = 0;
        axi_bready = 0;
        axi_araddr = 0; axi_arprot = 0; axi_arvalid = 0;
        axi_rready = 0;
        host_we_a = 0; host_addr_a = 0; host_wdata_a = 0;
        host_we_b = 0; host_addr_b = 0; host_wdata_b = 0;
        host_re_c = 0; host_addr_c = 0;
        err_cnt = 0;

        // Load test vectors
        $readmemh("matrix_a.hex", mem_a);
        $readmemh("matrix_b.hex", mem_b);
        $readmemh("matrix_c_expected.hex", mem_c_exp);

        // Reset
        #25;
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        @(posedge clk);



        // Read VERSION register
        axi_read(ADDR_VERSION, read_data);
        $display("[AXI] VERSION  = 0x%08h (expected 0x00020000)", read_data);
        if (read_data !== 32'h0002_0000) err_cnt = err_cnt + 1;

        // Read ARRAY_CFG register
        axi_read(ADDR_ARRAY_CFG, read_data);
        $display("[AXI] ARRAY_CFG = 0x%08h (COLS=%0d, ROWS=%0d)",
                 read_data, read_data[15:8], read_data[7:0]);
        if (read_data[7:0] !== ROWS[7:0] || read_data[15:8] !== COLS[7:0])
            err_cnt = err_cnt + 1;

        $display("[TB] Loading Input Buffer A...");
        for (i = 0; i < K_DIM; i = i + 1) begin
            a_row = {(ROWS*DATA_WIDTH){1'b0}};
            for (j = 0; j < ROWS; j = j + 1) begin
                a_row[(j*DATA_WIDTH) +: DATA_WIDTH] = mem_a[j*K_DIM + i];
            end
            @(posedge clk);
            host_we_a = 1;
            host_addr_a = i[ADDR_WIDTH-1:0];
            host_wdata_a = a_row;
        end
        @(posedge clk);
        host_we_a = 0;

        $display("[TB] Loading Weight Buffer B...");
        for (i = 0; i < K_DIM; i = i + 1) begin
            b_row = {(COLS*DATA_WIDTH){1'b0}};
            for (j = 0; j < COLS; j = j + 1) begin
                b_row[(j*DATA_WIDTH) +: DATA_WIDTH] = mem_b[i*COLS + j];
            end
            @(posedge clk);
            host_we_b = 1;
            host_addr_b = i[ADDR_WIDTH-1:0];
            host_wdata_b = b_row;
        end
        @(posedge clk);
        host_we_b = 0;

        $display("[AXI] Writing K_DIM = %0d", K_DIM);
        axi_write(ADDR_KDIM, K_DIM);

        $display("[AXI] Writing CTRL = 1 (start)");
        axi_write(ADDR_CTRL, 32'h0000_0001);

        $display("[AXI] Polling STATUS register...");
        timeout = 0;
        read_data = 0;
        while (read_data[0] !== 1'b1 && timeout < 100) begin
            axi_read(ADDR_STATUS, read_data);
            timeout = timeout + 1;
        end

        if (timeout >= 100) begin
            $display("[AXI] ERROR: Timeout polling for done!");
            $finish;
        end

        $display("[AXI] STATUS = 0x%08h (done=%b, busy=%b, state=%0d)",
                 read_data, read_data[0], read_data[1], read_data[4:2]);


        axi_read(ADDR_PERF_TOT, read_data);
        $display("[AXI] PERF_TOTAL   = %0d cycles", read_data);

        axi_read(ADDR_PERF_COMP, read_data);
        $display("[AXI] PERF_COMPUTE = %0d cycles", read_data);


        @(posedge clk);
        host_re_c = 1;
        host_addr_c = 0;
        @(posedge clk);
        @(posedge clk);
        host_re_c = 0;

        
        for (i = 0; i < ROWS; i = i + 1) begin
            for (j = 0; j < COLS; j = j + 1) begin
                act_val = host_rdata_c[((i*COLS + j)*ACC_WIDTH) +: ACC_WIDTH];
                exp_val = mem_c_exp[i*COLS + j];

                if (act_val !== exp_val) begin
                    $display("  MISMATCH C[%0d][%0d]: Expected=%0d  Actual=%0d",
                             i, j, $signed(exp_val), $signed(act_val));
                    err_cnt = err_cnt + 1;
                end
            end
        end

        if (err_cnt == 0) begin
            $display("\n[ PASS ] AXI SIMULATION PASSED!");
        end else begin
            $display("\n[ FAIL ] AXI SIMULATION FAILED: %0d errors.", err_cnt);
        end

        #20;
        $finish;
    end

endmodule
