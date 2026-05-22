`timescale 1ns/1ps

module tb_pe;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;
    
    // Signals
    reg  clk;
    reg  rst_n;
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  signed [DATA_WIDTH-1:0] b_in;
    reg  valid_in;
    
    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire signed [ACC_WIDTH-1:0]  acc_out;
    wire valid_out;

    // Instantiate PE
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_pe (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(a_in),
        .b_in(b_in),
        .valid_in(valid_in),
        .a_out(a_out),
        .b_out(b_out),
        .acc_out(acc_out),
        .valid_out(valid_out)
    );

    // Clock generation: 100 MHz
    always #5 clk = ~clk;
    
    integer errors;

    initial begin
        // Init
        clk = 0;
        rst_n = 0;
        a_in = 0;
        b_in = 0;
        valid_in = 0;
        errors = 0;
        
        // Release reset
        #20;
        @(posedge clk);
        rst_n = 1;
        
        // ---- Test 1: Single MAC 3 * 4 = 12 ----
        @(posedge clk);
        a_in = 3;
        b_in = 4;
        valid_in = 1;
        
        @(posedge clk);
        valid_in = 0;
        a_in = 0;
        b_in = 0;
        
        @(posedge clk); // let it settle
        if (acc_out !== 32'sd12) begin
            $display("FAIL Test1: expected 12, got %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("PASS Test1: 3*4 = %0d", acc_out);
        end
        
        // ---- Test 2: Accumulate: + (-2)*5 = 12 + (-10) = 2 ----
        @(posedge clk);
        a_in = -2;
        b_in = 5;
        valid_in = 1;
        
        @(posedge clk);
        valid_in = 0;
        a_in = 0;
        b_in = 0;
        
        @(posedge clk);
        if (acc_out !== 32'sd2) begin
            $display("FAIL Test2: expected 2, got %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("PASS Test2: 12 + (-2)*5 = %0d", acc_out);
        end
        
        // ---- Test 3: Data forwarding check ----
        @(posedge clk);
        a_in = 8'sd42;
        b_in = -8'sd7;
        valid_in = 1;
        
        @(posedge clk);
        // a_out and b_out should now hold the values from last cycle
        if (a_out !== 8'sd42) begin
            $display("FAIL Test3: a_out expected 42, got %0d", a_out);
            errors = errors + 1;
        end else begin
            $display("PASS Test3: a_out forwarded correctly = %0d", a_out);
        end
        if (b_out !== -8'sd7) begin
            $display("FAIL Test3: b_out expected -7, got %0d", b_out);
            errors = errors + 1;
        end else begin
            $display("PASS Test3: b_out forwarded correctly = %0d", b_out);
        end
        
        valid_in = 0;
        a_in = 0;
        b_in = 0;
        
        // ---- Test 4: Reset clears accumulator ----
        @(posedge clk);
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        if (acc_out !== 0) begin
            $display("FAIL Test4: expected 0 after reset, got %0d", acc_out);
            errors = errors + 1;
        end else begin
            $display("PASS Test4: Reset clears accumulator to 0");
        end
        
        // ---- Summary ----
        if (errors == 0) begin
            $display("\n[ PASS ] PE TESTBENCH PASSED!");
        end else begin
            $display("\n[ FAIL ] PE TESTBENCH FAILED: %0d errors", errors);
        end
        
        $finish;
    end

endmodule
