////////////////////////////////////////////////////////////////////////////////
// Purpose:     Implements the "Quarter Rotator" stage (4-point decomposition).
//              This corresponds to the specific optimization where complex
//              multipliers are replaced by simple logic (Add/Sub/Swap).
////////////////////////////////////////////////////////////////////////////////

`default_nettype    none

module  qtrstage(
    i_clk, i_reset, i_clk_enable, i_sync, 
    i_data, o_data, o_sync
);
    // --- Configuration Parameters ---
    parameter   IWIDTH=16;           // Input Bit Width
    parameter   OWIDTH=IWIDTH+1;     // Output Bit Width (Bit Growth allowed)
    
    // LGWIDTH: Log2 of the sub-transform size. 
    // For a 4-point stage in this specific architecture, this controls timing.
    parameter   LGWIDTH=8; 
    
    // ODD: The critical parameter for the "Quarter Rotator".
    // 0 = Even path (Twiddle W^0 = 1) -> No rotation.
    // 1 = Odd path (Twiddle W^{N/4} = -j) -> Rotate by -90 degrees.
    parameter   ODD=0; 
    
    parameter   INVERSE=0;           // 0 = Forward FFT (-j), 1 = IFFT (+j)
    parameter   SHIFT=0;             // Scaling shift (usually 0)

    // --- Ports ---
    input   wire                        i_clk, i_reset, i_clk_enable, i_sync;
    input   wire    [(2*IWIDTH-1):0]    i_data; // Complex Input
    output  reg     [(2*OWIDTH-1):0]    o_data; // Complex Output
    output  reg                         o_sync;

    // --- Internal State ---
    reg             wait_for_sync;
    
    // Pipeline Shift Register: Tracks the validity of data as it moves 
    // through the Add -> Round -> Rotate stages.
    reg     [3:0]   pipeline; 

    // Butterfly Intermediate Results
    reg     [(IWIDTH):0]    sum_r, sum_i, diff_r, diff_i;

    // Output Registers
    reg     [(2*OWIDTH-1):0]    ob_a;           // "Sum" path result
    wire    [(2*OWIDTH-1):0]    ob_b;           // "Diff" path result (Rotated)
    reg     [(OWIDTH-1):0]      ob_b_r, ob_b_i; // Components of ob_b
    assign  ob_b = { ob_b_r, ob_b_i };

    // --- Control Logic ---
    reg     [(LGWIDTH-1):0]     iaddr;          // Address Counter
    
    // --- Memory (Delay Line) ---
    // Note: Since this is a small stage processing 2 samples/clock, 
    // the "delay" required is very small (1 cycle).
    // Therefore, 'imem' is just a register, not a RAM block.
    reg     [(2*IWIDTH-1):0]    imem;

    // Split input and memory into Real/Imag parts for calculation
    wire    signed  [(IWIDTH-1):0]  imem_r, imem_i;
    assign  imem_r = imem[(2*IWIDTH-1):(IWIDTH)];
    assign  imem_i = imem[(IWIDTH-1):0];

    wire    signed  [(IWIDTH-1):0]  i_data_r, i_data_i;
    assign  i_data_r = i_data[(2*IWIDTH-1):(IWIDTH)];
    assign  i_data_i = i_data[(IWIDTH-1):0];

    // Output Memory (SDF Feedback Buffer)
    reg     [(2*OWIDTH-1):0]    omem;

    // --- Rounding Wires ---
    // Wires to hold results after "Convergent Rounding"
    wire    signed  [(OWIDTH-1):0]  rnd_sum_r, rnd_sum_i, rnd_diff_r, rnd_diff_i,
                                    n_rnd_diff_r, n_rnd_diff_i;
    // ========================================================================
    // 1. ROUNDING INSTANTIATION
    // ========================================================================
    // Instantiates helper modules to handle bit growth and rounding.
    convround #(IWIDTH+1,OWIDTH,SHIFT)
        do_rnd_sum_r(i_clk, i_clk_enable, sum_r, rnd_sum_r);

    convround #(IWIDTH+1,OWIDTH,SHIFT)
        do_rnd_sum_i(i_clk, i_clk_enable, sum_i, rnd_sum_i);

    convround #(IWIDTH+1,OWIDTH,SHIFT)
        do_rnd_diff_r(i_clk, i_clk_enable, diff_r, rnd_diff_r);

    convround #(IWIDTH+1,OWIDTH,SHIFT)
        do_rnd_diff_i(i_clk, i_clk_enable, diff_i, rnd_diff_i);

    // Pre-calculate negated versions for the "Quarter Rotator" logic
    assign n_rnd_diff_r = - rnd_diff_r;
    assign n_rnd_diff_i = - rnd_diff_i;
    // ========================================================================
    // 2. CONTROL LOGIC (Addressing)
    // ========================================================================
    always @(posedge i_clk)
    if (i_reset)
    begin
        wait_for_sync <= 1'b1;
        iaddr <= 0;
    end else if ((i_clk_enable)&&((!wait_for_sync)||(i_sync)))
    begin
        // Increment counter. 
        // Note: For a 4-point stage with 2-samples/clock, this toggles rapidly.
        iaddr <= iaddr + { {(LGWIDTH-1){1'b0}}, 1'b1 };
        wait_for_sync <= 1'b0;
    end
    // ========================================================================
    // 3. INPUT DELAY (FIFO)
    // ========================================================================
    // This stores the "Previous" sample to perform the butterfly with the "Current".
    // Since this is a small stage, a simple register suffices.
    always @(posedge i_clk)
        if (i_clk_enable)
            imem <= i_data;
    // ========================================================================
    // 4. PIPELINE TRACKING
    // ========================================================================
    // Tracks the valid data bit as it flows through the pipeline stages.
    // pipeline[0] -> Butterfly
    // pipeline[1] -> Rounding
    // pipeline[2] -> Rotation
    // pipeline[3] -> Output Mux
    always  @(posedge i_clk)
        if (i_reset)
            pipeline <= 4'h0;
        else if (i_clk_enable) 
            pipeline <= { pipeline[2:0], iaddr[0] };
    // ========================================================================
    // 5. STAGE 1: BUTTERFLY ARITHMETIC
    // ========================================================================
    // Standard Radix-2 Butterfly: Sum = A+B, Diff = A-B
    // Condition: (iaddr[0]) ensures we only calculate when we have both 
    // the stored sample (imem) and the current sample (i_data).
    always  @(posedge i_clk)
    if ((i_clk_enable)&&(iaddr[0]))
    begin
        sum_r  <= imem_r + i_data_r;
        sum_i  <= imem_i + i_data_i;
        diff_r <= imem_r - i_data_r;
        diff_i <= imem_i - i_data_i;
    end
    // ========================================================================
    // 6. STAGE 2: ROTATION (The Quarter Rotator)
    // ========================================================================
    // This is the implementation of Paper Section IV.C.
    // Instead of a multiplier, we use Muxes to swap Real/Imag components.
    always  @(posedge i_clk)
    if (i_clk_enable)
    begin
        // The Sum path (ob_a) never rotates in Radix-2 DIF.
        ob_a <= { rnd_sum_r, rnd_sum_i };
        // The Diff path (ob_b) rotates based on the 'ODD' parameter.
        if (ODD == 0)
        begin
            // CASE: W = 1 (0 degrees)
            // No rotation. Pass inputs through.
            ob_b_r <= rnd_diff_r;
            ob_b_i <= rnd_diff_i;
        end else if (INVERSE==0) begin
            // CASE: W = -j (-90 degrees) -- Forward FFT
            // Math: (Re + jIm) * (-j) = -jRe - j^2Im = Im - jRe
            // Real Out = Imag In
            // Imag Out = -Real In
            ob_b_r <=   rnd_diff_i;
            ob_b_i <= n_rnd_diff_r;
        end else begin
            // CASE: W = +j (+90 degrees) -- Inverse FFT
            // Math: (Re + jIm) * (j) = jRe + j^2Im = -Im + jRe
            // Real Out = -Imag In
            // Imag Out = Real In
            ob_b_r <= n_rnd_diff_i;
            ob_b_i <=   rnd_diff_r;
        end
    end
    // ========================================================================
    // 7. STAGE 3: OUTPUT MUX (SDF Commutator)
    // ========================================================================
    // Selects between the immediate result (ob_a) and the delayed result (omem).
    // The delay is managed by 'omem'.
    always  @(posedge i_clk)
    if (i_clk_enable)
    begin 
        if (pipeline[3])
        begin
            // First Half of Output:
            // Output 'Sum' (ob_a) immediately.
            // Store 'Diff' (ob_b) in omem for later.
            omem <= ob_b;
            o_data <= ob_a;
        end else
            // Second Half of Output:
            // Output the stored 'Diff' from omem.
            o_data <= omem;
    end
    // ========================================================================
    // 8. SYNC GENERATION
    // ========================================================================
    // Generates the synchronization pulse for the NEXT stage.
    // This logic is complex because it must account for the pipeline latency 
    // (5 clocks) to align the sync pulse with the first valid output sample.
    generate if (LGWIDTH == 3)
    begin
        // Logic for specific small FFT sizes...
        reg o_sync_passed;
        initial o_sync_passed = 1'b0;
        always  @(posedge i_clk)
        if (i_reset)
            o_sync_passed <= 1'b0;
        else if (i_clk_enable && o_sync)
            o_sync_passed <= 1'b1;

        always  @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable && (o_sync_passed || iaddr[2]))
            o_sync <= (iaddr[1:0] == 2'b01);
    end else if (LGWIDTH == 4)
    begin
        // Logic for slightly larger sizes...
        always  @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable)
            o_sync <= (iaddr[2:0] == 3'b101);
    end else begin
        // General Case for larger stages
        // Aligns sync based on address counters and pipeline depth.
        always  @(posedge i_clk)
        if (i_reset)
            o_sync <= 1'b0;
        else if (i_clk_enable)
            // Notice: The condition (iaddr[2:0] == 3'b101) corresponds to 
            // the pipeline latency of 5 clock cycles.
            o_sync <= (iaddr[(LGWIDTH-2):3] == 0) && (iaddr[2:0] == 3'b101);
    end endgenerate
endmodule