// ============================================================================
// Module: laststage
// ============================================================================
// Purpose:
//   Implements the final Radix-2 butterfly stage of the FFT.
//
// Architectural Context:
//   • Last decomposition level (2-point butterfly)
//   • Twiddle factors reduce to ±1
//   • No complex multiplication required
//
// Mathematical Operation:
//
//      Output[0] = A + B
//      Output[1] = A - B
//
// Precision Handling:
//   • Arithmetic grows by 1 bit (IWIDTH → IWIDTH+1)
//   • Convergent rounding reduces to OWIDTH
//
// Latency:
//   3 clock cycles
//      Cycle 1 → Add/Sub
//      Cycle 2 → Rounding
//      Cycle 3 → Output Register
// ============================================================================

`default_nettype none

module laststage #(
    // ------------------------------------------------------------------------
    // Configuration Parameters
    // ------------------------------------------------------------------------
    parameter IWIDTH = 16,           // Input component width
    parameter OWIDTH = IWIDTH + 1,   // Output width (allows bit growth)
    parameter SHIFT  = 0             // Optional scaling shift
)(
    // ------------------------------------------------------------------------
    // Ports
    // ------------------------------------------------------------------------
    input  wire                      i_clk,
    input  wire                      i_reset,
    input  wire                      i_clk_enable,
    input  wire                      i_sync,

    input  wire [(2*IWIDTH-1):0]     i_left,  // Even sample (Real+Imag)
    input  wire [(2*IWIDTH-1):0]     i_right,  // Odd sample  (Real+Imag)

    output reg  [(2*OWIDTH-1):0]     o_left,   // Final Sum
    output reg  [(2*OWIDTH-1):0]     o_right,  // Final Diff
    output reg                       o_sync    // Valid flag
);

    // ========================================================================
    // 1. INPUT UNPACKING
    // ========================================================================
    //
    // Split complex inputs into signed Real/Imag components.
    //

    wire signed [(IWIDTH-1):0] i_in_0r, i_in_0i;
    wire signed [(IWIDTH-1):0] i_in_1r, i_in_1i;

    assign i_in_0r = i_left [(2*IWIDTH-1):(IWIDTH)];
    assign i_in_0i = i_left [(IWIDTH-1):0];

    assign i_in_1r = i_right[(2*IWIDTH-1):(IWIDTH)];
    assign i_in_1i = i_right[(IWIDTH-1):0];

    // ========================================================================
    // 2. SYNCHRONIZATION PIPELINE
    // ========================================================================
    //
    // Aligns sync with datapath latency.
    //
    // Pipeline:
    //      Stage 1 → rnd_sync
    //      Stage 2 → r_sync
    //      Stage 3 → o_sync
    //

    reg rnd_sync, r_sync;

    always @(posedge i_clk)
    if (i_reset)
    begin
        rnd_sync <= 1'b0;
        r_sync   <= 1'b0;
    end
    else if (i_clk_enable)
    begin
        rnd_sync <= i_sync;    // Delay 1
        r_sync   <= rnd_sync;  // Delay 2
    end

    // ========================================================================
    // 3. BUTTERFLY ARITHMETIC (Add/Subtract)
    // ========================================================================
    //
    // Radix-2 Butterfly (Twiddle = 1):
    //
    //      Sum  = A + B
    //      Diff = A - B
    //
    // Width:
    //      IWIDTH+1 (prevents overflow)
    //

    reg signed [(IWIDTH):0] rnd_in_0r, rnd_in_0i;
    reg signed [(IWIDTH):0] rnd_in_1r, rnd_in_1i;

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // Sum Path
        rnd_in_0r <= i_in_0r + i_in_1r;
        rnd_in_0i <= i_in_0i + i_in_1i;

        // Difference Path
        rnd_in_1r <= i_in_0r - i_in_1r;
        rnd_in_1i <= i_in_0i - i_in_1i;
    end

    // ========================================================================
    // 4. CONVERGENT ROUNDING
    // ========================================================================
    //
    // Reduces arithmetic growth:
    //      (IWIDTH+1) → OWIDTH
    //
    // Prevents:
    //      • Bias accumulation
    //      • Overflow propagation
    //

    wire [(OWIDTH-1):0] o_out_0r, o_out_0i;
    wire [(OWIDTH-1):0] o_out_1r, o_out_1i;

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_0r(i_clk, i_clk_enable, rnd_in_0r, o_out_0r);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_0i(i_clk, i_clk_enable, rnd_in_0i, o_out_0i);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_1r(i_clk, i_clk_enable, rnd_in_1r, o_out_1r);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_1i(i_clk, i_clk_enable, rnd_in_1i, o_out_1i);

    // ========================================================================
    // 5. OUTPUT PACKING & REGISTRATION
    // ========================================================================
    //
    // Pack rounded Real/Imag into complex outputs.
    // Provides final pipeline isolation stage.
    //

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        o_left  <= { o_out_0r, o_out_0i };
        o_right <= { o_out_1r, o_out_1i };
    end

    // ========================================================================
    // FINAL SYNC OUTPUT
    // ========================================================================
    //
    // Sync aligned with Cycle 3 (valid outputs).
    //

    always @(posedge i_clk)
    if (i_reset)
        o_sync <= 1'b0;
    else if (i_clk_enable)
        o_sync <= r_sync;

endmodule
