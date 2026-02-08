// Purpose: Calculates a Radix-2 Decimation-in-Frequency (DIF) Butterfly.
//          This is the core mathematical engine of the FFT.
//
// Operation:
//    Input:  Left (L), Right (R), Coefficient/Twiddle (C)
//    Output: Left' (L'), Right' (R')
//
//    Equations:
//       L' = L + R          (Sum Path - No Rotation)
//       R' = (L - R) * C    (Diff Path - Rotated)
//
// Timing:
//    This module is heavily pipelined. The inputs take several clock cycles
//    (defined by LCLDELAY) to reach the output.
//    The 'aux' line is a delay line that ensures the "Valid/Sync" signal
//    travels with the data and exits at the exact same cycle the result is ready.

`default_nettype    none

module  butterfly #(
        // --- Configuration Parameters ---
        parameter IWIDTH=16,   // Input Data Width
        parameter CWIDTH=20,   // Twiddle Factor Width
        parameter OWIDTH=17,   // Output Width (Usually IWIDTH+1 to capture growth)
        
        // SHIFT: Used to perform static scaling (division by 2) if needed 
        // to prevent overflow. In your 5G design, this is usually 0.
        parameter   SHIFT=0,

        // CKPCE: Clocks per Clock Enable.
        // For 5G High-Bandwidth (400MHz), this is usually 1 (Full Speed).
        parameter   CKPCE=1,

        // --- Latency Calculation Parameters ---
        // These parameters automatically calculate how deep the pipeline 
        // needs to be based on the bit widths. 
        // A wider multiplier takes more logic levels -> more pipeline stages.

        // MXMPYBITS: Determine the size of the multiplier.
        // Optimization: A 16x20 multiply takes the same time as 20x16.
        // We pick the smaller width to determine the logic depth.
        localparam MXMPYBITS = ((IWIDTH+2)>(CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH + 2),

        // MPYDELAY: Estimates the latency of the soft-logic multiplier.
        // Heuristic: Roughly 1 pipeline stage for every 2 bits of width + overhead.
        localparam  MPYDELAY=((MXMPYBITS+1)/2)+2,

        // LCLDELAY: The effective delay seen by the rest of the system.
        // If CKPCE=1, it equals MPYDELAY.
        // If CKPCE>1, the hardware is reused, so the delay counts change.
        localparam  LCLDELAY = (CKPCE == 1) ? MPYDELAY
            : (CKPCE == 2) ? (MPYDELAY/2+2)
            : (MPYDELAY/3 + 2),

        // LGDELAY: Log2 of the delay (used for counter widths, if needed).
        localparam  LGDELAY = (MPYDELAY>64) ? 7
            : (MPYDELAY > 32) ? 6
            : (MPYDELAY > 16) ? 5
            : (MPYDELAY >  8) ? 4
            : (MPYDELAY >  4) ? 3
            : 2,
        
        // AUXLEN: Total latency of the module.
        // The arithmetic takes 'LCLDELAY' cycles.
        // add +3 cycles for input registering, add/sub, and output registering.
        localparam  AUXLEN=(LCLDELAY+3),

        // Remainder calculation for multi-cycle operations (mostly unused if CKPCE=1)
        localparam  MPYREMAINDER = MPYDELAY - CKPCE*(MPYDELAY/CKPCE)
    ) (
        // --- Ports ---
        input   wire                        i_clk, i_reset, i_clk_enable,
        input   wire    [(2*CWIDTH-1):0]    i_coef,         // Twiddle (Real+Imag)
        input   wire    [(2*IWIDTH-1):0]    i_left, i_right,// Inputs (Real+Imag)
        
        // i_aux: The Input Sync Signal.
        // You pulse this high when the first data sample enters.
        input   wire                        i_aux,
        
        output  wire    [(2*OWIDTH-1):0]    o_left, o_right,// Outputs (Real+Imag)
        
        // o_aux: The Output Sync Signal.
        // This will pulse high exactly 'AUXLEN' cycles after i_aux,
        // signaling that o_left/o_right are valid.
        output  reg                         o_aux
    );
	// ========================================================================
    // 1. SIGNAL DECLARATIONS
    // ========================================================================
    // --- Input Registration ---
    // These registers capture the inputs on the first clock cycle.
    reg     [(2*IWIDTH-1):0]    r_left, r_right;
    reg     [(2*CWIDTH-1):0]    r_coef;         // Twiddle Factor (Stage 1)
    reg     [(2*CWIDTH-1):0]    r_coef_2;       // Twiddle Factor (Stage 2 - Pipelined)
    // --- Unpacked Components ---
    // Signed wires to handle arithmetic easily.
    wire    signed  [(IWIDTH-1):0]  r_left_r, r_left_i;   // Left Real/Imag
    wire    signed  [(IWIDTH-1):0]  r_right_r, r_right_i; // Right Real/Imag
    // --- Butterfly Adder Results ---
    // Note: These are (IWIDTH+1) bits to handle the 1-bit growth from A+B.
    reg     signed  [(IWIDTH):0]    r_sum_r, r_sum_i;     // Sum (L+R)
    reg     signed  [(IWIDTH):0]    r_dif_r, r_dif_i;     // Diff (L-R)
    // ========================================================================
    // 2. DELAY FIFO (For the Sum Path)
    // ========================================================================
    // The "Sum" path (L+R) does not need multiplication. 
    // The "Diff" path (L-R) * C takes 'LCLDELAY' cycles to complete multiplication.
    // Therefore, we must store the "Sum" result in a FIFO to delay it 
    // so it matches the latency of the multiplier.
    reg     [(LGDELAY-1):0]     fifo_addr;       // Write Address Pointer
    wire    [(LGDELAY-1):0]     fifo_read_addr;  // Read Address Pointer
    // The Memory Array:
    // Stores the (IWIDTH+1) bit Sum results (Real + Imag).
    // Total width = 2*(IWIDTH+1) = 2*IWIDTH + 2.
    reg     [(2*IWIDTH+1):0]    fifo_left [ 0:((1<<LGDELAY)-1)];
    // The Data read out of the FIFO (Delayed Sum)
    reg     [(2*IWIDTH+1):0]    fifo_read;
    // Unpacked Delayed Sum components
    wire    signed  [(IWIDTH):0]    fifo_r, fifo_i;
    // Assigns happen later in logic, but conceptually:
    // fifo_r = fifo_read[RealPart];
    // fifo_i = fifo_read[ImagPart];
    // ========================================================================
    // 3. MULTIPLIER SIGNALS
    // ========================================================================
    // Signals for the 3-multiply complex multiplication algorithm.
    // (a+jb)*(c+jd) -> requires 3 multiplies: k1, k2, k3.
    
    wire    signed  [(CWIDTH-1):0]              ir_coef_r, ir_coef_i;
    wire    signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   p_one, p_two, p_three; // Partial Products
    
    // Final Multiplication Result (before Rounding)
    reg     signed  [(CWIDTH+IWIDTH+3-1):0]     mpy_r, mpy_i;

    // --- Rounding Wires ---
    wire    signed  [(OWIDTH-1):0]  rnd_left_r, rnd_left_i;   // Final Rounded Sum
    wire    signed  [(OWIDTH-1):0]  rnd_right_r, rnd_right_i; // Final Rounded Diff

    // Sign-extended versions of the Left (Sum) result to match multiplier width
    // for clean bit-width management during final output assignment.
    wire    signed  [(CWIDTH+IWIDTH+3-1):0] left_sr, left_si;

    // --- Aux Pipeline ---
    // Delay line for the synchronization signal.
    reg     [(AUXLEN-1):0]      aux_pipeline;
    
    // --- Multiplier Output Registers (Moved to module scope) ---
    // These are declared here so they're accessible to all generate blocks
    // and the code that follows.
    reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]  rp_one, rp_two, rp_three;
    reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]  rp2_one, rp2_two, rp2_three, rp3_one;

    // Multiplier output wire (accessible to all generate blocks)
    wire signed [(CWIDTH+IWIDTH+3-1):0] mpy_pipe_out;
    
    // ========================================================================
    // 4. DATA UNPACKING ASSIGNMENTS
    // ========================================================================
    // Map the registered inputs to signed wires.
    assign  r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
    assign  r_left_i  = r_left[ (IWIDTH-1):0];
    assign  r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
    assign  r_right_i = r_right[(IWIDTH-1):0];

    // Coefficient unpacking (from the second pipeline stage register)
    assign  ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
    assign  ir_coef_i = r_coef_2[(CWIDTH-1):0];

    // ========================================================================
    // 5. FIFO READ POINTER GENERATION
    // ========================================================================
    // Logic: This implements a "Circular Buffer" without using the % operator.
    // By allowing 'fifo_addr' to overflow naturally and subtracting 'LCLDELAY',
    // we generate a read pointer that is exactly 'LCLDELAY' cycles behind 
    // the write pointer.
    
    assign  fifo_read_addr = fifo_addr - LCLDELAY[(LGDELAY-1):0];

    // ========================================================================
    // 6. INPUT REGISTRATION & BUTTERFLY ARITHMETIC (Stage 1 & 2)
    // ========================================================================
    // This block performs the first two steps of the math pipeline.
    // r_left, r_right, r_coef, r_sum_[r|i], r_dif_[r|i], r_coef_2
    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // --- Pipeline Stage 1: Input Latching ---
        // Isolates the internal logic from external routing delays.
        r_left  <= i_left;   // Latched Input A
        r_right <= i_right;  // Latched Input B
        r_coef  <= i_coef;   // Latched Twiddle Factor

        // --- Pipeline Stage 2: Butterfly Add/Sub ---
        // Standard Radix-2 Operation:
        // Sum  = Left + Right
        // Diff = Left - Right
        // Note: Results grow by 1 bit (IWIDTH+1) here.
        r_sum_r <= r_left_r + r_right_r; 
        r_sum_i <= r_left_i + r_right_i;
        r_dif_r <= r_left_r - r_right_r;
        r_dif_i <= r_left_i - r_right_i;
        // Pass the coefficient forward to Stage 2 to align with Diff result
        r_coef_2<= r_coef;
    end
    // ========================================================================
    // 7. FIFO WRITE CONTROL (Delay Line)
    // ========================================================================
    // The "Sum" result (r_sum) does NOT need to be multiplied. 
    // However, the "Diff" result (r_dif) is about to enter a deep multiplier pipeline.
    // We must store "Sum" in a FIFO to delay it so it emerges at the same time
    // the multiplier finishes.
    always @(posedge i_clk)
    if (i_reset)
        fifo_addr <= 0;
    else if (i_clk_enable)
        // Increment Write Pointer linearly
        fifo_addr <= fifo_addr + 1;
    // ========================================================================
    // 8. FIFO WRITE OPERATION
    // ========================================================================
    // Stores the (Real, Imag) Sum result into the delay memory.
    // This will be read back later using 'fifo_read_addr'.
    always @(posedge i_clk)
    if (i_clk_enable)
        fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };
	// Notes
	// {{{
	// Multiply output is always a width of the sum of the widths of
	// the two inputs.  ALWAYS.  This is independent of the number of
	// bits in p_one, p_two, or p_three.  These values needed to
	// accumulate a bit (or two) each.  However, this approach to a
	// three multiply complex multiply cannot increase the total
	// number of bits in our final output.  We'll take care of
	// dropping back down to the proper width, OWIDTH, in our routine
	// below.

	// We accomplish here "Karatsuba" multiplication.  That is,
	// by doing three multiplies we accomplish the work of four.
	// Let's prove to ourselves that this works ... We wish to
	// multiply: (a+jb) * (c+jd), where a+jb is given by
	//	a + jb = r_dif_r + j r_dif_i, and
	//	c + jd = ir_coef_r + j ir_coef_i.
	// We do this by calculating the intermediate products P1, P2,
	// and P3 as
	//	P1 = ac
	//	P2 = bd
	//	P3 = (a + b) * (c + d)
	// and then complete our final answer with
	//	ac - bd = P1 - P2 (this checks)
	//	ad + bc = P3 - P2 - P1
	//	        = (ac + bc + ad + bd) - bd - ac
	//	        = bc + ad (this checks)
	// }}}
    // ========================================================================
    // 8. KARATSUBA MULTIPLICATION LOGIC
    // ========================================================================
    // The following block instantiates the high-speed logic for P1, P2, and P3.

    // ------------------------------------------------------------------------
    // A. Architecture Selection
    // ------------------------------------------------------------------------
    // This generates hardware for "Full Speed" mode (1 clock per sample).
    generate if (CKPCE <= 1)
    begin : CKPCE_ONE
        // --------------------------------------------------------------------
        // B. Pre-Adders for P3
        // --------------------------------------------------------------------
        // P3 requires multiplying (Sum of Data) * (Sum of Coeffs).
        // We calculate those sums here.
        wire    [(CWIDTH):0]    p3c_in; // Sum of Coeffs (Width + 1 bit growth)
        wire    [(IWIDTH+1):0]  p3d_in; // Sum of Data   (Width + 1 bit growth)
        // Math: (ir_coef_r + j ir_coef_i) -> Sum = Real + Imag
        assign  p3c_in = ir_coef_i + ir_coef_r;
        // Math: (r_dif_r + j r_dif_i)     -> Sum = Real + Imag
        assign  p3d_in = r_dif_r + r_dif_i;
        // --------------------------------------------------------------------
        // C. Multiplier 1 (P1): Real * Real
        // --------------------------------------------------------------------
        // P1 = ir_coef_r * r_dif_r
        // Note on Padding:
        // P3 (above) grew by 1 bit due to the addition.
        // P1 (here) did not.
        // To ensure 'longbimpy' creates identical pipelines (same latency) for
        // P1 and P3, we sign-extend P1's inputs by 1 bit to match P3's width.
        // {bit[MSB], bit} creates a sign-extension.
        longbimpy #(
            .IAW(CWIDTH+1),  // Input A Width (Padded)
            .IBW(IWIDTH+2)   // Input B Width (Padded)
        ) p1(
            .i_clk(i_clk), 
            .i_clk_enable(i_clk_enable),
            // Sign-extend Coeff Real
            .i_a_unsorted({ir_coef_r[CWIDTH-1], ir_coef_r}), 
            // Sign-extend Data Real
            .i_b_unsorted({r_dif_r[IWIDTH],     r_dif_r}),
            .o_r(p_one) // The Result P1
        );
        // ====================================================================
        // KARATSUBA MULTIPLIER 2: Imaginary Part Product (P2)
        // ====================================================================
        // Formula: P2 = (Data Imag) * (Coeff Imag)
        //          P2 = r_dif_i * ir_coef_i
        
        longbimpy #(
            .IAW(CWIDTH+1),  // Input A Width (Padded to match P3)
            .IBW(IWIDTH+2)   // Input B Width (Padded to match P3)
        ) p2(
            .i_clk(i_clk), 
            .i_clk_enable(i_clk_enable),
            // Sign-Extension:
            // Like P1, we manually extend the inputs by 1 bit.
            // Why? P3 (below) uses sums (A+B), which are naturally 1 bit wider.
            // To ensure P1, P2, and P3 all have the EXACT same latency and 
            // bit width for the final subtraction, we pad P1 and P2 here.
            .i_a_unsorted({ir_coef_i[CWIDTH-1], ir_coef_i}), 
            .i_b_unsorted({r_dif_i[IWIDTH],     r_dif_i}),
            
            .o_r(p_two) // Result P2
        );
        // ====================================================================
        // KARATSUBA MULTIPLIER 3: Sum Product (P3)
        // ====================================================================
        // Formula: P3 = (Data Real + Data Imag) * (Coeff Real + Coeff Imag)
        //          P3 = p3d_in * p3c_in
        longbimpy #(
            .IAW(CWIDTH+1), 
            .IBW(IWIDTH+2)
        ) p3(
            .i_clk(i_clk), 
            .i_clk_enable(i_clk_enable),
            // Inputs:
            // These inputs (p3c_in, p3d_in) were calculated in the previous step.
            // Since they are sums, they are already "native" width (W+1).
            // No manual sign extension is needed here.
            .i_a_unsorted(p3c_in),
            .i_b_unsorted(p3d_in),
            
            .o_r(p_three) // Result P3
        );

    end 
    // ========================================================================
    // OPTION 2: RESOURCE SHARING (CKPCE == 2)
    // ========================================================================
    // This block triggers ONLY if the user sets CKPCE=2.
    // It creates a "Time-Multiplexed" architecture to save DSP slices.
    
    else if (CKPCE == 2)
    begin : CKPCE_TWO

        // --------------------------------------------------------------------
        // A. Pipeline Registers for Multiplexing
        // --------------------------------------------------------------------
        // We need registers to hold the values for TWO cycles.
        // 'mpy_pipe_c' and 'mpy_pipe_d' act as small shift registers (FIFO depth 2).
        // They store the Coefficient and Data values to be fed into the 
        // shared multiplier one after the other.
        
        reg     [2*(CWIDTH)-1:0]    mpy_pipe_c; // Holds Real AND Imag Coeffs
        reg     [2*(IWIDTH+1)-1:0]  mpy_pipe_d; // Holds Real AND Imag Data
        
        // These wires tap the top of the shift register to feed the multiplier
        wire    signed  [(CWIDTH-1):0]  mpy_pipe_vc;
        wire    signed  [(IWIDTH):0]    mpy_pipe_vd;

        // Assignments:
        // Always take the upper half of the register (the "current" value to multiply).
        assign  mpy_pipe_vc =  mpy_pipe_c[2*(CWIDTH)-1:CWIDTH];
        assign  mpy_pipe_vd =  mpy_pipe_d[2*(IWIDTH+1)-1:IWIDTH+1];


        // --------------------------------------------------------------------
        // B. Phase Control (The Toggle Flip-Flop)
        // --------------------------------------------------------------------
        // 'ce_phase' tracks which half of the cycle we are in.
        // 0 -> First half (Cycle A)
        // 1 -> Second half (Cycle B)
        
        reg ce_phase;
        
        initial ce_phase = 1'b0;
        always @(posedge i_clk)
        if (i_reset)
            ce_phase <= 1'b0;
        else if (i_clk_enable)
            // When new data arrives (i_clk_enable=1), we start the phase sequence.
            ce_phase <= 1'b1;
        else
            // Otherwise, reset to 0 (ready for next sample).
            ce_phase <= 1'b0;


        // --------------------------------------------------------------------
        // C. Multiplier Valid Signal
        // --------------------------------------------------------------------
        // The shared multiplier must run on BOTH cycles.
        // Cycle A: Triggered by 'i_clk_enable' (New Data).
        // Cycle B: Triggered by 'ce_phase' (The second slot).
        
        reg mpy_pipe_v;
        always @(*)
            mpy_pipe_v = (i_clk_enable)||(ce_phase);


        // --------------------------------------------------------------------
        // D. Loading the Pipeline (The State Machine)
        // --------------------------------------------------------------------
        // This block loads the data into the shift registers based on the phase.
        
        // Storage for P3 calculations (Sums)
        reg signed  [(CWIDTH+1)-1:0]    mpy_cof_sum;
        reg signed  [(IWIDTH+2)-1:0]    mpy_dif_sum;

        always @(posedge i_clk)
        if (ce_phase) 
        begin
            // --- PHASE 1 (Cycle B Logic) ---
            // While we are processing the second half of the previous sample...
            // We PRE-LOAD the registers with the NEXT sample's components.
            // 
            // Load Real parts into the UPPER slots.
            // Load Imag parts into the LOWER slots.
            mpy_pipe_c[2*CWIDTH-1:0] <= { ir_coef_r, ir_coef_i };
            mpy_pipe_d[2*(IWIDTH+1)-1:0] <= { r_dif_r, r_dif_i };

            // Calculate the Sums for P3 right now, so they are ready for the dedicated multiplier.
            mpy_cof_sum <= ir_coef_i + ir_coef_r;
            mpy_dif_sum <= r_dif_r + r_dif_i;

        end else if (i_clk_enable)
        begin
            // --- PHASE 0 (Cycle A Logic) ---
            // New data has arrived and is being processed (Upper slot used).
            // SHIFT the registers up.
            // This discards the value just used (Real) and moves the 
            // next value (Imag) into position for the next clock cycle.
            
            mpy_pipe_c[2*(CWIDTH)-1:0] <= {
                mpy_pipe_c[(CWIDTH)-1:0], {(CWIDTH){1'b0}} };
                
            mpy_pipe_d[2*(IWIDTH+1)-1:0] <= {
                mpy_pipe_d[(IWIDTH+1)-1:0], {(IWIDTH+1){1'b0}} };
        end
        
        // Note: The multiplier instantiation ('mpy0') follows this block.
        // It uses 'mpy_pipe_v' as its clock enable and 'mpy_cof_sum'/'mpy_dif_sum' inputs.

		end // End of CKPCE_TWO block
// ========================================================================
    // OPTION 3: SINGLE MULTIPLIER (CKPCE > 2)
    // ========================================================================
    // If we have 3 or more clock cycles per data sample, we can serialize
    // all three multiplications (P1, P2, P3) onto a single hardware unit.
    // This offers the maximum area savings (1 DSP used total).
    else if (CKPCE > 2)
    begin : CKPCE_GREATER_THAN_2
    
        // --------------------------------------------------------------------
        // 1. DECLARATIONS
        // --------------------------------------------------------------------
        
        // State Machine & Pipeline Control
        reg [2:0]   mpy_state;
        reg         mpy_pipe_v;
        
        // Mux Inputs: Hold the coefficients/data for the current state.
        reg signed  [(CWIDTH):0]    mpy_pipe_c;
        reg signed  [(IWIDTH+1):0]  mpy_pipe_d;

        // Pre-calculation registers for P3 sums
        reg signed  [(CWIDTH+1)-1:0]    mpy_cof_sum;
        reg signed  [(IWIDTH+2)-1:0]    mpy_dif_sum;

        // Multiplier Output
        wire signed [IWIDTH+CWIDTH+3-1:0] longmpy;

        // Output Capture Shift Registers (Delay Lines)
        // These track which result (P1, P2, or P3) is currently in the multiplier.
        reg [MPYDELAY-1:0] pipe_state_0; // Tracks P1
        reg [MPYDELAY-1:0] pipe_state_1; // Tracks P2
        reg [MPYDELAY-1:0] pipe_state_2; // Tracks P3

        // Final Result Registers
        // (Note: We only need rp_, we do NOT need rp2_ for this mode)
        reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0] rp_one, rp_two, rp_three;


        // --------------------------------------------------------------------
        // 2. STATE MACHINE (One-Hot Rotator)
        // --------------------------------------------------------------------
        initial mpy_state = 0;
        always @(posedge i_clk)
        if (i_reset)
            mpy_state <= 0;
        else if (i_clk_enable)
            // When new data arrives, reset to State 1 (001)
            mpy_state <= 3'b001;
        else
            // Otherwise, rotate the bit left: 001 -> 010 -> 100
            mpy_state <= { mpy_state[1:0], 1'b0 };


        // --------------------------------------------------------------------
        // 3. INPUT MULTIPLEXING LOGIC
        // --------------------------------------------------------------------
        always @(posedge i_clk)
        if (i_clk_enable) 
        begin
            // --- STATE 1 SETUP (For P1) ---
            mpy_pipe_c <= { {(1){1'b0}}, ir_coef_r };
            mpy_pipe_d <= { {(2){1'b0}}, r_dif_r };

            // Pre-calculate sums for P3
            mpy_cof_sum <= ir_coef_i + ir_coef_r;
            mpy_dif_sum <= r_dif_r + r_dif_i;
        end 
        else if (mpy_state[0]) 
        begin
            // --- STATE 2 SETUP (For P2) ---
            mpy_pipe_c <= { {(1){1'b0}}, ir_coef_i };
            mpy_pipe_d <= { {(2){1'b0}}, r_dif_i };
        end 
        else if (mpy_state[1]) 
        begin
            // --- STATE 3 SETUP (For P3) ---
            mpy_pipe_c <= mpy_cof_sum;
            mpy_pipe_d <= mpy_dif_sum;
        end


        // --------------------------------------------------------------------
        // 4. MULTIPLIER INSTANTIATION
        // --------------------------------------------------------------------
        always @(*)
            mpy_pipe_v = (i_clk_enable) || (mpy_state[0]) || (mpy_state[1]);

        longbimpy #(
            .IAW(CWIDTH+1), 
            .IBW(IWIDTH+2)
        ) mpy0(
            .i_clk(i_clk), 
            .i_clk_enable(mpy_pipe_v),
            .i_a_unsorted(mpy_pipe_c),
            .i_b_unsorted(mpy_pipe_d),
            .o_r(longmpy)
        );


        // --------------------------------------------------------------------
        // 5. OUTPUT CAPTURE LOGIC
        // --------------------------------------------------------------------
        // We push a '1' into the shift register when we start a multiply.
        // When that '1' pops out 'MPYDELAY' cycles later, we capture the result.

        always @(posedge i_clk) 
        if (i_reset) begin
            pipe_state_0 <= 0; 
            pipe_state_1 <= 0; 
            pipe_state_2 <= 0;
        end else if (mpy_pipe_v) begin
            pipe_state_0 <= { pipe_state_0[MPYDELAY-2:0], (i_clk_enable) };
            pipe_state_1 <= { pipe_state_1[MPYDELAY-2:0], mpy_state[0] };
            pipe_state_2 <= { pipe_state_2[MPYDELAY-2:0], mpy_state[1] };
        end

        always @(posedge i_clk) begin
            if (pipe_state_0[MPYDELAY-1]) rp_one   <= longmpy;
            if (pipe_state_1[MPYDELAY-1]) rp_two   <= longmpy;
            if (pipe_state_2[MPYDELAY-1]) rp_three <= longmpy;
        end
        
        // --------------------------------------------------------------------
        // 6. FINAL ASSIGNMENT
        // --------------------------------------------------------------------
        // Map captured registers to the output wires.
        // We do NOT need the 'rp2' logic here because the state machine 
        // ensures 'rp_one/two/three' hold their values until the next sample.
        assign p_one   = rp_one;
        assign p_two   = rp_two;
        assign p_three = rp_three;

    end // End of CKPCE_GREATER_THAN_2
    // ========================================================================
    // OPTION 3: 3-CLOCK SERIALIZATION (CKPCE == 3)
    // ========================================================================
    // Logic for exactly 3 clocks per sample.
    // Uses 1 Multiplier to do the work of 3.

    else if (CKPCE <= 3) 
    begin : CKPCE_THREE

        // --------------------------------------------------------------------
        // A. Pipeline Registers (The "Vertical Shift Register")
        // --------------------------------------------------------------------
        // Holds inputs for all 3 cycles. Size is 3x the width of one input.
        reg     [3*(CWIDTH+1)-1:0]  mpy_pipe_c; // Coeff Pipeline
        reg     [3*(IWIDTH+2)-1:0]  mpy_pipe_d; // Data Pipeline
        
        // Wires hardwired to the TOP of the pipeline (Current Input)
        wire    signed  [(CWIDTH):0]    mpy_pipe_vc;
        wire    signed  [(IWIDTH+1):0]  mpy_pipe_vd;
        
        assign  mpy_pipe_vc =  mpy_pipe_c[3*(CWIDTH+1)-1:2*(CWIDTH+1)];
        assign  mpy_pipe_vd =  mpy_pipe_d[3*(IWIDTH+2)-1:2*(IWIDTH+2)];

        // --------------------------------------------------------------------
        // B. Phase Control
        // --------------------------------------------------------------------
        // Controls the Load -> Shift -> Shift sequence.
        reg     [2:0]   ce_phase;
        
        initial ce_phase = 3'b011;
        always @(posedge i_clk)
        if (i_reset)
            ce_phase <= 3'b011;
        else if (i_clk_enable)
            ce_phase <= 3'b000; // Reset to 0 on new data
        else if (ce_phase != 3'b011)
            ce_phase <= ce_phase + 1'b1; // Increment 0->1->2->3

        // Valid signal for the multiplier
        reg mpy_pipe_v;
        always @(*)
            mpy_pipe_v = (i_clk_enable)||(ce_phase < 3'b010);

        // --------------------------------------------------------------------
        // C. Data Loading & Shifting
        // --------------------------------------------------------------------
        always @(posedge i_clk)
        if (ce_phase == 3'b000)
        begin
            // --- LOAD PHASE (Cycle 1) ---
            // Pack P1, P2, and P3 inputs into the register simultaneously.
            
            // Top Slot: P1 (Real * Real)
            // Mid Slot: P2 (Imag * Imag)
            mpy_pipe_c[3*(CWIDTH+1)-1:(CWIDTH+1)] <= {
                ir_coef_r[CWIDTH-1], ir_coef_r, // P1 Coeff
                ir_coef_i[CWIDTH-1], ir_coef_i  // P2 Coeff
            };
            
            // Bot Slot: P3 (Sum * Sum)
            mpy_pipe_c[CWIDTH:0] <= ir_coef_i + ir_coef_r;

            // Same pattern for Data (mpy_pipe_d)...
            mpy_pipe_d[3*(IWIDTH+2)-1:(IWIDTH+2)] <= {
                r_dif_r[IWIDTH], r_dif_r,      // P1 Data
                r_dif_i[IWIDTH], r_dif_i       // P2 Data
            };
            mpy_pipe_d[(IWIDTH+2)-1:0] <= r_dif_r + r_dif_i; // P3 Data
            
        end else if (mpy_pipe_v)
        begin
            // --- SHIFT PHASE (Cycle 2 & 3) ---
            // Shift everything UP by one slot width.
            mpy_pipe_c[3*(CWIDTH+1)-1:0] <= {
                mpy_pipe_c[2*(CWIDTH+1)-1:0], {(CWIDTH+1){1'b0}} };
            mpy_pipe_d[3*(IWIDTH+2)-1:0] <= {
                mpy_pipe_d[2*(IWIDTH+2)-1:0], {(IWIDTH+2){1'b0}} };
        end

        // --------------------------------------------------------------------
        // D. Multiplier Instantiation
        // --------------------------------------------------------------------
        wire signed [(CWIDTH+IWIDTH+3)-1:0] mpy_pipe_out;
        
        longbimpy #(
            .IAW(CWIDTH+1), .IBW(IWIDTH+2)
        ) mpy(
            .i_clk(i_clk), .i_clk_enable(mpy_pipe_v),
            .i_a_unsorted(mpy_pipe_vc),
            .i_b_unsorted(mpy_pipe_vd),
            .o_r(mpy_pipe_out)
        );

        // --------------------------------------------------------------------
        // E. Output Capture Logic (CASE 0: Exact Alignment)
        // --------------------------------------------------------------------
        // This block handles the case where (Multiplier Latency % 3) == 0.
        // This means the inputs and outputs are perfectly phase-aligned.
        // If P1 goes in at Phase 0, P1 comes out at Phase 0.
        
        always @(posedge i_clk)
        if (MPYREMAINDER == 0)
        begin
            if (i_clk_enable) 
                // Capture P2 (It's actually the previous sample's P2 here due to wrapping)
                rp_two   <= mpy_pipe_out;
            else if (ce_phase == 3'b000)
                // Capture P3
                rp_three <= mpy_pipe_out;
            else if (ce_phase == 3'b001)
                // Capture P1
                rp_one   <= mpy_pipe_out;
        end 
  // ====================================================================
        // OUTPUT CAPTURE LOGIC (Cases 1 & 2)
        // ====================================================================
        // This handles the timing offsets if the multiplier latency isn't
        // a perfect multiple of 3.
        
        else if (MPYREMAINDER == 1)
        begin
            // Case 1: Offset by 1 cycle.
            // When 'i_clk_enable' is high (Phase 0), the multiplier finishes P1.
            // When Phase is 0 (Cycle 2), the multiplier finishes P2.
            // When Phase is 1 (Cycle 3), the multiplier finishes P3.
            if (i_clk_enable)
                rp_one   <= mpy_pipe_out;
            else if (ce_phase == 3'b000)
                rp_two   <= mpy_pipe_out;
            else if (ce_phase == 3'b001)
                rp_three <= mpy_pipe_out;
        end 
        else // (MPYREMAINDER == 2)
        begin
            // Case 2: Offset by 2 cycles.
            // The sequence wraps around differently.
            // i_clk_enable (Phase 0) -> Captures P3 (from previous set!)
            // Phase 0 -> Captures P1
            // Phase 1 -> Captures P2
            if (i_clk_enable)
                rp_three <= mpy_pipe_out;
            else if (ce_phase == 3'b000)
                rp_one   <= mpy_pipe_out;
            else if (ce_phase == 3'b001)
                rp_two   <= mpy_pipe_out;
        end


        // ====================================================================
        // FINAL ALIGNMENT & REGISTERING
        // ====================================================================
        // At this point, rp_one, rp_two, and rp_three contain the correct values,
        // but they were captured at different clock cycles.
        // We must align them so they are all valid on the SAME clock edge
        // before handing them off to the adder.

        always @(posedge i_clk)
        if (i_clk_enable)
        begin
            // Buffer the values to align them.
            // rp2_... are the "Stage 2" delay registers.
            rp2_one   <= rp_one;
            rp2_two   <= rp_two;
            
            // Special handling for P3 and P1 based on the Remainder offset:
            // If Offset=2, P3 arrives late, so bypass the buffer logic.
            rp2_three <= (MPYREMAINDER == 2) ? mpy_pipe_out : rp_three;
            
            // If Offset=0, P1 arrives early, so double-buffer it (rp3_one).
            rp3_one   <= (MPYREMAINDER == 0) ? rp2_one : rp_one;
        end

        // Assign the final, perfectly aligned wires
        assign  p_one   = rp3_one;
        assign  p_two   = rp2_two;
        assign  p_three = rp2_three;

    end // End of CKPCE_THREE block
    endgenerate // End of Multiplier Architecture Generation


    // ========================================================================
    // FIFO OUTPUT RECOVERY
    // ========================================================================
    // While the multiplier was crunching the "Difference" path, the "Sum" path
    // was sitting in a FIFO (memory). We now read it out.
    
    // Scaling Logic:
    // The multiplier result (p_one, etc.) is conceptually multiplied by 
    // the Twiddle Factor (CWIDTH bits).
    // The FIFO result (Left + Right) was NOT multiplied.
    // To add them together, we must scale the FIFO result up to match.
    // We do this by appending (CWIDTH-2) zeros at the bottom.
    // This is equivalent to multiplying by 2^(CWIDTH-2).
    
    assign  fifo_r = { 
        {2{fifo_read[2*(IWIDTH+1)-1]}},             // Sign Extension (2 bits)
        fifo_read[(2*(IWIDTH+1)-1):(IWIDTH+1)],     // The Real Data
        {(CWIDTH-2){1'b0}}                          // Zero Padding (Scaling)
    };
    
    assign  fifo_i = { 
        {2{fifo_read[(IWIDTH+1)-1]}},               // Sign Extension (2 bits)
        fifo_read[((IWIDTH+1)-1):0],                // The Imag Data
        {(CWIDTH-2){1'b0}}                          // Zero Padding (Scaling)
    };

// ========================================================================
    // 9. ROUNDING AND TRUNCATION LOGIC
    // ========================================================================
    // The multiplication and addition stages have significantly increased the 
    // bit width of our data (Input + Coeff + Growth Bits).
    // We must now round this back down to 'OWIDTH' to fit the output ports.
    
    // ------------------------------------------------------------------------
    // A. Prepare FIFO Data for Rounding
    // ------------------------------------------------------------------------
    // The FIFO data (Sum Path) was NOT multiplied, so it has fewer bits than
    // the Multiplier data (Diff Path).
    // To use the same rounding logic for both, we "pad" the FIFO data.
    // 1. Sign Extension: Repeat the MSB twice ({2{...}}) to match the growth.
    // 2. Zero Padding: Append zeros to the LSB side. This effectively
    //    multiplies the value by 2^(CWIDTH-2) to match the scale of the
    //    Diff path (which was multiplied by the Twiddle Factor).
    
    assign  left_sr = { {(2){fifo_r[(IWIDTH+CWIDTH)]}}, fifo_r };
    assign  left_si = { {(2){fifo_i[(IWIDTH+CWIDTH)]}}, fifo_i };

    // ------------------------------------------------------------------------
    // B. Convergent Rounding (Round to Nearest Even)
    // ------------------------------------------------------------------------
    // We use the 'convround' module to remove the extra bits.
    // 'SHIFT+4' is the number of bits to drop. The '+4' accounts for the 
    // internal bit growth (2 bits from butterfly add/sub + 2 bits from CWIDTH-2 scaling).
    
    // Round the Sum Path (Left/Top)
    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_left_r(i_clk, i_clk_enable, left_sr, rnd_left_r);

    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_left_i(i_clk, i_clk_enable, left_si, rnd_left_i);

    // Round the Diff Path (Right/Bottom)
    // mpy_r and mpy_i are the results from the reconstruction step below.
    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_right_r(i_clk, i_clk_enable, mpy_r, rnd_right_r);

    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_right_i(i_clk, i_clk_enable, mpy_i, rnd_right_i);


    // ========================================================================
    // 10. KARATSUBA RECONSTRUCTION & FIFO READ
    // ========================================================================
    // This block runs parallel to the rounding logic above (pipeline stage).
    
    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // --- Path A: The Sum (FIFO) ---
        // Retrieve the data we stored way back at the start.
        // It has been waiting in the FIFO for exactly 'LCLDELAY' cycles.
        fifo_read <= fifo_left[fifo_read_addr];

        // --- Path B: The Diff (Multiplier) ---
        // Reconstruct the Real and Imaginary parts from the three Karatsuba 
        // partial products (P1, P2, P3).
        // Real = P1 - P2
        mpy_r <= p_one - p_two;
        
        // Imag = P3 - (P1 + P2)
        // Note: P3 = (Real+Imag)*(Real+Imag)
        mpy_i <= p_three - p_one - p_two;
    end


    // ========================================================================
    // 11. AUXILIARY SIGNAL SYNCHRONIZATION
    // ========================================================================
    // The 'i_aux' signal (Start of Frame / Sync) must be delayed by the exact
    // same amount as the data so they stay in sync at the output.
    
    // Shift the aux signal through a shift register of length 'AUXLEN'
    always @(posedge i_clk)
    if (i_reset)
        aux_pipeline <= 0;
    else if (i_clk_enable)
        // Shift left: Discard MSB, shift in new LSB
        aux_pipeline <= { aux_pipeline[(AUXLEN-2):0], i_aux };

    // Latch the final delayed bit to the output port
    always @(posedge i_clk)
    if (i_reset)
        o_aux <= 1'b0;
    else if (i_clk_enable)
    begin
        // Output the MSB of the delay line
        o_aux <= aux_pipeline[AUXLEN-1];
    end


    // ========================================================================
    // 12. FINAL OUTPUT ASSIGNMENT
    // ========================================================================
    // Pack the rounded Real and Imaginary parts into the single output buses.
    // Each output is 2*OWIDTH bits wide.
    // Upper Half: Real Part
    // Lower Half: Imaginary Part
    
    assign  o_left  = { rnd_left_r,  rnd_left_i };
    assign  o_right = { rnd_right_r, rnd_right_i };

endmodule


