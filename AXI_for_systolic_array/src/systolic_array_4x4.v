`timescale 1ns / 1ps

module systolic_array_4x4 #(
    parameter NUM_ROWS   = 4,
    parameter NUM_COLS   = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                                              clk,
    input  wire                                              rst,

    input  wire                                              load_weight,
    input  wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     weight_in,   // [row*NUM_COLS+col] packed

    input  wire signed [NUM_ROWS*DATA_WIDTH-1:0]              a_in,        // one activation stream per row, enters col 0

    output wire signed [NUM_COLS*(2*DATA_WIDTH+1)-1:0]        acc_out,     // one result per column, exits bottom row

    output wire signed [NUM_ROWS*DATA_WIDTH-1:0]              a_out        // right-edge forwarding, for chaining arrays
);

    localparam ACC_WIDTH = (2*DATA_WIDTH) + 1;

    // horizontal activation chain: a_grid[row][col] feeds PE[row][col].a_in
    // a_grid[row][0]        = external a_in for that row
    // a_grid[row][col] (>0) = PE[row][col-1].a_out
    wire signed [DATA_WIDTH-1:0] a_grid [0:NUM_ROWS-1][0:NUM_COLS];

    // vertical psum chain: psum_grid[row][col] feeds PE[row][col].psum_in
    // psum_grid[0][col]        = 0 (top boundary, no partial sum above row 0)
    // psum_grid[row][col] (>0) = PE[row-1][col].psum_out
    wire signed [ACC_WIDTH-1:0] psum_grid [0:NUM_ROWS][0:NUM_COLS-1];

    genvar r, c;
    generate
        for (r = 0; r < NUM_ROWS; r = r + 1) begin : row_gen
            assign a_grid[r][0] = a_in[((r+1)*DATA_WIDTH)-1 : r*DATA_WIDTH];
            assign a_out[((r+1)*DATA_WIDTH)-1 : r*DATA_WIDTH] = a_grid[r][NUM_COLS];
        end

        for (c = 0; c < NUM_COLS; c = c + 1) begin : col_gen
            assign psum_grid[0][c] = 0;
            assign acc_out[((c+1)*ACC_WIDTH)-1 : c*ACC_WIDTH] = psum_grid[NUM_ROWS][c];
        end

        for (r = 0; r < NUM_ROWS; r = r + 1) begin : pe_row
            for (c = 0; c < NUM_COLS; c = c + 1) begin : pe_col
                processing_element_2d #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk         (clk),
                    .rst         (rst),
                    .load_weight (load_weight),
                    .weight_in   (weight_in[((r*NUM_COLS+c+1)*DATA_WIDTH)-1 : (r*NUM_COLS+c)*DATA_WIDTH]),
                    .a_in        (a_grid[r][c]),
                    .a_out       (a_grid[r][c+1]),
                    .psum_in     (psum_grid[r][c]),
                    .psum_out    (psum_grid[r+1][c])
                );
            end
        end
    endgenerate

endmodule
