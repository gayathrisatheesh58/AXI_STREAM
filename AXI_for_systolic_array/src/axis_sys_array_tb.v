`timescale 1ns / 1ps

module systolic_array_4x4_tb;

    localparam NUM_ROWS   = 4;
    localparam NUM_COLS   = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = (2 * DATA_WIDTH) + 1;

    localparam CLK_PERIOD = 10;

    reg                                            clk;
    reg                                            rst;
    reg  signed [NUM_ROWS*DATA_WIDTH-1:0]          a_in;
    reg                                            load_weight;
    reg  signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0] weight_in;

    wire signed [NUM_COLS*ACC_WIDTH-1:0]           acc_out;
    wire signed [NUM_ROWS*DATA_WIDTH-1:0]          a_out;

    reg signed [DATA_WIDTH-1:0] w_matrix [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer ref_chain [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_w     [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_prod  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_psum  [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer new_prod  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_psum  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_w     [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer saved_last_chain [0:NUM_ROWS-1];

    integer error_count;
    integer test_num;

    systolic_array_4x4 #(
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight),
        .weight_in   (weight_in),
        .a_in        (a_in),
        .acc_out     (acc_out),
        .a_out       (a_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pr, pc;

    task pack_weight_bus;
        begin
            for (pr = 0; pr < NUM_ROWS; pr = pr + 1)
                for (pc = 0; pc < NUM_COLS; pc = pc + 1)
                    weight_in[((pr*NUM_COLS+pc+1)*DATA_WIDTH)-1 : (pr*NUM_COLS+pc)*DATA_WIDTH] = w_matrix[pr][pc];
        end
    endtask

    task set_all_weights;
        input signed [DATA_WIDTH-1:0] val;
        begin
            for (pr = 0; pr < NUM_ROWS; pr = pr + 1)
                for (pc = 0; pc < NUM_COLS; pc = pc + 1)
                    w_matrix[pr][pc] = val;
        end
    endtask

    task set_col_weights;
        input signed [DATA_WIDTH-1:0] w0, w1, w2, w3;
        begin
            for (pr = 0; pr < NUM_ROWS; pr = pr + 1) begin
                w_matrix[pr][0] = w0;
                w_matrix[pr][1] = w1;
                w_matrix[pr][2] = w2;
                w_matrix[pr][3] = w3;
            end
        end
    endtask

    integer k, m;

    task apply_inputs;
        input signed [DATA_WIDTH-1:0] a0, a1, a2, a3;
        input                         in_load;
        begin
            ref_chain[0][0] = $signed(a0);
            ref_chain[1][0] = $signed(a1);
            ref_chain[2][0] = $signed(a2);
            ref_chain[3][0] = $signed(a3);

            a_in[1*DATA_WIDTH-1 : 0*DATA_WIDTH] = a0;
            a_in[2*DATA_WIDTH-1 : 1*DATA_WIDTH] = a1;
            a_in[3*DATA_WIDTH-1 : 2*DATA_WIDTH] = a2;
            a_in[4*DATA_WIDTH-1 : 3*DATA_WIDTH] = a3;

            load_weight = in_load;
            pack_weight_bus;

            @(posedge clk);
            #1;

            for (k = 0; k < NUM_ROWS; k = k + 1)
                saved_last_chain[k] = ref_chain[k][NUM_COLS-1];

            for (k = 0; k < NUM_ROWS; k = k + 1)
                for (m = 0; m < NUM_COLS; m = m + 1)
                    new_prod[k][m] = ref_chain[k][m] * ref_w[k][m];

            for (k = 0; k < NUM_ROWS; k = k + 1)
                for (m = 0; m < NUM_COLS; m = m + 1) begin
                    if (k == 0)
                        new_psum[k][m] = ref_prod[k][m];
                    else
                        new_psum[k][m] = ref_psum[k-1][m] + ref_prod[k][m];
                end

            for (k = 0; k < NUM_ROWS; k = k + 1)
                for (m = 0; m < NUM_COLS; m = m + 1)
                    new_w[k][m] = in_load ? w_matrix[k][m] : ref_w[k][m];

            for (k = 0; k < NUM_ROWS; k = k + 1)
                for (m = NUM_COLS-1; m >= 1; m = m - 1)
                    ref_chain[k][m] = ref_chain[k][m-1];

            for (k = 0; k < NUM_ROWS; k = k + 1)
                for (m = 0; m < NUM_COLS; m = m + 1) begin
                    ref_prod[k][m] = new_prod[k][m];
                    ref_psum[k][m] = new_psum[k][m];
                    ref_w[k][m]    = new_w[k][m];
                end

            for (m = 0; m < NUM_COLS; m = m + 1) begin
                if ($signed(acc_out[((m+1)*ACC_WIDTH)-1 -: ACC_WIDTH]) !==
                    ref_psum[NUM_ROWS-1][m][ACC_WIDTH-1:0]) begin
                    $display("  [FAIL] t=%0t | TC%0d | COL[%0d] acc: got %0d, exp %0d",
                             $time, test_num, m,
                             $signed(acc_out[((m+1)*ACC_WIDTH)-1 -: ACC_WIDTH]),
                             ref_psum[NUM_ROWS-1][m]);
                    error_count = error_count + 1;
                end else begin
                    $display("  [PASS] t=%0t | TC%0d | COL[%0d] acc=%0d",
                             $time, test_num, m,
                             $signed(acc_out[((m+1)*ACC_WIDTH)-1 -: ACC_WIDTH]));
                end
            end

            for (k = 0; k < NUM_ROWS; k = k + 1) begin
                if ($signed(a_out[((k+1)*DATA_WIDTH)-1 -: DATA_WIDTH]) !==
                    saved_last_chain[k][DATA_WIDTH-1:0]) begin
                    $display("  [FAIL] t=%0t | TC%0d | ROW[%0d] a_out: got %0d, exp %0d",
                             $time, test_num, k,
                             $signed(a_out[((k+1)*DATA_WIDTH)-1 -: DATA_WIDTH]),
                             saved_last_chain[k]);
                    error_count = error_count + 1;
                end else begin
                    $display("  [PASS] t=%0t | TC%0d | ROW[%0d] a_out=%0d",
                             $time, test_num, k,
                             $signed(a_out[((k+1)*DATA_WIDTH)-1 -: DATA_WIDTH]));
                end
            end
        end
    endtask

    integer f;

    task flush_pipeline;
        begin
            $display("  [FLUSH] Draining 4x4 array — %0d zero cycles", NUM_ROWS+NUM_COLS+2);
            for (f = 0; f < NUM_ROWS+NUM_COLS+2; f = f + 1)
                apply_inputs(0, 0, 0, 0, 1'b0);
        end
    endtask

    task do_reset;
        integer j, n;
        begin
            load_weight = 0; weight_in = 0; a_in = 0;
            rst = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;

            for (j = 0; j < NUM_ROWS; j = j + 1)
                for (n = 0; n < NUM_COLS; n = n + 1) begin
                    ref_chain[j][n] = 0;
                    ref_w[j][n]     = 0;
                    ref_prod[j][n]  = 0;
                    ref_psum[j][n]  = 0;
                end

            for (n = 0; n < NUM_COLS; n = n + 1) begin
                if (acc_out[((n+1)*ACC_WIDTH)-1 -: ACC_WIDTH] !== {ACC_WIDTH{1'b0}}) begin
                    $display("  [FAIL] t=%0t | RESET | COL[%0d] acc not zero: %0d",
                             $time, n, $signed(acc_out[((n+1)*ACC_WIDTH)-1 -: ACC_WIDTH]));
                    error_count = error_count + 1;
                end else
                    $display("  [PASS] t=%0t | RESET | COL[%0d] acc = 0", $time, n);
            end

            for (j = 0; j < NUM_ROWS; j = j + 1) begin
                if (a_out[((j+1)*DATA_WIDTH)-1 -: DATA_WIDTH] !== {DATA_WIDTH{1'b0}}) begin
                    $display("  [FAIL] t=%0t | RESET | ROW[%0d] a_out not zero: %0d",
                             $time, j, $signed(a_out[((j+1)*DATA_WIDTH)-1 -: DATA_WIDTH]));
                    error_count = error_count + 1;
                end else
                    $display("  [PASS] t=%0t | RESET | ROW[%0d] a_out = 0", $time, j);
            end

            rst = 0;
        end
    endtask

    integer i, ii;

    initial begin
        error_count = 0; test_num = 0;
        clk = 0; rst = 1;
        a_in = 0; load_weight = 0; weight_in = 0;
        for (i = 0; i < NUM_ROWS; i = i + 1)
            for (ii = 0; ii < NUM_COLS; ii = ii + 1) begin
                ref_chain[i][ii] = 0; ref_w[i][ii] = 0;
                ref_prod[i][ii]  = 0; ref_psum[i][ii] = 0;
                w_matrix[i][ii]  = 0;
            end

        $display("================================================================");
        $display("  Self-Checking Testbench : systolic_array_4x4");
        $display("  NUM_ROWS=%0d NUM_COLS=%0d DATA_WIDTH=%0d ACC_WIDTH=%0d",
                 NUM_ROWS, NUM_COLS, DATA_WIDTH, ACC_WIDTH);
        $display("================================================================");

        $display("\n--- TC1: Synchronous Reset ---");
        test_num = 1;
        do_reset;

        $display("\n--- TC2: Single Pulse — Row0 Wave (W=1 all, A=10 into row0) ---");
        test_num = 2;
        set_all_weights(8'd1);
        apply_inputs(8'd10, 8'd0, 8'd0, 8'd0, 1'b1);
        apply_inputs(8'd0,  8'd0, 8'd0, 8'd0, 1'b0);
        apply_inputs(8'd0,  8'd0, 8'd0, 8'd0, 1'b0);
        apply_inputs(8'd0,  8'd0, 8'd0, 8'd0, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC3: Staggered Row Feed (identity-like matmul pattern) ---");
        test_num = 3;
        set_all_weights(8'd1);
        apply_inputs(8'd1, 8'd0, 8'd0, 8'd0, 1'b1);
        apply_inputs(8'd2, 8'd1, 8'd0, 8'd0, 1'b0);
        apply_inputs(8'd3, 8'd2, 8'd1, 8'd0, 1'b0);
        apply_inputs(8'd4, 8'd3, 8'd2, 8'd1, 1'b0);
        apply_inputs(8'd0, 8'd4, 8'd3, 8'd2, 1'b0);
        apply_inputs(8'd0, 8'd0, 8'd4, 8'd3, 1'b0);
        apply_inputs(8'd0, 8'd0, 8'd0, 8'd4, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC4: Full Weighted Sum (W per col = {2,3,5,7}, a=4 all rows, 4 cycles) ---");
        test_num = 4;
        set_col_weights(8'd2, 8'd3, 8'd5, 8'd7);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b1);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC5: Weight Hold (load once, stream 6 cycles) ---");
        test_num = 5;
        set_all_weights(8'd4);
        apply_inputs(8'd1, 8'd1, 8'd1, 8'd1, 1'b1);
        apply_inputs(8'd5, 8'd5, 8'd5, 8'd5, 1'b0);
        apply_inputs(8'd5, 8'd5, 8'd5, 8'd5, 1'b0);
        apply_inputs(8'd5, 8'd5, 8'd5, 8'd5, 1'b0);
        apply_inputs(8'd5, 8'd5, 8'd5, 8'd5, 1'b0);
        apply_inputs(8'd5, 8'd5, 8'd5, 8'd5, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC6: Negative Activations (a=-5, W per col={2,3,4,5}) ---");
        test_num = 6;
        set_col_weights(8'd2, 8'd3, 8'd4, 8'd5);
        apply_inputs(-8'd5, -8'd5, -8'd5, -8'd5, 1'b1);
        apply_inputs(-8'd5, -8'd5, -8'd5, -8'd5, 1'b0);
        apply_inputs(-8'd5, -8'd5, -8'd5, -8'd5, 1'b0);
        apply_inputs(-8'd5, -8'd5, -8'd5, -8'd5, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC7: Mixed Weights (W per col={3,-3,5,-5}, a=4) ---");
        test_num = 7;
        set_col_weights(8'd3, -8'd3, 8'd5, -8'd5);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b1);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        apply_inputs(8'd4, 8'd4, 8'd4, 8'd4, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC8: Boundary Values (127x127, -128x-128) ---");
        test_num = 8;
        set_col_weights(8'd127, 8'd127, -8'd128, -8'd128);
        apply_inputs(8'd127, 8'd127, 8'd127, 8'd127, 1'b1);
        apply_inputs(8'd127, 8'd127, 8'd127, 8'd127, 1'b0);
        flush_pipeline;
        do_reset;

        $display("\n--- TC9: Mid-run Reset ---");
        test_num = 9;
        set_col_weights(8'd2, 8'd3, 8'd4, 8'd5);
        apply_inputs(8'd8, 8'd8, 8'd8, 8'd8, 1'b1);
        apply_inputs(8'd8, 8'd8, 8'd8, 8'd8, 1'b0);
        apply_inputs(8'd8, 8'd8, 8'd8, 8'd8, 1'b0);

        rst = 1;
        @(posedge clk); #1;

        for (i = 0; i < NUM_ROWS; i = i + 1)
            for (ii = 0; ii < NUM_COLS; ii = ii + 1) begin
                ref_chain[i][ii] = 0; ref_w[i][ii] = 0;
                ref_prod[i][ii]  = 0; ref_psum[i][ii] = 0;
            end

        for (ii = 0; ii < NUM_COLS; ii = ii + 1) begin
            if (acc_out[((ii+1)*ACC_WIDTH)-1 -: ACC_WIDTH] !== {ACC_WIDTH{1'b0}}) begin
                $display("  [FAIL] t=%0t | TC9 | COL[%0d] acc not zero: %0d",
                         $time, ii, $signed(acc_out[((ii+1)*ACC_WIDTH)-1 -: ACC_WIDTH]));
                error_count = error_count + 1;
            end else
                $display("  [PASS] t=%0t | TC9 | COL[%0d] acc = 0 after mid-reset", $time, ii);
        end
        rst = 0;

        $display("\n--- TC10: Long Accumulation (W per col={1,2,3,4}, 30 cycles) ---");
        test_num = 10;
        set_col_weights(8'd1, 8'd2, 8'd3, 8'd4);
        apply_inputs(8'd1, 8'd1, 8'd1, 8'd1, 1'b1);

        for (i = 0; i < 29; i = i + 1) begin
            apply_inputs(
                $signed(((i % 10) - 5)),
                $signed(((i % 10) - 5)),
                $signed(((i % 10) - 5)),
                $signed(((i % 10) - 5)),
                1'b0
            );
        end
        flush_pipeline;

        $display("\n================================================================");
        if (error_count == 0)
            $display("  RESULT : ALL TESTS PASSED (0 errors)");
        else
            $display("  RESULT : FAILED — %0d error(s) detected", error_count);
        $display("================================================================\n");

        $finish;
    end

    initial begin
        #500000;
        $display("[WATCHDOG] Simulation exceeded time limit. Terminating.");
        $finish;
    end

    initial begin
        $dumpfile("systolic_array_4x4_tb.vcd");
        $dumpvars(0, systolic_array_4x4_tb);
    end

endmodule
