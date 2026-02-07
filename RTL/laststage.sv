////////////////////////////////////////////////////////////////////////////////
// Purpose:     The Final 2-Point Butterfly Stage.
//              Takes two inputs (Even/Odd) and computes:
//                Out0 = In0 + In1
//                Out1 = In0 - In1
//              Includes Convergent Rounding to fix final bit width.
////////////////////////////////////////////////////////////////////////////////

`default_nettype    none

module  laststage #(
        // Configuration Parameters
        parameter   IWIDTH = 16,        // Input Bit Width
        parameter   OWIDTH = IWIDTH+1,  // Output Bit Width (Usually matches IWIDTH for 5G)
        parameter   SHIFT  = 0          // Scaling Shift
    ) (
        input   wire                        i_clk, i_reset, i_clk_enable, i_sync,
        input   wire    [(2*IWIDTH-1):0]    i_left,  // Even Sample (Real+Imag)
        input   wire    [(2*IWIDTH-1):0]    i_right, // Odd Sample (Real+Imag)
        output  reg     [(2*OWIDTH-1):0]    o_left,  // Final Result 0
        output  reg     [(2*OWIDTH-1):0]    o_right, // Final Result 1
        output  reg                         o_sync   // Valid Data Flag
    );
    // ========================================================================
    // 1. INPUT UNPACKING
    // ========================================================================
    // Break the complex inputs (Real/Imag concatenated) into signed components.
    wire    signed  [(IWIDTH-1):0]  i_in_0r, i_in_0i, i_in_1r, i_in_1i;
    
    // Output wires coming from the Rounding modules
    wire    [(OWIDTH-1):0]          o_out_0r, o_out_0i, o_out_1r, o_out_1i;

    assign  i_in_0r = i_left[(2*IWIDTH-1):(IWIDTH)];
    assign  i_in_0i = i_left[(IWIDTH-1):0];
    assign  i_in_1r = i_right[(2*IWIDTH-1):(IWIDTH)];
    assign  i_in_1i = i_right[(IWIDTH-1):0];

    // ========================================================================
    // 2. SYNCHRONIZATION PIPELINE
    // ========================================================================
    // Tracks the valid signal through the 3-cycle latency of this stage.
    // Cycle 1: Add/Sub -> rnd_sync
    // Cycle 2: Rounding -> r_sync
    // Cycle 3: Output Register -> o_sync
    reg rnd_sync, r_sync;

    always @(posedge i_clk)
    if (i_reset)
    begin
        rnd_sync <= 1'b0;
        r_sync   <= 1'b0;
    end else if (i_clk_enable)
    begin
        rnd_sync <= i_sync;    // Latency 1
        r_sync   <= rnd_sync;  // Latency 2
    end
    // ========================================================================
    // 3. BUTTERFLY ARITHMETIC (Add/Subtract)
    // ========================================================================
    // Registers to store the Sum and Difference.
    // Note: The width is (IWIDTH + 1) to accommodate the carry bit without overflow.
    reg signed  [(IWIDTH):0]    rnd_in_0r, rnd_in_0i;
    reg signed  [(IWIDTH):0]    rnd_in_1r, rnd_in_1i;

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // Standard Radix-2 Butterfly
        // No Twiddle Factor multiplication needed here (W = 1).
        
        // Sum Path (A + B)
        rnd_in_0r <= i_in_0r + i_in_1r;
        rnd_in_0i <= i_in_0i + i_in_1i;

        // Diff Path (A - B)
        rnd_in_1r <= i_in_0r - i_in_1r;
        rnd_in_1i <= i_in_0i - i_in_1i;
    end
    // ========================================================================
    // 4. CONVERGENT ROUNDING
    // ========================================================================
    // Instantiates the 'convround' module to handle bit growth or reduction.
    // Inputs are (IWIDTH + 1) bits.
    // Outputs are OWIDTH bits.
    // This is vital for 5G to prevent DC bias accumulation.
    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_0r(
        i_clk, i_clk_enable, rnd_in_0r, o_out_0r
    );

    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_0i(
        i_clk, i_clk_enable, rnd_in_0i, o_out_0i
    );

    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_1r(
        i_clk, i_clk_enable, rnd_in_1r, o_out_1r
    );

    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_1i(
        i_clk, i_clk_enable, rnd_in_1i, o_out_1i
    );
    // ========================================================================
    // 5. OUTPUT PACKING & REGISTRATION
    // ========================================================================
    // Re-pack Real/Imag components into complex outputs.
    // This adds the 3rd cycle of latency, isolating the FFT timing 
    // from the downstream logic (e.g., Bit Reversal or AXI Wrapper).
    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        o_left  <= { o_out_0r, o_out_0i };
        o_right <= { o_out_1r, o_out_1i };
    end

    // Final Sync Output
    always @(posedge i_clk)
    if (i_reset)
        o_sync <= 1'b0;
    else if (i_clk_enable)
        o_sync <= r_sync;
endmodule