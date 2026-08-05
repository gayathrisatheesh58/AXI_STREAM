`timescale 1ns / 1ps

module processing_element_2d #(
    parameter DATA_WIDTH = 8
)(
    input  wire                                clk,
    input  wire                                rst,

    input  wire                                load_weight,
    input  wire signed [DATA_WIDTH-1:0]        weight_in,

    input  wire signed [DATA_WIDTH-1:0]        a_in,
    output reg  signed [DATA_WIDTH-1:0]        a_out,      // → next PE right (a_in delayed 1 cycle)

    input  wire signed [(2*DATA_WIDTH):0]      psum_in,    // partial sum from PE above
    output reg  signed [(2*DATA_WIDTH):0]      psum_out    // partial sum to PE below
);

    reg signed [DATA_WIDTH-1:0]   w_reg;
    reg signed [(2*DATA_WIDTH)-1:0] product_reg;

    // weight, stationary, loaded once
    always @(posedge clk) begin
        if (rst)
            w_reg <= 0;
        else if (load_weight)
            w_reg <= weight_in;
    end

    // horizontal forwarding - same as original PE
    always @(posedge clk) begin
        if (rst)
            a_out <= 0;
        else
            a_out <= a_in;
    end

    // multiply stage
    always @(posedge clk) begin
        if (rst)
            product_reg <= 0;
        else
            product_reg <= a_in * w_reg;
    end

    // vertical accumulate - psum_in (from above) + local product, forwarded down
    always @(posedge clk) begin
        if (rst)
            psum_out <= 0;
        else
            psum_out <= psum_in + product_reg;
    end

endmodule
