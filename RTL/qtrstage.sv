////////////////////////////////////////////////////////////////////////////////
// Module: qtrstage
////////////////////////////////////////////////////////////////////////////////
// Purpose:
//   Implements the "Quarter Rotator" stage used in Radix-2 DIF FFT pipelines.
//
// Architectural Context:
//   This stage appears at the decomposition level where twiddle factors
//   become trivial rotations (±1, ±j). Instead of using complex multipliers,
//   we exploit mathematical properties:
//
//        ×  1   → Pass-through
//        × -1   → Sign inversion
//        ×  j   → Swap Real/Imag + Sign
//        × -j   → Swap Real/Imag + Sign
//
// Result:
//   Multiplier-free implementation using only:
//
//        • Add/Sub
//        • Sign inversion
//        • Real/Imag swapping
//
// Benefit:
//   Significant area and power reduction.
//
////////////////////////////////////////////////////////////////////////////////

`default_nettype none

module qtrstage (
    i_clk,
    i_reset,
    i_clk_enable,
    i_sync,
    i_data,
    o_data,
    o_sync
);

    // ------------------------------------------------------------------------
    // Configuration Parameters
    // ------------------------------------------------------------------------

    parameter IWIDTH = 16;            // Input component width (Real / Imag)
    parameter OWIDTH = IWIDTH + 1;    // Output width (allows bit growth)

    // LGWIDTH:
    //   Log2 of FFT size (context parameter)
    //   Used for internal scheduling / timing alignment
    parameter LGWIDTH = 8;

    // ODD:
    //   Selects rotation behavior
    //
    //      ODD = 0 → Even Path  → Twiddle = 1 (No rotation)
    //      ODD = 1 → Odd Path   → Twiddle = ±j (Quarter rotation)
    //
    parameter ODD = 0;

    // INVERSE:
    //      0 → Forward FFT  → Rotation by -j
    //      1 → Inverse FFT  → Rotation by +j
    parameter INVERSE = 0;

    // SHIFT:
    //   Optional scaling shift
    //   Typically 0 (full precision)
    parameter SHIFT = 0;

    // ------------------------------------------------------------------------
    // Ports
    // ------------------------------------------------------------------------

    input  wire                      i_clk;
    input  wire                      i_reset;
    input  wire                      i_clk_enable;
    input  wire                      i_sync;

    // Complex data format:
    //      [High Bits] → Real
    //      [Low Bits ] → Imaginary
    input  wire [(2*IWIDTH-1):0]     i_data;

    output reg  [(2*OWIDTH-1):0]     o_data;
    output reg                       o_sync;
    // ========================================================================
    // INTERNAL STATE & PIPELINE TRACKING
    // ========================================================================

    // wait_for_sync:
    //   Prevents invalid data propagation before the first frame begins.
    //   Ensures the stage only processes valid FFT samples.
    reg wait_for_sync;

    // pipeline:
    //   Shift register tracking sample validity across pipeline stages.
    //
    //   Pipeline flow:
    //        Stage 0 → Input capture
    //        Stage 1 → Add/Sub (Butterfly)
    //        Stage 2 → Rounding
    //        Stage 3 → Rotation / Output
    //
    //   Each bit represents validity of data at that stage.
    reg [3:0] pipeline;

    // ========================================================================
    // BUTTERFLY INTERMEDIATE RESULTS
    // ========================================================================
    //
    // Radix-2 Butterfly Equations:
    //
    //      Sum  = L + R
    //      Diff = L - R
    //
    // Width grows by 1 bit (IWIDTH+1).
    //

    reg [(IWIDTH):0] sum_r, sum_i;   // Real/Imag Sum
    reg [(IWIDTH):0] diff_r, diff_i; // Real/Imag Difference

    // ========================================================================
    // OUTPUT PATH REGISTERS
    // ========================================================================

    // ob_a:
    //   Sum path output (no rotation required).
    reg  [(2*OWIDTH-1):0] ob_a;

    // ob_b:
    //   Diff path output (subject to quarter rotation).
    wire [(2*OWIDTH-1):0] ob_b;

    // ob_b_r / ob_b_i:
    //   Individual Real/Imag components after rotation logic.
    reg [(OWIDTH-1):0] ob_b_r, ob_b_i;

    // Pack rotated components
    assign ob_b = { ob_b_r, ob_b_i };

    // ========================================================================
    // CONTROL & ADDRESSING
    // ========================================================================

    // iaddr:
    //   Sample counter controlling SDF scheduling.
    //   Determines when add/sub and rotation phases occur.
    reg [(LGWIDTH-1):0] iaddr;

    // ========================================================================
    // DELAY LINE (SDF FEEDBACK STORAGE)
    // ========================================================================
    //
    // Because this stage operates on a very small span (4-point level),
    // the required delay is minimal (1 clock).
    //
    // Implementation:
    //      Register instead of RAM
    //

    reg [(2*IWIDTH-1):0] imem;  // Input delay register

    // Split delayed sample into components
    wire signed [(IWIDTH-1):0] imem_r, imem_i;

    assign imem_r = imem[(2*IWIDTH-1):(IWIDTH)];
    assign imem_i = imem[(IWIDTH-1):0];

    // Split incoming sample
    wire signed [(IWIDTH-1):0] i_data_r, i_data_i;

    assign i_data_r = i_data[(2*IWIDTH-1):(IWIDTH)];
    assign i_data_i = i_data[(IWIDTH-1):0];

    // omem:
    //   Stores Diff-path result for SDF feedback.
    reg [(2*OWIDTH-1):0] omem;

    // ========================================================================
    // ROUNDING SIGNALS
    // ========================================================================
    //
    // Convergent rounding reduces (IWIDTH+1) → OWIDTH.
    //

    wire signed [(OWIDTH-1):0]
        rnd_sum_r, rnd_sum_i,
        rnd_diff_r, rnd_diff_i,
        n_rnd_diff_r, n_rnd_diff_i;

    // ========================================================================
    // 1. ROUNDING MODULE INSTANTIATION
    // ========================================================================
    //
    // Each arithmetic result is rounded independently.
    //

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_sum_r(i_clk, i_clk_enable, sum_r, rnd_sum_r);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_sum_i(i_clk, i_clk_enable, sum_i, rnd_sum_i);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_diff_r(i_clk, i_clk_enable, diff_r, rnd_diff_r);

    convround #(IWIDTH+1, OWIDTH, SHIFT)
        do_rnd_diff_i(i_clk, i_clk_enable, diff_i, rnd_diff_i);

    // Precompute negated Diff values
    // Used by quarter-rotation logic (±j cases)
    assign n_rnd_diff_r = -rnd_diff_r;
    assign n_rnd_diff_i = -rnd_diff_i;
    // ========================================================================
    // 2. CONTROL LOGIC (Frame Synchronization & Addressing)
    // ========================================================================
    //
    // wait_for_sync:
    //   Prevents counter activity until the first valid frame arrives.
    //
    // iaddr:
    //   Free-running sample counter once synchronization is achieved.
    //   LSB (iaddr[0]) controls butterfly scheduling.
    //

    always @(posedge i_clk)
    if (i_reset)
    begin
        wait_for_sync <= 1'b1;  // Hold until first sync
        iaddr         <= 0;     // Reset counter
    end
    else if ((i_clk_enable) && ((!wait_for_sync) || (i_sync)))
    begin
        // Counter increment
        // For small-span stages (4-point level), this toggles rapidly.
        iaddr <= iaddr + 1'b1;

        // Release sync hold after first valid sample
        wait_for_sync <= 1'b0;
    end

    // ========================================================================
    // 3. INPUT DELAY (Single-Sample FIFO)
    // ========================================================================
    //
    // Purpose:
    //   Stores previous input sample for Radix-2 butterfly pairing.
    //
    // Implementation:
    //   Register-based delay (no RAM required).
    //

    always @(posedge i_clk)
        if (i_clk_enable)
            imem <= i_data;

    // ========================================================================
    // 4. PIPELINE VALIDITY TRACKING
    // ========================================================================
    //
    // pipeline shift register:
    //
    //   pipeline[0] → Butterfly active
    //   pipeline[1] → Rounding stage
    //   pipeline[2] → Rotation stage
    //   pipeline[3] → Output selection
    //
    // Input source:
    //   iaddr[0] toggles every sample pair
    //

    always @(posedge i_clk)
        if (i_reset)
            pipeline <= 4'h0;
        else if (i_clk_enable)
            pipeline <= { pipeline[2:0], iaddr[0] };

    // ========================================================================
    // 5. STAGE 1: BUTTERFLY ARITHMETIC
    // ========================================================================
    //
    // Radix-2 Butterfly:
    //
    //      Sum  = Previous + Current
    //      Diff = Previous - Current
    //
    // Condition:
    //      iaddr[0] == 1
    //
    // Ensures:
    //      Both operands available (imem + i_data)
    //

    always @(posedge i_clk)
    if ((i_clk_enable) && (iaddr[0]))
    begin
        sum_r  <= imem_r + i_data_r;
        sum_i  <= imem_i + i_data_i;

        diff_r <= imem_r - i_data_r;
        diff_i <= imem_i - i_data_i;
    end
    // ========================================================================
    // 6. STAGE 2: QUARTER ROTATION (Multiplier-Free Twiddle)
    // ========================================================================
    //
    // Implements the "Quarter Rotator" optimization.
    //
    // Instead of complex multiplication, rotation is achieved via:
    //      • Real/Imag swap
    //      • Sign inversion
    //
    // Twiddle cases handled:
    //
    //      ODD = 0 → W = 1   → No rotation
    //      ODD = 1 → W = ±j  → ±90° rotation
    //

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // Sum path: never rotated in DIF
        ob_a <= { rnd_sum_r, rnd_sum_i };

        // Diff path: rotation depends on configuration
        if (ODD == 0)
        begin
            // CASE: W = 1 (0°)
            ob_b_r <= rnd_diff_r;
            ob_b_i <= rnd_diff_i;

        end else if (INVERSE == 0)
        begin
            // CASE: W = -j (Forward FFT)
            //
            // (Re + jIm) × (-j) = Im − jRe
            //
            // Real =  Imag
            // Imag = -Real
            //
            ob_b_r <=   rnd_diff_i;
            ob_b_i <= n_rnd_diff_r;

        end else
        begin
            // CASE: W = +j (Inverse FFT)
            //
            // (Re + jIm) × ( j) = -Im + jRe
            //
            // Real = -Imag
            // Imag =  Real
            //
            ob_b_r <= n_rnd_diff_i;
            ob_b_i <=   rnd_diff_r;
        end
    end

    // ========================================================================
    // 7. STAGE 3: OUTPUT MUX (SDF Commutator)
    // ========================================================================
    //
    // Selects output ordering according to SDF scheduling:
    //
    //      pipeline[3] = 1 → Output SUM
    //                         Store DIFF
    //
    //      pipeline[3] = 0 → Output stored DIFF
    //

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        if (pipeline[3])
        begin
            // First half of butterfly outputs
            omem   <= ob_b;   // Store Diff
            o_data <= ob_a;   // Output Sum
        end
        else
        begin
            // Second half of outputs
            o_data <= omem;   // Output delayed Diff
        end
    end

    // ========================================================================
    // 8. SYNC GENERATION
    // ========================================================================
    //
    // Generates frame synchronization for downstream stages.
    //
    // Sync must be aligned with:
    //      • Pipeline latency
    //      • Butterfly scheduling
    //
    // Special handling for small LGWIDTH values.
    //

    generate

    // ------------------------------------------------------------------------
    // CASE: Very Small FFT Context (LGWIDTH == 3)
    // ------------------------------------------------------------------------
    if (LGWIDTH == 3)
    begin
        reg o_sync_passed;
        initial o_sync_passed = 1'b0;

        always @(posedge i_clk)
        if (i_reset)
            o_sync_passed <= 1'b0;
        else if (i_clk_enable && o_sync)
            o_sync_passed <= 1'b1;

        always @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable && (o_sync_passed || iaddr[2]))
            o_sync <= (iaddr[1:0] == 2'b01);
    end

    // ------------------------------------------------------------------------
    // CASE: Small FFT Context (LGWIDTH == 4)
    // ------------------------------------------------------------------------
    else if (LGWIDTH == 4)
    begin
        always @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable)
            o_sync <= (iaddr[2:0] == 3'b101);
    end

    // ------------------------------------------------------------------------
    // GENERAL CASE (Larger FFT Stages)
    // ------------------------------------------------------------------------
    else
    begin
        always @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable)
            // Sync aligned to pipeline latency (5 cycles)
            o_sync <= (iaddr[(LGWIDTH-2):3] == 0)
                   && (iaddr[2:0] == 3'b101);
    end

    endgenerate
endmodule