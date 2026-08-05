`timescale 1ns / 1ps

module systolic_array_4x4_top_tb;

    localparam NUM_ROWS   = 4;
    localparam NUM_COLS   = 4;
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH  = (2 * DATA_WIDTH) + 1;
    localparam FEED_CYCLES  = NUM_ROWS + NUM_COLS - 1;
    localparam DRAIN_CYCLES = NUM_ROWS + NUM_COLS + 2;

    localparam RS_IDLE = 0, RS_LOAD = 1, RS_STREAM = 2, RS_DRAIN = 3, RS_DONE = 4;

    localparam CLK_PERIOD = 10;

    reg clk, rst, start;
    reg signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0] matrix_a_flat;
    reg signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0] weight_flat;

    wire signed [NUM_COLS*ACC_WIDTH-1:0] acc_out;
    wire out_valid, busy, done;

    systolic_array_4x4_top #(
        .NUM_ROWS(NUM_ROWS), .NUM_COLS(NUM_COLS), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk), .rst(rst), .start(start),
        .matrix_a_flat(matrix_a_flat), .weight_flat(weight_flat),
        .acc_out(acc_out), .out_valid(out_valid), .busy(busy), .done(done)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer stim_matA      [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer stim_weight2d  [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer ref_chain [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_w     [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_prod  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer ref_psum  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_prod  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_psum  [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_w     [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer rf_matA        [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer rf_weight2d    [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_rf_matA    [0:NUM_ROWS-1][0:NUM_COLS-1];
    integer new_rf_weight2d[0:NUM_ROWS-1][0:NUM_COLS-1];

    integer rf_state, rf_cnt, rf_a_in [0:NUM_ROWS-1], rf_load_weight, rf_busy, rf_done, rf_out_valid;
    integer new_rf_state, new_rf_cnt, new_rf_a_in [0:NUM_ROWS-1], new_rf_load_weight, new_rf_busy, new_rf_done, new_rf_out_valid;

    integer error_count, test_num;
    integer r, c;

    task load_matrix_bus;
        begin
            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1) begin
                    matrix_a_flat[((r*NUM_COLS+c+1)*DATA_WIDTH)-1 -: DATA_WIDTH] = stim_matA[r][c];
                    weight_flat  [((r*NUM_COLS+c+1)*DATA_WIDTH)-1 -: DATA_WIDTH] = stim_weight2d[r][c];
                end
        end
    endtask

    task step;
        input in_start;
        begin
            start = in_start;

            for (r = 0; r < NUM_ROWS; r = r + 1)
                ref_chain[r][0] = rf_a_in[r];

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1)
                    new_prod[r][c] = ref_chain[r][c] * ref_w[r][c];

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1) begin
                    if (r == 0)
                        new_psum[r][c] = new_prod[r][c];
                    else
                        new_psum[r][c] = ref_psum[r-1][c] + new_prod[r][c];
                end

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1)
                    new_w[r][c] = rf_load_weight ? rf_weight2d[r][c] : ref_w[r][c];

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = NUM_COLS-1; c >= 1; c = c - 1)
                    ref_chain[r][c] = ref_chain[r][c-1];

            new_rf_out_valid = 0;
            new_rf_load_weight = 0;

            case (rf_state)
                RS_IDLE: begin
                    new_rf_done = 0;
                    if (in_start) begin
                        for (r = 0; r < NUM_ROWS; r = r + 1)
                            for (c = 0; c < NUM_COLS; c = c + 1) begin
                                new_rf_matA[r][c]     = stim_matA[r][c];
                                new_rf_weight2d[r][c] = stim_weight2d[r][c];
                            end
                        new_rf_load_weight = 1;
                        new_rf_busy = 1;
                        new_rf_cnt  = 0;
                        new_rf_state = RS_LOAD;
                    end else begin
                        new_rf_busy = rf_busy;
                        new_rf_cnt  = rf_cnt;
                        new_rf_state = RS_IDLE;
                        for (r = 0; r < NUM_ROWS; r = r + 1)
                            for (c = 0; c < NUM_COLS; c = c + 1) begin
                                new_rf_matA[r][c]     = rf_matA[r][c];
                                new_rf_weight2d[r][c] = rf_weight2d[r][c];
                            end
                    end
                    for (r = 0; r < NUM_ROWS; r = r + 1) new_rf_a_in[r] = 0;
                end

                RS_LOAD: begin
                    new_rf_cnt = 0;
                    for (r = 0; r < NUM_ROWS; r = r + 1) new_rf_a_in[r] = 0;
                    new_rf_state = RS_STREAM;
                    new_rf_busy = rf_busy; new_rf_done = rf_done;
                    for (r = 0; r < NUM_ROWS; r = r + 1)
                        for (c = 0; c < NUM_COLS; c = c + 1) begin
                            new_rf_matA[r][c] = rf_matA[r][c];
                            new_rf_weight2d[r][c] = rf_weight2d[r][c];
                        end
                end

                RS_STREAM: begin
                    for (r = 0; r < NUM_ROWS; r = r + 1) begin
                        if ((rf_cnt >= r) && (rf_cnt - r < NUM_COLS))
                            new_rf_a_in[r] = rf_matA[r][rf_cnt - r];
                        else
                            new_rf_a_in[r] = 0;
                    end
                    if (rf_cnt == FEED_CYCLES - 1) begin
                        new_rf_cnt = 0;
                        new_rf_state = RS_DRAIN;
                    end else begin
                        new_rf_cnt = rf_cnt + 1;
                        new_rf_state = RS_STREAM;
                    end
                    new_rf_busy = rf_busy; new_rf_done = rf_done;
                    for (r = 0; r < NUM_ROWS; r = r + 1)
                        for (c = 0; c < NUM_COLS; c = c + 1) begin
                            new_rf_matA[r][c] = rf_matA[r][c];
                            new_rf_weight2d[r][c] = rf_weight2d[r][c];
                        end
                end

                RS_DRAIN: begin
                    for (r = 0; r < NUM_ROWS; r = r + 1) new_rf_a_in[r] = 0;
                    if (rf_cnt == DRAIN_CYCLES - 1) begin
                        new_rf_out_valid = 1;
                        new_rf_busy = 0;
                        new_rf_done = 1;
                        new_rf_state = RS_DONE;
                        new_rf_cnt = rf_cnt;
                    end else begin
                        new_rf_cnt = rf_cnt + 1;
                        new_rf_state = RS_DRAIN;
                        new_rf_busy = rf_busy;
                        new_rf_done = rf_done;
                    end
                    for (r = 0; r < NUM_ROWS; r = r + 1)
                        for (c = 0; c < NUM_COLS; c = c + 1) begin
                            new_rf_matA[r][c] = rf_matA[r][c];
                            new_rf_weight2d[r][c] = rf_weight2d[r][c];
                        end
                end

                RS_DONE: begin
                    new_rf_done = 1;
                    new_rf_busy = 0;
                    new_rf_cnt = rf_cnt;
                    for (r = 0; r < NUM_ROWS; r = r + 1) new_rf_a_in[r] = rf_a_in[r];
                    for (r = 0; r < NUM_ROWS; r = r + 1)
                        for (c = 0; c < NUM_COLS; c = c + 1) begin
                            new_rf_matA[r][c] = rf_matA[r][c];
                            new_rf_weight2d[r][c] = rf_weight2d[r][c];
                        end
                    if (!in_start)
                        new_rf_state = RS_IDLE;
                    else
                        new_rf_state = RS_DONE;
                end

                default: begin
                    new_rf_state = RS_IDLE; new_rf_cnt = 0; new_rf_busy = 0; new_rf_done = 0;
                    for (r = 0; r < NUM_ROWS; r = r + 1) new_rf_a_in[r] = 0;
                    for (r = 0; r < NUM_ROWS; r = r + 1)
                        for (c = 0; c < NUM_COLS; c = c + 1) begin
                            new_rf_matA[r][c] = 0; new_rf_weight2d[r][c] = 0;
                        end
                end
            endcase

            @(posedge clk); #1;

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1) begin
                    ref_prod[r][c] = new_prod[r][c];
                    ref_psum[r][c] = new_psum[r][c];
                    ref_w[r][c]    = new_w[r][c];
                    rf_matA[r][c]     = new_rf_matA[r][c];
                    rf_weight2d[r][c] = new_rf_weight2d[r][c];
                end

            rf_state       = new_rf_state;
            rf_cnt         = new_rf_cnt;
            rf_load_weight = new_rf_load_weight;
            rf_busy        = new_rf_busy;
            rf_done        = new_rf_done;
            rf_out_valid   = new_rf_out_valid;
            for (r = 0; r < NUM_ROWS; r = r + 1) rf_a_in[r] = new_rf_a_in[r];

            for (c = 0; c < NUM_COLS; c = c + 1) begin
                if ($signed(acc_out[((c+1)*ACC_WIDTH)-1 -: ACC_WIDTH]) !==
                    ref_psum[NUM_ROWS-1][c][ACC_WIDTH-1:0]) begin
                    $display("  [FAIL] t=%0t | TC%0d | COL[%0d] acc: got %0d, exp %0d",
                             $time, test_num, c,
                             $signed(acc_out[((c+1)*ACC_WIDTH)-1 -: ACC_WIDTH]),
                             ref_psum[NUM_ROWS-1][c]);
                    error_count = error_count + 1;
                end else begin
                    $display("  [PASS] t=%0t | TC%0d | COL[%0d] acc=%0d",
                             $time, test_num, c,
                             $signed(acc_out[((c+1)*ACC_WIDTH)-1 -: ACC_WIDTH]));
                end
            end

            if (busy !== rf_busy[0]) begin
                $display("  [FAIL] t=%0t | TC%0d | busy: got %0d, exp %0d", $time, test_num, busy, rf_busy);
                error_count = error_count + 1;
            end
            if (done !== rf_done[0]) begin
                $display("  [FAIL] t=%0t | TC%0d | done: got %0d, exp %0d", $time, test_num, done, rf_done);
                error_count = error_count + 1;
            end
            if (out_valid !== rf_out_valid[0]) begin
                $display("  [FAIL] t=%0t | TC%0d | out_valid: got %0d, exp %0d", $time, test_num, out_valid, rf_out_valid);
                error_count = error_count + 1;
            end else if (rf_out_valid) begin
                $display("  [PASS] t=%0t | TC%0d | out_valid pulsed correctly", $time, test_num);
            end
        end
    endtask

    integer i;

    task do_reset;
        begin
            rst = 1; start = 0;
            @(posedge clk); #1;
            @(posedge clk); #1;

            for (r = 0; r < NUM_ROWS; r = r + 1)
                for (c = 0; c < NUM_COLS; c = c + 1) begin
                    ref_chain[r][c] = 0; ref_w[r][c] = 0; ref_prod[r][c] = 0; ref_psum[r][c] = 0;
                    rf_matA[r][c] = 0; rf_weight2d[r][c] = 0;
                end
            rf_state = RS_IDLE; rf_cnt = 0; rf_load_weight = 0;
            rf_busy = 0; rf_done = 0; rf_out_valid = 0;
            for (r = 0; r < NUM_ROWS; r = r + 1) rf_a_in[r] = 0;

            rst = 0;
        end
    endtask

    task run_test;
        integer s;
        begin
            load_matrix_bus;
            step(1);
            for (s = 0; s < 20; s = s + 1)
                step(0);
        end
    endtask

    initial begin
        error_count = 0; test_num = 0;
        clk = 0; rst = 1; start = 0;
        matrix_a_flat = 0; weight_flat = 0;

        $display("================================================================");
        $display("  Self-Checking Testbench : systolic_array_4x4_top (feeder + array)");
        $display("================================================================");

        do_reset;

        $display("\n--- TC1: Uniform rows [1,2,3,4], W=1 (replicates array-level TC3) ---");
        test_num = 1;
        for (r = 0; r < NUM_ROWS; r = r + 1)
            for (c = 0; c < NUM_COLS; c = c + 1) begin
                stim_matA[r][c] = c + 1;
                stim_weight2d[r][c] = 1;
            end
        run_test;
        do_reset;

        $display("\n--- TC2: All a=4, per-column weights {2,3,5,7} (replicates array-level TC4) ---");
        test_num = 2;
        for (r = 0; r < NUM_ROWS; r = r + 1)
            for (c = 0; c < NUM_COLS; c = c + 1) begin
                stim_matA[r][c] = 4;
            end
        for (r = 0; r < NUM_ROWS; r = r + 1) begin
            stim_weight2d[r][0] = 2; stim_weight2d[r][1] = 3;
            stim_weight2d[r][2] = 5; stim_weight2d[r][3] = 7;
        end
        run_test;
        do_reset;

        $display("\n--- TC3: Distinct 4x4 matrix and distinct per-PE weights (true 2D matmul) ---");
        test_num = 3;
        stim_matA[0][0]=1; stim_matA[0][1]=2; stim_matA[0][2]=3; stim_matA[0][3]=4;
        stim_matA[1][0]=5; stim_matA[1][1]=6; stim_matA[1][2]=7; stim_matA[1][3]=8;
        stim_matA[2][0]=9; stim_matA[2][1]=10; stim_matA[2][2]=11; stim_matA[2][3]=12;
        stim_matA[3][0]=13; stim_matA[3][1]=14; stim_matA[3][2]=15; stim_matA[3][3]=16;

        stim_weight2d[0][0]=1; stim_weight2d[0][1]=0; stim_weight2d[0][2]=-1; stim_weight2d[0][3]=2;
        stim_weight2d[1][0]=0; stim_weight2d[1][1]=1; stim_weight2d[1][2]=2; stim_weight2d[1][3]=-1;
        stim_weight2d[2][0]=2; stim_weight2d[2][1]=-1; stim_weight2d[2][2]=1; stim_weight2d[2][3]=0;
        stim_weight2d[3][0]=-1; stim_weight2d[3][1]=2; stim_weight2d[3][2]=0; stim_weight2d[3][3]=1;
        run_test;
        do_reset;

        $display("\n================================================================");
        if (error_count == 0)
            $display("  RESULT : ALL TESTS PASSED (0 errors)");
        else
            $display("  RESULT : FAILED - %0d error(s) detected", error_count);
        $display("================================================================\n");

        $finish;
    end

    initial begin
        #500000;
        $display("[WATCHDOG] Simulation exceeded time limit. Terminating.");
        $finish;
    end

    initial begin
        $dumpfile("systolic_array_4x4_top_tb.vcd");
        $dumpvars(0, systolic_array_4x4_top_tb);
    end

endmodule