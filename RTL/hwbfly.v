// Purpose:	This routine is identical to the butterfly.v routine found
//		in 'butterfly.v', save only that it uses the verilog
//	operator '*' in hopes that the synthesizer would be able to optimize
//	it with hardware resources.
//
//	It is understood that a hardware multiply can complete its operation in
//	a single clock.
//
// Operation:
//
//	Given two inputs, A (i_left) and B (i_right), and a complex
//	coefficient C (i_coeff), return two outputs, O1 and O2, where:
//
//		O1 = A + B, and
//		O2 = (A - B)*C
//
//	This operation is commonly known as a Decimation in Frequency (DIF)
//	Radix-2 Butterfly.
//	O1 and O2 are rounded before being returned in (o_left) and o_right
//	to OWIDTH bits.  If SHIFT is one, an extra bit is dropped from these
//	values during the rounding process.
//
//	Further, since these outputs will take some number of clocks to
//	calculate, we'll pipe a value (i_aux) through the system and return
//	it with the results (o_aux), so you can synchronize to the outgoing
//	output stream.

`default_nettype    none


`default_nettype    none

module  hwbfly #(
        // ====================================================================
        // 1. CONFIGURATION PARAMETERS
        // ====================================================================
        parameter IWIDTH=16,          // Input Data Width (e.g., 16 bits)
        parameter CWIDTH=IWIDTH+4,    // Coefficient Width (Extra precision)
        parameter OWIDTH=IWIDTH+1,    // Output Width (Allows 1 bit growth from Add/Sub)
        
        parameter   SHIFT=0,          // Static shift for scaling (if needed)
        
        // CKPCE: Clocks per Clock Enable
        // 1 = Full Speed (Parallel Multipliers)
        // 2 = Resource Shared (2 Multipliers)
        // 3 = Serialized (1 Multiplier)
        parameter   [1:0]   CKPCE=1
    ) (
        // ====================================================================
        // 2. PORTS
        // ====================================================================
        input   wire    i_clk, i_reset, i_ce,
        
        // Complex Inputs: Packed as {Real, Imaginary}
        input   wire    [(2*CWIDTH-1):0]    i_coef,  // Twiddle Factor
        input   wire    [(2*IWIDTH-1):0]    i_left,  // Data Input A
        input   wire    [(2*IWIDTH-1):0]    i_right, // Data Input B
        
        // Synchronization: Pulses high when the first valid sample arrives
        input   wire    i_aux,
        
        // Complex Outputs: Packed as {Real, Imaginary}
        output  wire    [(2*OWIDTH-1):0]    o_left, o_right,
        
        // Output Sync: Pulses high when valid data exits the module
        output  reg o_aux
    );

    // ====================================================================
    // 3. INTERNAL SIGNALS
    // ====================================================================
    
    // --- Input Capture Registers (Stage 1) ---
    // Isolate timing paths by latching inputs immediately.
    reg [(2*IWIDTH-1):0]    r_left, r_right;
    reg [(2*CWIDTH-1):0]    r_coef;
    reg             r_aux, r_aux_2;

    // --- Unpacked Wires ---
    // Helper wires to access Real/Imag parts easily.
    wire    signed  [(IWIDTH-1):0]  r_left_r, r_left_i, r_right_r, r_right_i;
    
    // --- Twiddle Factor Alignment ---
    // The coefficients need to be delayed to match the Add/Sub latency.
    reg signed  [(CWIDTH-1):0]  ir_coef_r, ir_coef_i;

    // --- Add/Sub Registers (Stage 2) ---
    // Store the results of (Left +/- Right).
    // Note: These are 1 bit wider [(IWIDTH):0] to handle the carry bit.
    reg signed  [(IWIDTH):0]    r_sum_r, r_sum_i; // Sum Path
    reg signed  [(IWIDTH):0]    r_dif_r, r_dif_i; // Diff Path

    // --- Sum Path Delay Line ---
    // The Sum path finishes early. These registers hold the data while
    // the Diff path goes through the slow multiplier.
    reg [(2*IWIDTH+2):0]    leftv, leftvv;

    // --- Multiplier Signals ---
    // Intermediate wires for the Karatsuba multiplication.
    // Widths are calculated to hold the full precision result without overflow.
    wire    signed  [((IWIDTH+1)+(CWIDTH)-1):0] p_one, p_two;
    wire    signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   p_three;
    wire    signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   w_one, w_two;

    wire    aux_s;
    wire    signed  [(IWIDTH+CWIDTH):0] left_si, left_sr;
    reg     [(2*IWIDTH+2):0]    left_saved;
    
    // --- Final Multiplier Result ---
    // ATTRIBUTE: (* use_dsp48="no" *)
    // This tells the synthesis tool: "Do NOT use a hard DSP slice for this."
    // It forces the logic into general FPGA fabric (LUTs).
    (* use_dsp48="no" *)
    reg signed  [(CWIDTH+IWIDTH+3-1):0] mpy_r, mpy_i;

    // --- Rounding Results ---
    wire    signed  [(OWIDTH-1):0]  rnd_left_r, rnd_left_i, rnd_right_r, rnd_right_i;

    // ====================================================================
    // 4. DATA UNPACKING
    // ====================================================================
    // Manually split the packed buses into signed integers.
    // [Upper Half] = Real Part
    // [Lower Half] = Imaginary Part
    assign  r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
    assign  r_left_i  = r_left[ (IWIDTH-1):0];
    assign  r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
    assign  r_right_i = r_right[(IWIDTH-1):0];

    // ====================================================================
    // 5. AUXILIARY PIPELINE SETUP
    // ====================================================================
    // We need to pass the Sync signal (`i_aux`) down the pipeline
    // alongside the data so we know when the output is valid.
    
    always @(posedge i_clk)
    if (i_reset)
    begin
        r_aux <= 1'b0;
        r_aux_2 <= 1'b0;
    end else if (i_ce)
    begin
        // Clock 1: Capture Input
        r_aux <= i_aux;
        
        // Clock 2: Move to Stage 2 (aligns with Add/Sub)
        r_aux_2 <= r_aux;
    end
	// ========================================================================
    // 4. BUTTERFLY STAGE 1 & 2 (The Arithmetic Pipeline)
    // ========================================================================
    // This block handles the first two stages of the FFT Butterfly:
    // Stage 1: Register Inputs (Isolation).
    // Stage 2: Calculate Sum (A+B) and Difference (A-B).
    
    always @(posedge i_clk)
    if (i_ce)
    begin
        // --- CLOCK 1: Input Latching ---
        // Capture inputs into registers. This improves timing performance (Fmax)
        // by isolating the internal logic from external routing delays.
        r_left  <= i_left;   // No change in # of bits
        r_right <= i_right;
        r_coef  <= i_coef;   // Capture Twiddle Factor

        // --- CLOCK 2: Add/Sub & Delay ---
        // 1. Calculate Sum (Top Path): (Real+Real, Imag+Imag)
        //    Note: Result grows by 1 bit (IWIDTH -> IWIDTH+1)
        r_sum_r <= r_left_r + r_right_r; 
        r_sum_i <= r_left_i + r_right_i;

        // 2. Calculate Difference (Bottom Path): (Real-Real, Imag-Imag)
        r_dif_r <= r_left_r - r_right_r;
        r_dif_i <= r_left_i - r_right_i;

        // 3. Align Coefficient
        //    Since the Add/Sub took 1 clock cycle, we must delay the coefficient
        //    by 1 clock so it arrives at the multiplier at the same time as the Diff data.
        ir_coef_r <= r_coef[(2*CWIDTH-1):CWIDTH];
        ir_coef_i <= r_coef[(CWIDTH-1):0];
    end

    // ========================================================================
    // 5. SUM PATH DELAY LINE
    // ========================================================================
    // The "Sum" path (Top) is finished after the addition above. 
    // The "Diff" path (Bottom) still has to go through a complex multiplier.
    // We must delay the Sum result so it waits for the Multiplier to finish.

    always @(posedge i_clk)
    if (i_reset)
    begin
        leftv  <= 0;
        leftvv <= 0;
    end else if (i_ce)
    begin
        // Delay Stage 1: Store Sum results + Sync Signal (r_aux_2)
        leftv <= { r_aux_2, r_sum_r, r_sum_i };

        // Delay Stage 2: Shift data down.
        // This 'leftvv' will be used later to recombine with the multiplier output.
        // The synthesis tool effectively infers a shift register here.
        leftvv <= leftv;
    end

    // ========================================================================
    // 6. MULTIPLIER LOGIC (CKPCE=1 / Full Speed)
    // ========================================================================
    // This block generates the hardware for the fastest speed grade (1 clock per sample).
    // It uses 3 Parallel Multipliers to perform the complex multiplication.
    
    generate if (CKPCE <= 1)
    begin : CKPCE_ONE
        
        // --------------------------------------------------------------------
        // A. Multiplier Input Registers
        // --------------------------------------------------------------------
        // Registers to hold inputs for the 3 multipliers (P1, P2, P3).
        
        // P1 & P2 Inputs:
        reg signed  [(CWIDTH-1):0]  p1c_in, p2c_in; // Coefficients
        reg signed  [(IWIDTH):0]    p1d_in, p2d_in; // Data (Diff Real/Imag)
        
        // P3 Inputs (Requires Pre-Adder):
        // P3 = (Sum of Coeffs) * (Sum of Data)
        reg signed  [(CWIDTH):0]    p3c_in;         // Sum Coeffs (Extra bit width)
        reg signed  [(IWIDTH+1):0]  p3d_in;         // Sum Data   (Extra bit width)

        // --------------------------------------------------------------------
        // B. Multiplier Output Registers
        // --------------------------------------------------------------------
        reg signed  [((IWIDTH+1)+(CWIDTH)-1):0] rp_one, rp_two;
        reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   rp_three;

        // --------------------------------------------------------------------
        // C. Pre-Calculation Stage (Clock 3)
        // --------------------------------------------------------------------
        always @(posedge i_clk)
        if (i_ce)
        begin
            // Setup P1 inputs: Real Coeff * Real Diff
            p1c_in <= ir_coef_r;
            p1d_in <= r_dif_r;
            
            // Setup P2 inputs: Imag Coeff * Imag Diff
            p2c_in <= ir_coef_i;
            p2d_in <= r_dif_i;
            
            // Setup P3 inputs: (Real+Imag Coeff) * (Real+Imag Diff)
            // This addition is the "Karatsuba Pre-Add".
            // Modern DSP slices (like DSP48) can often do this addition internally.
            p3c_in <= ir_coef_i + ir_coef_r;
            p3d_in <= r_dif_r + r_dif_i;
        end

        // --------------------------------------------------------------------
        // D. Multiplication Stage (Clock 4)
        // --------------------------------------------------------------------
        // This is the actual multiplication step.
        // Because we use the '*' operator, synthesis tools will map these lines
        // directly to the FPGA's dedicated hardware multipliers (DSP Slices).
        
        always @(posedge i_clk)
        if (i_ce)
        begin
            // Calculate Partial Products
            rp_one   <= p1c_in * p1d_in;   // DSP Slice #1
            rp_two   <= p2c_in * p2d_in;   // DSP Slice #2
            rp_three <= p3c_in * p3d_in;   // DSP Slice #3
        end
		

        assign	p_one   = rp_one;
		assign	p_two   = rp_two;
		assign	p_three = rp_three;
		// }}}
	    end // ========================================================================
    // 6. MULTIPLIER LOGIC (CKPCE=2 / Resource Shared)
    // ========================================================================
    // This block triggers when we have 2 clock cycles per data sample.
    // It saves 1 DSP slice compared to the Full Speed version.
    
    else if (CKPCE <= 2)
    begin : CKPCE_TWO

        // --------------------------------------------------------------------
        // A. Pipeline Registers
        // --------------------------------------------------------------------
        // We need a small memory (Shift Register) to hold the Real and Imaginary
        // parts so we can feed them to the shared multiplier one by one.
        // Size = 2 * Width (Holds Real + Imag).
        
        reg     [2*(CWIDTH)-1:0]    mpy_pipe_c; // Coefficient Pipeline
        reg     [2*(IWIDTH+1)-1:0]  mpy_pipe_d; // Data Pipeline (Diff)
        
        // These wires tap the "Top" of the shift register.
        // They feed the Shared Multiplier with whatever is currently active.
        wire    signed  [(CWIDTH-1):0]  mpy_pipe_vc;
        wire    signed  [(IWIDTH):0]    mpy_pipe_vd;

        // Dedicated Registers for the P3 (Sum) Multiplier
        // Since P3 happens in parallel, it gets its own registers.
        reg signed  [(CWIDTH+1)-1:0]    mpy_cof_sum;
        reg signed  [(IWIDTH+2)-1:0]    mpy_dif_sum;

        // Control Signals
        reg             mpy_pipe_v; // Valid signal for Shared Multiplier
        reg             ce_phase;   // Phase Counter (0 or 1)

        // Multiplier Outputs
        reg signed  [(CWIDTH+IWIDTH+1)-1:0] mpy_pipe_out; // Output of Shared Multiplier
        reg signed [IWIDTH+CWIDTH+3-1:0]    longmpy;      // Output of Dedicated Multiplier (P3)

        // Capture Registers (To hold results until all 3 are ready)
        reg signed  [((IWIDTH+1)+(CWIDTH)-1):0] rp_one, rp2_one, rp_two;
        reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   rp_three;

        // Hardwire the shared multiplier input to the top half of the pipe.
        assign  mpy_pipe_vc =  mpy_pipe_c[2*(CWIDTH)-1:CWIDTH];
        assign  mpy_pipe_vd =  mpy_pipe_d[2*(IWIDTH+1)-1:IWIDTH+1];

        // --------------------------------------------------------------------
        // B. Phase Control (The Toggle Flip-Flop)
        // --------------------------------------------------------------------
        // We need to track which half of the cycle we are in.
        // ce_phase = 0: First Clock (Process Real parts)
        // ce_phase = 1: Second Clock (Process Imag parts)
        
        initial ce_phase = 1'b1;
        always @(posedge i_clk)
        if (i_reset)
            ce_phase <= 1'b1;
        else if (i_ce)
            // When new data arrives (i_ce=1), reset to Phase 0
            ce_phase <= 1'b0;
        else
            // Otherwise toggle to Phase 1
            ce_phase <= 1'b1;

        // Generate a "Valid" signal that is high for BOTH phases.
        // This ensures the shared multiplier runs on both clock cycles.
        always @(*)
            mpy_pipe_v = (i_ce)||(!ce_phase);

        // --------------------------------------------------------------------
        // C. Data Loading (Pre-Clock / Phase 1)
        // --------------------------------------------------------------------
        // Logic: When we are finishing the previous sample (Phase 1 / !ce_phase),
        // we PRE-LOAD the registers with the NEXT sample's data.
        
        always @(posedge i_clk)
        if (!ce_phase) // Logic for end of Phase 0 / Start of Phase 1
        begin
            // Load the Pipeline Registers with BOTH Real and Imag parts.
            // [Top Half]    = Real Part (To be used immediately)
            // [Bottom Half] = Imag Part (To be used next clock)
            mpy_pipe_c[2*CWIDTH-1:0] <= { ir_coef_r, ir_coef_i };
            mpy_pipe_d[2*(IWIDTH+1)-1:0] <= { r_dif_r, r_dif_i };

            // Pre-Calculate the Sums for the Dedicated P3 Multiplier.
            // P3 = (Imag+Real) * (Imag+Real)
            // We do this addition now so it's ready for the dedicated multiplier.
            mpy_cof_sum <= ir_coef_i + ir_coef_r;
            mpy_dif_sum <= r_dif_r + r_dif_i;
        end // ====================================================================
        // D. Pipeline Shifting (Phase 1 / Clock 2)
        // ====================================================================
        // In the previous chunk, we LOADED the registers when (!ce_phase).
        // Now, when (i_ce) is high (start of next cycle), we SHIFT them.
        //
        // Initial State: [ Real Part | Imag Part ]
        // Clock 1 Use:   Uses [Real Part] (Top of register)
        // Action:        Shift Left by Width.
        // New State:     [ Imag Part | 000000000 ]
        // Clock 2 Use:   Uses [Imag Part] (Now at Top of register)
        
        else if (i_ce)
        begin
            // Shift Coeffs: Discard used Real part, move Imag part to top.
            mpy_pipe_c[2*(CWIDTH)-1:0] <= {
                mpy_pipe_c[(CWIDTH)-1:0], {(CWIDTH){1'b0}} };
                
            // Shift Data: Discard used Real part, move Imag part to top.
            mpy_pipe_d[2*(IWIDTH+1)-1:0] <= {
                mpy_pipe_d[(IWIDTH+1)-1:0], {(IWIDTH+1){1'b0}} };
        end

        // ====================================================================
        // E. Multiplier Execution
        // ====================================================================
        // We use the '*' operator to infer DSP slices.
        // I have removed the formal verification code as requested.

        // 1. Dedicated Multiplier (P3): Runs once per sample (i_ce).
        //    Calculates (Sum Coeffs) * (Sum Data).
        always @(posedge i_clk)
        if (i_ce) 
            longmpy <= mpy_cof_sum * mpy_dif_sum;

        // 2. Shared Multiplier (P1 & P2): Runs on both clocks (mpy_pipe_v).
        //    Clock 1: Inputs are Real * Real (P1)
        //    Clock 2: Inputs are Imag * Imag (P2) -> Because of the shift above!
        always @(posedge i_clk)
        if (mpy_pipe_v)
            mpy_pipe_out <= mpy_pipe_vc * mpy_pipe_vd;


        // ====================================================================
        // F. Output Capture & Alignment
        // ====================================================================
        // The results appear sequentially. We must capture them and align them.

        // Capture P1 (Real * Real)
        // This result is valid after the first phase (!ce_phase).
        always @(posedge i_clk)
        if (!ce_phase) 
            rp_one <= mpy_pipe_out;

        // Capture P2 (Imag * Imag)
        // This result is valid after the second phase (i_ce).
        always @(posedge i_clk)
        if (i_ce) 
            rp_two <= mpy_pipe_out;

        // Capture P3 (Sum * Sum)
        // This result is valid after the second phase (i_ce).
        always @(posedge i_clk)
        if (i_ce) 
            rp_three<= longmpy;

        // --- Synchronization ---
        // P1 was captured 1 clock cycle earlier than P2 and P3.
        // We register it one more time ('rp2_one') so that all three values
        // change on the exact same clock edge.
        always @(posedge i_clk)
        if (i_ce)
            rp2_one <= rp_one;

        // ====================================================================
        // G. Final Assignments
        // ====================================================================
        // Connect the aligned registers to the module outputs.
        assign  p_one   = rp2_one;
        assign  p_two   = rp_two;
        assign  p_three = rp_three;

    end // End of CKPCE_TWO
	// ========================================================================
    // OPTION 3: 3-CLOCK SERIALIZATION (CKPCE == 3)
    // ========================================================================
    // This logic triggers when the clock rate is >= 3x the data rate.
    // It uses a SINGLE hardware multiplier to do the work of three.
    // This provides the maximum area savings (1 DSP vs 3 DSPs).
    
    else if (CKPCE <= 2'b11)
    begin : CKPCE_THREE

        // --------------------------------------------------------------------
        // A. Pipeline Declarations
        // --------------------------------------------------------------------
        // We create a "Vertical" shift register (stack) to hold inputs for 3 cycles.
        // Size = 3 * Width.
        
        reg     [3*(CWIDTH+1)-1:0]  mpy_pipe_c; // Coefficient Stack
        reg     [3*(IWIDTH+2)-1:0]  mpy_pipe_d; // Data Stack
        
        // These wires tap the "Top" of the stack (Current Input to Multiplier)
        wire    signed  [(CWIDTH):0]    mpy_pipe_vc;
        wire    signed  [(IWIDTH+1):0]  mpy_pipe_vd;

        // Control Signals
        reg             mpy_pipe_v; // Valid Signal
        reg     [2:0]   ce_phase;   // Phase Counter (0, 1, 2, 3)

        // Multiplier Output
        reg signed  [(CWIDTH+IWIDTH+3)-1:0]   mpy_pipe_out;

        // Capture Registers
        // We need to store the results as they pop out sequentially.
        reg signed  [((IWIDTH+1)+(CWIDTH)-1):0] rp_one, rp_two, rp2_one, rp2_two;
        reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   rp_three, rp2_three;

        // --------------------------------------------------------------------
        // B. Pipeline Taps
        // --------------------------------------------------------------------
        // Hardwire the multiplier inputs to the top 1/3rd of the registers.
        // As we shift the register, new data moves into these slots.
        assign  mpy_pipe_vc =  mpy_pipe_c[3*(CWIDTH+1)-1:2*(CWIDTH+1)];
        assign  mpy_pipe_vd =  mpy_pipe_d[3*(IWIDTH+2)-1:2*(IWIDTH+2)];

        // --------------------------------------------------------------------
        // C. Phase Counter (ce_phase)
        // --------------------------------------------------------------------
        // We need to count 0 -> 1 -> 2 to track which product we are calculating.
        // State 3 (011) is the "Idle" state.
        
        initial ce_phase = 3'b011;
        always @(posedge i_clk)
        if (i_reset)
            ce_phase <= 3'b011;
        else if (i_ce)
            // New Data Arrived! Reset counter to 0.
            ce_phase <= 3'b000;
        else if (ce_phase != 3'b011)
            // Increment counter until we hit 3.
            ce_phase <= ce_phase + 1'b1;

        // --------------------------------------------------------------------
        // D. Multiplier Valid Signal
        // --------------------------------------------------------------------
        // The multiplier should run during phases 0, 1, and 2.
        // It stops when we hit phase 3 (Idle).
        always @(*)
            mpy_pipe_v = (i_ce)||(ce_phase < 3'b010);

        // --------------------------------------------------------------------
        // E. Data Loading & Shifting
        // --------------------------------------------------------------------
        
        always @(posedge i_clk)
        if (ce_phase == 3'b000)
        begin
            // --- LOAD PHASE (Cycle 1) ---
            // We pack all 3 pending calculations into the register stack at once.
            
            // Top Slot: P1 (Real * Real)
            // Middle Slot: P2 (Imag * Imag)
            mpy_pipe_c[3*(CWIDTH+1)-1:(CWIDTH+1)] <= {
                ir_coef_r[CWIDTH-1], ir_coef_r, // P1 Coeff (Sign Extended)
                ir_coef_i[CWIDTH-1], ir_coef_i  // P2 Coeff (Sign Extended)
            };
            
            // Bottom Slot: P3 (Sum * Sum)
            // Pre-calculate the sum now.
            mpy_pipe_c[CWIDTH:0] <= ir_coef_i + ir_coef_r;

            // Do the same for Data (Diff)
            mpy_pipe_d[3*(IWIDTH+2)-1:(IWIDTH+2)] <= {
                r_dif_r[IWIDTH], r_dif_r,   // P1 Data
                r_dif_i[IWIDTH], r_dif_i    // P2 Data
            };
            mpy_pipe_d[(IWIDTH+2)-1:0] <= r_dif_r + r_dif_i; // P3 Data

        end else if (mpy_pipe_v)
        begin
            // --- SHIFT PHASE (Cycle 2 & 3) ---
            // Shift the whole stack UP by one slot.
            // P1 falls off the top (it's being multiplied now).
            // P2 moves to the Top.
            // P3 moves to the Middle.
            mpy_pipe_c[3*(CWIDTH+1)-1:0] <= {
                mpy_pipe_c[2*(CWIDTH+1)-1:0], {(CWIDTH+1){1'b0}} };
                
            mpy_pipe_d[3*(IWIDTH+2)-1:0] <= {
                mpy_pipe_d[2*(IWIDTH+2)-1:0], {(IWIDTH+2){1'b0}} };
        end
		// ====================================================================
        // F. SERIALIZED MULTIPLIER EXECUTION
        // ====================================================================
        // This is the single hardware multiplier doing the work of three.
        // It runs sequentially:
        // Cycle 1: Computes P1 (Real * Real)
        // Cycle 2: Computes P2 (Imag * Imag)
        // Cycle 3: Computes P3 (Sum * Sum)
        
        always @(posedge i_clk)
        if (mpy_pipe_v)
            // INFER DSP: This maps to the FPGA's hard multiplier (e.g., DSP48).
            // Input 'mpy_pipe_vc/vd' changes every clock cycle (fed by the shift register).
            mpy_pipe_out <= mpy_pipe_vc * mpy_pipe_vd;

        // ====================================================================
        // G. OUTPUT DEMULTIPLEXING & CAPTURE
        // ====================================================================
        // The results pop out of 'mpy_pipe_out' one by one. We must catch them
        // into separate registers at the exact right moment.

        // Capture P1 (Real * Real)
        // P1 computation finishes first. It is available when i_ce is High.
        // Note: P1 is narrower than P3, so we only capture the needed bits.
        always @(posedge i_clk)
        if(i_ce)
            rp_one <= mpy_pipe_out[(CWIDTH+IWIDTH):0];

        // Capture P2 (Imag * Imag)
        // P2 finishes next. It is available when the phase counter is 0 (1 clock after i_ce).
        always @(posedge i_clk)
        if(ce_phase == 3'b000)
            rp_two <= mpy_pipe_out[(CWIDTH+IWIDTH):0];

        // Capture P3 (Sum * Sum)
        // P3 finishes last. It is available when the phase counter is 1 (2 clocks after i_ce).
        // Note: P3 is wider (due to the pre-addition), so we capture the full width.
        always @(posedge i_clk)
        if(ce_phase == 3'b001)
            rp_three <= mpy_pipe_out;

        // ====================================================================
        // H. FINAL SYNCHRONIZATION
        // ====================================================================
        // P1 was captured at T=0, P2 at T=1, P3 at T=2.
        // We cannot use them yet because they are misaligned in time.
        // We wait for the next 'i_ce' (Start of Sample) to register them ALL together.
        
        always @(posedge i_clk)
        if (i_ce)
        begin
            rp2_one   <= rp_one;   // Align P1
            rp2_two   <= rp_two;   // Align P2
            rp2_three <= rp_three; // Align P3
        end

        // Connect aligned registers to module wires
        assign  p_one   = rp2_one;
        assign  p_two   = rp2_two;
        assign  p_three = rp2_three;

    end endgenerate // End of CKPCE_THREE and End of Generate Blocks


    // ========================================================================
    // 7. WIDTH MATCHING (SIGN EXTENSION)
    // ========================================================================
    // We are preparing to do the math: Result = P3 - P1 - P2.
    // However, P3 is 2 bits wider than P1 and P2 (due to input growth).
    // To perform signed subtraction correctly, we must sign-extend P1 and P2
    // to match the width of P3.
    
    // {2{...}} repeats the MSB (sign bit) twice to pad the top.
    assign  w_one = { {(2){p_one[((IWIDTH+1)+(CWIDTH)-1)]}}, p_one };
    assign  w_two = { {(2){p_two[((IWIDTH+1)+(CWIDTH)-1)]}}, p_two };


    // ========================================================================
    // 8. SUM PATH RECOVERY & SCALING
    // ========================================================================
    // While the bottom path was doing all that multiplication, the top path (Sum)
    // was sitting in the 'leftv/leftvv' delay line. Now we retrieve it.
    
    always @(posedge i_clk)
    if (i_ce)
        left_saved <= leftvv; // Retrieve the delayed Sum (L+R)

    // --- Scaling Logic ---
    // The "Difference" path was multiplied by a Twiddle Factor (CWIDTH bits).
    // This effectively shifted its decimal point.
    // The "Sum" path was NOT multiplied.
    // To align the decimal points for the final output stage, we must "scale up"
    // the Sum path by appending zeros to the LSB.
    //
    // Mathematically: Sum_Scaled = Sum * 2^(CWIDTH-2)
    
    assign  left_sr = { 
        {2{left_saved[2*(IWIDTH+1)-1]}},             // Sign Extend Top
        left_saved[(2*(IWIDTH+1)-1):(IWIDTH+1)],     // The Real Data
        {(CWIDTH-2){1'b0}}                           // Zero Padding (Shift Left)
    };
    
    assign  left_si = { 
        {2{left_saved[(IWIDTH+1)-1]}},               // Sign Extend Top
        left_saved[((IWIDTH+1)-1):0],                // The Imag Data
        {(CWIDTH-2){1'b0}}                           // Zero Padding (Shift Left)
    };
    
    // Recover the Aux Sync signal (stored in the MSB)
    assign  aux_s = left_saved[2*IWIDTH+2];
	// ========================================================================
    // 8. DATA RECOVERY & SYNC
    // ========================================================================
    
    always @(posedge i_clk)
    if (i_reset)
    begin
        left_saved <= 0;
        o_aux <= 1'b0;
    end else if (i_ce)
    begin
        // Recover Sum Path:
        // Retrieve the "Sum" (L+R) data from the delay line ('leftvv').
        // It has been waiting there while the Multiplier (Diff path) finished.
        left_saved <= leftvv;

        // Output Sync Signal:
        // 'aux_s' is the synchronization pulse that traveled down the pipeline.
        // We output it now ('o_aux') to tell the next module "Data is Valid".
        o_aux <= aux_s;
    end

    // ========================================================================
    // 9. KARATSUBA RECONSTRUCTION (The Final Math)
    // ========================================================================
    // We have the three partial products:
    // P1 (w_one)   = Real * Real
    // P2 (w_two)   = Imag * Imag
    // P3 (p_three) = (Real+Imag) * (Real+Imag)
    
    // Now we reconstruct the Complex Multiplication result:
    // Real Part = A*C - B*D  => P1 - P2
    // Imag Part = A*D + B*C  => P3 - P1 - P2
    
    always @(posedge i_clk)
    if (i_ce)
    begin
        // Calculate Real Part
        // w_one and w_two are the sign-extended versions of P1 and P2.
        mpy_r <= w_one - w_two;
        
        // Calculate Imaginary Part
        mpy_i <= p_three - w_one - w_two;
        
        // NOTE: The (* use_dsp48="no" *) attribute defined earlier applies here.
        // It ensures these subtractions are built with FPGA Logic (LUTs),
        // saving expensive DSP slices for actual multiplications.
    end

    // ========================================================================
    // 10. CONVERGENT ROUNDING
    // ========================================================================
    // The data has grown significantly in bit width. We must round it back
    // down to 'OWIDTH' to fit the output wires.
    
    // --- Rounding the Sum Path (Top) ---
    // Inputs: left_sr (Real), left_si (Imag)
    // Shift: SHIFT+2. This accounts for the 1-bit growth in the first Add/Sub
    //        plus the alignment padding we added earlier.
    convround #(CWIDTH+IWIDTH+1, OWIDTH, SHIFT+2)
        do_rnd_left_r(i_clk, i_ce, left_sr, rnd_left_r);

    convround #(CWIDTH+IWIDTH+1, OWIDTH, SHIFT+2)
        do_rnd_left_i(i_clk, i_ce, left_si, rnd_left_i);

    // --- Rounding the Diff Path (Bottom / Multiplier) ---
    // Inputs: mpy_r (Real), mpy_i (Imag)
    // Shift: SHIFT+4. This accounts for the massive bit growth during multiplication.
    //        We drop the extra fractional bits created by the Twiddle Factor.
    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_right_r(i_clk, i_ce, mpy_r, rnd_right_r);

    convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
        do_rnd_right_i(i_clk, i_ce, mpy_i, rnd_right_i);

    // ========================================================================
    // 11. FINAL OUTPUT PACKING
    // ========================================================================
    // Concatenate the Real and Imaginary parts into single output buses.
    // [Upper Bits] = Real
    // [Lower Bits] = Imaginary
    
    assign  o_left  = { rnd_left_r,  rnd_left_i };
    assign  o_right = { rnd_right_r, rnd_right_i };

// End of Module (Formal Verification block removed)
endmodule