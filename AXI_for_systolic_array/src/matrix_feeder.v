`timescale 1ns / 1ps

module matrix_feeder #(
    parameter NUM_ROWS   = 4,
    parameter NUM_COLS   = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                                              clk,
    input  wire                                              rst,
    input  wire                                              start,

    input  wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     matrix_a_flat,  // row*NUM_COLS+col
    input  wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     weight_flat,    // row*NUM_COLS+col

    output reg  signed [NUM_ROWS*DATA_WIDTH-1:0]              a_in,
    output reg                                                load_weight,
    output reg  signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     weight_in,

    output reg                                                busy,
    output reg                                                done,
    output reg                                                out_valid
);

    localparam FEED_CYCLES  = NUM_ROWS + NUM_COLS - 1;   // 7 for 4x4
    localparam DRAIN_CYCLES = NUM_ROWS + NUM_COLS + 2;   // 10 for 4x4 (matches tb flush)

    localparam S_IDLE   = 3'd0,
               S_LOAD    = 3'd1,
               S_STREAM  = 3'd2,
               S_DRAIN   = 3'd3,
               S_DONE    = 3'd4;

    reg [2:0] state;
    reg [7:0] cnt;

    reg signed [DATA_WIDTH-1:0] matA [0:NUM_ROWS-1][0:NUM_COLS-1];

    integer r, c;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            cnt         <= 0;
            a_in        <= 0;
            load_weight <= 0;
            weight_in   <= 0;
            busy        <= 0;
            done        <= 0;
            out_valid   <= 0;
        end else begin
            out_valid   <= 0;
            load_weight <= 0;

            case (state)

                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        for (r = 0; r < NUM_ROWS; r = r + 1)
                            for (c = 0; c < NUM_COLS; c = c + 1)
                                matA[r][c] <= matrix_a_flat[((r*NUM_COLS+c+1)*DATA_WIDTH)-1 -: DATA_WIDTH];
                        weight_in   <= weight_flat;
                        load_weight <= 1;
                        busy        <= 1;
                        cnt         <= 0;
                        state       <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    cnt   <= 0;
                    a_in  <= 0;
                    state <= S_STREAM;
                end

                S_STREAM: begin
                    for (r = 0; r < NUM_ROWS; r = r + 1) begin
                        if ((cnt >= r) && (cnt - r < NUM_COLS))
                            a_in[((r+1)*DATA_WIDTH)-1 -: DATA_WIDTH] <= matA[r][cnt - r];
                        else
                            a_in[((r+1)*DATA_WIDTH)-1 -: DATA_WIDTH] <= 0;
                    end

                    if (cnt == FEED_CYCLES - 1) begin
                        cnt   <= 0;
                        state <= S_DRAIN;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                S_DRAIN: begin
                    a_in <= 0;
                    if (cnt == DRAIN_CYCLES - 1) begin
                        out_valid <= 1;
                        busy      <= 0;
                        done      <= 1;
                        state     <= S_DONE;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                S_DONE: begin
                    done <= 1;
                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
