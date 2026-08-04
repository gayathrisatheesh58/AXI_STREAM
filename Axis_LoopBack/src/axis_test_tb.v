`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Project : AXI-Stream DMA Loopback Test
// Module  : axis_loopback_tb
// Board   : Zybo Z7-10 (Zynq-7010)
// Author  : Gayathri Satheesh
//
// Purpose:
//   Simulate axis_loopback.v by pretending to be the AXI DMA.
//   Send values 10, 20, 30, 40 in one AXI-Stream transfer.
//   Verify the same values come back on the master side.
//
// ─── What you will see in the Vivado waveform ────────────────────────────────
//
//   Add these signals to the waveform window (they tell the whole story):
//
//     aclk
//     aresetn
//     s_axis_tvalid   ← testbench drives this
//     s_axis_tready   ← DUT drives this  (goes LOW when register is FULL)
//     s_axis_tdata    ← testbench drives this
//     s_axis_tlast    ← testbench drives this  (HIGH on word 40)
//     data_valid      ← DUT internal (add from UUT scope)
//     data_reg        ← DUT internal (add from UUT scope)
//     m_axis_tvalid   ← DUT drives this
//     m_axis_tready   ← testbench drives this
//     m_axis_tdata    ← DUT drives this
//     m_axis_tlast    ← DUT drives this
//
//   Expected waveform sequence per word:
//
//   Phase 1 - RECEIVE (data_valid=0, tready=1):
//     tvalid goes HIGH, tdata = word value
//     At posedge: tvalid=1 AND tready=1 → handshake → data_reg latches value
//     data_valid becomes 1, tready drops to 0
//
//   Phase 2 - TRANSMIT (data_valid=1, m_axis_tvalid=1):
//     m_axis_tvalid goes HIGH, m_axis_tdata = same value
//     When m_axis_tready=1: handshake → data_valid clears → tready goes HIGH again
//
// ─── Test cases ───────────────────────────────────────────────────────────────
//
//   TC1  : Reset check - tready=0 during reset, =1 after
//   TC2  : Send 10, 20, 30, 40 - basic loopback, TLAST on 40
//   TC3  : Backpressure - hold m_axis_tready LOW for 3 cycles then release
//   TC4  : Two consecutive transfers - module returns to ready state
//
// ─── Vivado simulation setup ──────────────────────────────────────────────────
//   Simulation sources (set axis_loopback_tb as top):
//     axis_loopback_tb.v
//     axis_loopback.v
//
//   Run time: 5 µs is more than enough.
//   After running, click "Window → Waveform" and add signals listed above.
//
//////////////////////////////////////////////////////////////////////////////////

module axis_loopback_tb;

    // =========================================================================
    // Clock and reset
    // =========================================================================
    reg aclk;
    reg aresetn;

    // 10 ns period = 100 MHz (matches Zybo Z7-10 default FCLK_CLK0)
    initial aclk = 0;
    always #5 aclk = ~aclk;

    // =========================================================================
    // DUT port connections
    // =========================================================================

    // S_AXIS - testbench drives (pretends to be DMA MM2S)
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;

    // M_AXIS - testbench receives (pretends to be DMA S2MM)
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    axis_loopback uut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tready (m_axis_tready)
    );

    // =========================================================================
    // Test tracking
    // =========================================================================
    integer tc_num;
    integer pass_count;
    integer fail_count;

    // =========================================================================
    // Task : do_reset
    // Holds aresetn LOW for 4 cycles, then releases it.
    // Waits 4 more cycles for the DUT to settle in S_IDLE.
    // =========================================================================
    task do_reset;
        begin
            @(negedge aclk);
            aresetn       = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = 32'd0;
            m_axis_tready = 1'b0;
            repeat(4) @(posedge aclk);

            @(negedge aclk);
            aresetn = 1'b1;
            repeat(4) @(posedge aclk);  // let DUT reach clean idle state
        end
    endtask

    // =========================================================================
    // Task : send_word
    // Drives one AXI-Stream word on the slave interface.
    // Waits until s_axis_tready is HIGH before presenting the word,
    // then holds tvalid until the handshake completes.
    //
    // AXI-Stream rule: once tvalid is asserted it MUST NOT be deasserted
    // until the handshake completes (tvalid=1 AND tready=1 at posedge).
    // =========================================================================
    task send_word;
        input [31:0] data;
        input        last;
        begin
            // Wait until DUT is ready to receive
            // (tready is combinationally ~data_valid, so it is 1 when empty)
            @(negedge aclk);
            while (!s_axis_tready) begin
                @(negedge aclk);
            end

            // Present word - drive on falling edge for setup margin
            s_axis_tdata  = data;
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = last;

            // Wait for rising edge where tvalid=1 AND tready=1 → handshake
            @(posedge aclk);

            // Deassert tvalid after handshake (on next falling edge)
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tdata  = 32'd0;
        end
    endtask

    // =========================================================================
    // Task : recv_word
    // Receives one AXI-Stream word on the master interface.
    // backpressure_cycles: how many cycles to hold m_axis_tready LOW first.
    // Captures tdata, tlast, checks against expected value.
    // =========================================================================
    task recv_word;
        input  [31:0]  expected_data;
        input          expected_last;
        input  integer backpressure_cycles;
        reg    [31:0]  got_data;
        reg            got_last;
        begin
            // Apply backpressure - hold tready low
            if (backpressure_cycles > 0) begin
                @(negedge aclk);
                m_axis_tready = 1'b0;
                repeat(backpressure_cycles) @(posedge aclk);
            end

            // Assert tready
            @(negedge aclk);
            m_axis_tready = 1'b1;

            // Wait until DUT presents valid data
            @(posedge aclk);
            while (!m_axis_tvalid) @(posedge aclk);

            // Capture at the handshake posedge
            got_data = m_axis_tdata;
            got_last = m_axis_tlast;

            // Deassert tready
            @(negedge aclk);
            m_axis_tready = 1'b0;

            // Check result
            if (got_data === expected_data && got_last === expected_last) begin
                $display("  TC%0d  PASS: received data=%-4d  tlast=%0b  (expected data=%-4d  tlast=%0b)",
                         tc_num, got_data, got_last, expected_data, expected_last);
                pass_count = pass_count + 1;
            end else begin
                $display("  TC%0d *FAIL: received data=%-4d  tlast=%0b  (expected data=%-4d  tlast=%0b)",
                         tc_num, got_data, got_last, expected_data, expected_last);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("=================================================================");
        $display(" axis_loopback Testbench");
        $display(" Board  : Zybo Z7-10 (Zynq-7010)");
        $display(" Clock  : 100 MHz (10 ns period)");
        $display(" Reset  : active-low (aresetn)");
        $display("=================================================================");
        $display("");
        $display(" Signals to add to waveform window:");
        $display("   aclk, aresetn");
        $display("   s_axis_tvalid, s_axis_tready, s_axis_tdata, s_axis_tlast");
        $display("   uut/data_valid  (internal - from UUT scope)");
        $display("   uut/data_reg    (internal - from UUT scope)");
        $display("   m_axis_tvalid, m_axis_tready, m_axis_tdata, m_axis_tlast");

        // -----------------------------------------------------------------
        // TC1 : Reset check
        // During reset: tready should be 0 (data_valid=0 so ~data_valid=1?
        // Actually: aresetn=0 forces data_valid=0 → s_axis_tready=~0=1.
        // After reset: data_valid=0, tready=1.  m_axis_tvalid=0.
        // -----------------------------------------------------------------
        tc_num = 1;
        $display("\n─────────────────────────────────────────────────────────────");
        $display(" TC1 : Reset check");
        $display("─────────────────────────────────────────────────────────────");
        do_reset;

        // tready is combinational ~data_valid. After reset data_valid=0 → tready=1.
        @(negedge aclk);
        if (s_axis_tready !== 1'b1) begin
            $display("  TC%0d *FAIL: s_axis_tready should be 1 after reset, got %0b", tc_num, s_axis_tready);
            fail_count = fail_count + 1;
        end else begin
            $display("  TC%0d  PASS: s_axis_tready = 1 after reset (register is empty)", tc_num);
            pass_count = pass_count + 1;
        end

        if (m_axis_tvalid !== 1'b0) begin
            $display("  TC%0d *FAIL: m_axis_tvalid should be 0 after reset, got %0b", tc_num, m_axis_tvalid);
            fail_count = fail_count + 1;
        end else begin
            $display("  TC%0d  PASS: m_axis_tvalid = 0 after reset (nothing to send)", tc_num);
            pass_count = pass_count + 1;
        end

        // -----------------------------------------------------------------
        // TC2 : Basic loopback - send 10, 20, 30, 40
        // This is the fundamental DMA communication test.
        // Each word is sent, then received back in order.
        // TLAST is asserted on the last word (40) to mark packet end.
        //
        // Waveform to observe per word:
        //   1. tvalid rises (testbench sends word)
        //   2. tready is 1 → handshake → data_valid goes 1, tready drops 0
        //   3. m_axis_tvalid rises (DUT outputs word)
        //   4. m_axis_tready goes 1 → handshake → data_valid clears, tready rises again
        // -----------------------------------------------------------------
        tc_num = 2;
        $display("\n─────────────────────────────────────────────────────────────");
        $display(" TC2 : Basic loopback  send→receive  [10, 20, 30, 40(LAST)]");
        $display("─────────────────────────────────────────────────────────────");
        do_reset;

        // Word 1: 10
        fork
            send_word(32'd10, 1'b0);
            recv_word(32'd10, 1'b0, 0);
        join

        // Word 2: 20
        fork
            send_word(32'd20, 1'b0);
            recv_word(32'd20, 1'b0, 0);
        join

        // Word 3: 30
        fork
            send_word(32'd30, 1'b0);
            recv_word(32'd30, 1'b0, 0);
        join

        // Word 4: 40 with TLAST
        fork
            send_word(32'd40, 1'b1);
            recv_word(32'd40, 1'b1, 0);
        join

        // -----------------------------------------------------------------
        // TC3 : Backpressure test
        // The S2MM DMA channel may not always be ready to accept data.
        // Hold m_axis_tready LOW for 3 cycles before releasing.
        //
        // Expected behaviour:
        //   m_axis_tvalid stays HIGH while tready is LOW (DUT waits).
        //   m_axis_tdata remains stable (no corruption).
        //   When tready goes HIGH, handshake completes and data transfers.
        //
        // Waveform: look for m_axis_tvalid HIGH for multiple cycles before
        //           m_axis_tready rises - this is DUT correctly stalling.
        // -----------------------------------------------------------------
        tc_num = 3;
        $display("\n─────────────────────────────────────────────────────────────");
        $display(" TC3 : Backpressure - m_axis_tready held LOW 3 cycles");
        $display("─────────────────────────────────────────────────────────────");
        do_reset;

        fork
            send_word(32'd99, 1'b1);
            recv_word(32'd99, 1'b1, 3);   // 3 cycles backpressure
        join

        // -----------------------------------------------------------------
        // TC4 : Two consecutive transfers
        // After the first packet completes, the DUT returns to idle.
        // Send a second packet immediately to confirm it accepts new data.
        //
        // First  packet: 100 (TLAST=1)
        // Second packet: 200 (TLAST=1)
        // -----------------------------------------------------------------
        tc_num = 4;
        $display("\n─────────────────────────────────────────────────────────────");
        $display(" TC4 : Two consecutive transfers (no reset between them)");
        $display("─────────────────────────────────────────────────────────────");
        do_reset;

        fork
            send_word(32'd100, 1'b1);
            recv_word(32'd100, 1'b1, 0);
        join

        // Small gap between packets (realistic - DMA has some turnaround)
        repeat(3) @(posedge aclk);

        fork
            send_word(32'd200, 1'b1);
            recv_word(32'd200, 1'b1, 0);
        join

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("");
        $display("=================================================================");
        $display(" SIMULATION COMPLETE");
        $display(" Total checks : %0d", pass_count + fail_count);
        $display(" Passed       : %0d", pass_count);
        $display(" Failed       : %0d", fail_count);
        if (fail_count == 0) begin
            $display(" Result       : ALL TESTS PASSED");
            $display("");
            $display(" Next step: Open Vivado Block Design.");
            $display("   1. Add Zynq PS, AXI DMA, Processor System Reset");
            $display("   2. Package axis_loopback as a custom IP");
            $display("   3. Connect DMA MM2S → axis_loopback S_AXIS");
            $display("   4. Connect axis_loopback M_AXIS → DMA S2MM");
            $display("   5. Generate bitstream and test on Zybo Z7-10");
            $display("   6. Once loopback passes on hardware,");
            $display("      replace axis_loopback with systolic_array_axis");
        end else begin
            $display(" Result       : FAILURES DETECTED - check waveform");
        end
        $display("=================================================================");

        #100;
        $finish;
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #50000;
        $display("TIMEOUT: simulation exceeded 50 µs - DUT may be deadlocked");
        $finish;
    end

endmodule
