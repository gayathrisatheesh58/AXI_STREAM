`timescale 1ns / 1ps

module systolic_array_4x4_top #(
    parameter NUM_ROWS   = 4,
    parameter NUM_COLS   = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                                              clk,
    input  wire                                              rst,
    input  wire                                              start,

    input  wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     matrix_a_flat,
    input  wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]     weight_flat,

    output wire signed [NUM_COLS*(2*DATA_WIDTH+1)-1:0]        acc_out,
    output wire                                                out_valid,
    output wire                                                busy,
    output wire                                                done
);

    wire signed [NUM_ROWS*DATA_WIDTH-1:0]          a_in_wire;
    wire                                            load_weight_wire;
    wire signed [NUM_ROWS*NUM_COLS*DATA_WIDTH-1:0]  weight_in_wire;
    wire signed [NUM_ROWS*DATA_WIDTH-1:0]           a_out_unused;

    matrix_feeder #(
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .DATA_WIDTH (DATA_WIDTH)
    ) feeder_inst (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .matrix_a_flat  (matrix_a_flat),
        .weight_flat    (weight_flat),
        .a_in           (a_in_wire),
        .load_weight    (load_weight_wire),
        .weight_in      (weight_in_wire),
        .busy           (busy),
        .done           (done),
        .out_valid      (out_valid)
    );

    systolic_array_4x4 #(
        .NUM_ROWS   (NUM_ROWS),
        .NUM_COLS   (NUM_COLS),
        .DATA_WIDTH (DATA_WIDTH)
    ) array_inst (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight_wire),
        .weight_in   (weight_in_wire),
        .a_in        (a_in_wire),
        .acc_out     (acc_out),
        .a_out       (a_out_unused)
    );

endmodule