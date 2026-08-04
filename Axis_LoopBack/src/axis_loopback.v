
`timescale 1ns / 1ps
module axis_loopback #(
    parameter DATA_WIDTH = 32
) (

    // ── AXI4-Stream global signals ────────────────────────────────────────────
    // aclk    : connect to PS FCLK_CLK0
    // aresetn : active-low; connect to processor_system_reset peripheral_aresetn[0]
    input  wire        aclk,
    input  wire        aresetn,

    // ── S_AXIS: Slave - receives data from DMA MM2S channel ──────────────────
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // ── M_AXIS: Master - sends data to DMA S2MM channel ──────────────────────
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready

);

    // =========================================================================
    // Internal storage register
    //
    // data_valid : 0 = register empty (ready to receive)
    //              1 = register full  (ready to transmit)
    // =========================================================================
    reg [31:0] data_reg;
    reg        data_valid;
    reg        last_reg;

    // =========================================================================
    // Combinational output assignments
    //
    // s_axis_tready : we can accept a word whenever the register is empty
    // m_axis_tvalid : we have a word to send whenever the register is full
    //
    // These update immediately when data_valid changes - no clock needed.
    // =========================================================================
    assign s_axis_tready = ~data_valid;
    assign m_axis_tdata  =  data_reg;
    assign m_axis_tvalid =  data_valid;
    assign m_axis_tlast  =  last_reg;

    // =========================================================================
    // Sequential logic - one always block handles both receive and transmit
    // =========================================================================
    always @(posedge aclk) begin

        if (!aresetn) begin
            // Active-low reset: clear register
            data_reg <= {DATA_WIDTH{1'b0}};
            data_valid <= 1'b0;
            last_reg   <= 1'b0;

        end else begin

            // ── RECEIVE ──────────────────────────────────────────────────────
            // Handshake: tvalid=1 AND tready=1 at the rising edge.
            // tready is 1 when data_valid=0, so this only fires when empty.
            if (s_axis_tvalid && s_axis_tready) begin
                data_reg   <= s_axis_tdata;
                data_valid <= 1'b1;
                last_reg   <= s_axis_tlast;
            end

            // ── TRANSMIT ─────────────────────────────────────────────────────
            // Handshake: tvalid=1 AND tready=1 at the rising edge.
            // Once the downstream DMA accepts the word, clear the register.
            // else-if ensures receive and transmit cannot fire simultaneously
            // (the learning limitation described above).
            else if (m_axis_tvalid && m_axis_tready) begin
                data_valid <= 1'b0;
            end

        end
    end

endmodule
