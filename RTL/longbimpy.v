
// Purpose:	A portable shift and add multiply, built with the knowledge
//	of the existence of a six bit LUT and carry chain.  That knowledge
//	allows us to multiply two bits from one value at a time against all
//	of the bits of the other value.  This sub multiply is called the
//	bimpy.
//
//	For minimal processing delay, make the first parameter the one with
//	the least bits, so that AWIDTH <= BWIDTH.

`default_nettype    none
module  longbimpy #(
        // ====================================================================
        // 1. CONFIGURATION & SIZING
        // ====================================================================
        parameter   IAW=8,  // Input Width A (e.g., 8 bits)
                IBW=12, // Input Width B (e.g., 12 bits)
            
        // --- Optimization Logic ---
        // Multiplication is commutative (A*B = B*A).
        // However, in a pipelined "Shift-and-Add" multiplier, the number of 
        // stages (latency) is determined by the width of the FIRST operand.
        // To minimize area and latency, we MUST ensure the first operand (AW)
        // is the smaller of the two inputs.

        localparam  AW = (IAW<IBW) ? IAW : IBW, // Force AW to be the smaller width
                BW = (IAW<IBW) ? IBW : IAW, // Force BW to be the larger width
                
                // --- Internal Width (IW) ---
                // This logic processes data in 2-bit chunks (Radix-4).
                // We need the input width to be an even number.
                // Logic: (AW+1) & (-2) rounds up to the next even number.
                // Ex: If AW=5 (binary 101), AW+1=6 (110). 6 & -2 (110 & 110) = 6.
                IW=(AW+1)&(-2), 

                LUTB=2, // Bits to multiply per stage (Hardcoded to 2)
                TLEN=(AW+(LUTB-1))/LUTB // Tableau Length: Total pipeline stages required.
    ) (
        // ====================================================================
        // 2. PORTS
        // ====================================================================
        input   wire            i_clk, i_ce,
        input   wire    [(IAW-1):0] i_a_unsorted,
        input   wire    [(IBW-1):0] i_b_unsorted,
        output  reg [(AW+BW-1):0]   o_r
        
        // (Formal verification ports removed as requested)
    );

    // ====================================================================
    // 3. INPUT SWAPPING (ROUTING)
    // ====================================================================
    // Connect the smaller input to internal wire 'i_a' and larger to 'i_b'.
    
    wire    [AW-1:0]    i_a;
    wire    [BW-1:0]    i_b;
    
    generate begin : PARAM_CHECK
    if (IAW <= IBW)
    begin : NO_PARAM_CHANGE_I
        // No swap needed
        assign i_a = i_a_unsorted;
        assign i_b = i_b_unsorted;
    end else begin : SWAP_PARAMETERS_I
        // Swap inputs to optimize pipeline depth
        assign i_a = i_b_unsorted;
        assign i_b = i_a_unsorted;
    end end endgenerate

    // ====================================================================
    // 4. INTERNAL REGISTERS
    // ====================================================================
    reg [(IW-1):0]  u_a; // Unsigned, Padded version of A
    reg [(BW-1):0]  u_b; // Unsigned version of B
    reg         sgn; // Stores the final sign bit

    // Pipeline Arrays ("The Waterfall")
    // r_a: Carries the remaining bits of A down the pipeline.
    // r_b: Carries the value of B down the pipeline.
    // r_s: Carries the sign bit down.
    // acc: Accumulates the partial sums at each stage.
    reg [(IW-1-2*(LUTB)):0] r_a[0:(TLEN-3)];
    reg [(BW-1):0]      r_b[0:(TLEN-3)];
    reg [(TLEN-1):0]        r_s;
    reg [(IW+BW-1):0]       acc[0:(TLEN-2)];
    
    genvar k;
    wire    [(BW+LUTB-1):0] pr_a, pr_b; // Helper wires
    wire    [(IW+BW-1):0]   w_r;        // Helper wires

    // ====================================================================
    // 5. SIGN CONVERSION (Stage 0 Setup)
    // ====================================================================
    // Implementing "Shift-and-Add" on signed (Two's Complement) numbers 
    // is complicated. It is much easier to:
    // 1. Convert inputs to Absolute Value (Unsigned).
    // 2. Multiply them.
    // 3. Re-apply the sign at the end.

    // Calculate Absolute Value of A (u_a)
    initial u_a = 0;
    generate begin : ABS
    if (IW > AW)
    begin : ABS_AND_ADD_BIT_TO_A
        // Case: Padding Needed (AW was odd).
        // We calculate the absolute value and pad the top bit with 0 
        // to make the total width even (IW).
        always @(posedge i_clk)
        if (i_ce)
            // Ternary Op: If MSB is 1 (negative), negate i_a. Else keep i_a.
            u_a <= { 1'b0, (i_a[AW-1])?(-i_a):(i_a) };
            
    end else begin : ABS_A
        // Case: No Padding Needed (AW was even).
        always @(posedge i_clk)
        if (i_ce)
            u_a <= (i_a[AW-1])?(-i_a):(i_a);
            
    end end endgenerate

// ====================================================================
    // 5. ABSOLUTE VALUE OF B & SIGN CALCULATION
    // ====================================================================
    // We convert input B to unsigned (absolute value) to simplify math.
    // We also calculate the final sign bit (A_sign XOR B_sign).
    
    always @(posedge i_clk)
    if (i_ce)
    begin : ABS_B
        // Ternary Op: If B is negative (MSB=1), negate it. Else keep B.
        u_b <= (i_b[BW-1])?(-i_b):(i_b);
        
        // Sign Calculation: 
        // 0 ^ 0 = 0 (Pos * Pos = Pos)
        // 1 ^ 1 = 0 (Neg * Neg = Pos)
        // 1 ^ 0 = 1 (Neg * Pos = Neg)
        sgn <= i_a[AW-1] ^ i_b[BW-1];
    end

    // ====================================================================
    // 6. STAGE 1: THE FIRST 4 BITS (Two 2xN Multiplies)
    // ====================================================================
    // Optimization: Since we don't have a "Previous Sum" to add yet, we can
    // process the first TWO chunks (4 bits total) of 'u_a' in parallel.
    // Chunk 0: u_a[1:0]
    // Chunk 1: u_a[3:2]

    // Instantiate 'bimpy' for the Bottom 2 bits (Chunk 0)
    // Calculates: u_b * u_a[1:0]
    bimpy   #(
        .BW(BW) // Width of B
    ) lmpy_0(
        .i_clk(i_clk), .i_reset(1'b0), .i_ce(i_ce),
        .i_a(u_a[(  LUTB-1):   0]), // u_a[1:0]
        .i_b(u_b),
        .o_r(pr_a)                  // Result A
    );

    // Instantiate 'bimpy' for the Next 2 bits (Chunk 1)
    // Calculates: u_b * u_a[3:2]
    bimpy   #(
        .BW(BW) // Width of B
    ) lmpy_1(
        .i_clk(i_clk), .i_reset(1'b0), .i_ce(i_ce),
        .i_a(u_a[(2*LUTB-1):LUTB]), // u_a[3:2]
        .i_b(u_b),
        .o_r(pr_b)                  // Result B
    );

    // ====================================================================
    // 7. PIPELINE MANAGEMENT (Carrying values forward)
    // ====================================================================
    always @(posedge i_clk)
    if (i_ce)
    begin
        // Pass the REMAINING bits of 'u_a' down to the next stage.
        // We just consumed 4 bits (2*LUTB), so start from bit 4.
        r_a[0] <= u_a[(IW-1):(2*LUTB)];
        
        // Pass 'u_b' down (needed for every stage).
        r_b[0] <= u_b;
        
        // Shift the sign bit into the sign pipeline.
        // r_s is a shift register that carries the sign to the very end.
        r_s <= { r_s[(TLEN-2):0], sgn };
    end

    // ====================================================================
    // 8. ACCUMULATOR 0 (Combining the first two products)
    // ====================================================================
    // This runs one clock cycle AFTER the multipliers (lmpy_0/1) finish.
    // It adds the two partial products together, shifting the second one
    // by 2 bits (LUTB) because it corresponds to u_a[3:2].
    
    always @(posedge i_clk) // One clk after p[0],p[1] become valid
    if (i_ce)
        acc[0] <= { {(IW-LUTB){1'b0}}, pr_a }          // Product A (No shift)
                + { {(IW-(2*LUTB)){1'b0}}, pr_b, {(LUTB){1'b0}} }; // Product B (Shift left 2)

// ====================================================================
    // 9. PIPELINE DATA PROPAGATION (The "Waterfall")
    // ====================================================================
    // As we move down the pipeline, we need to carry the operands with us.
    // r_b: The multiplicand (stays the same, just copied down).
    // r_a: The multiplier (gets shifted/consumed as we go).

    generate begin : COPY
    if (TLEN > 3) begin : FOR
        // Loop through the remaining stages of the pipeline
        for(k=0; k<TLEN-3; k=k+1)
        begin : GENCOPIES

            initial r_a[k+1] = 0;
            initial r_b[k+1] = 0;
            
            always @(posedge i_clk)
            if (i_ce)
            begin
                // Shift r_a right by 2 bits (LUTB) to expose the next chunk
                // for the next stage.
                r_a[k+1] <= { {(LUTB){1'b0}}, 
                              r_a[k][(IW-1-(2*LUTB)):LUTB] };
                              
                // Just copy r_b down to the next stage.
                r_b[k+1] <= r_b[k];
            end
        end 
    end end endgenerate


    // ====================================================================
    // 10. MULTIPLY & ACCUMULATE STAGES
    // ====================================================================
    // This is the core "Shift-and-Add" loop.
    // Each iteration 'k' creates one hardware stage (one clock cycle of latency).
    
    generate begin : STAGES
    if (TLEN > 2) begin : FOR
        for(k=0; k<TLEN-2; k=k+1)
        begin : GENSTAGES
            wire    [(BW+LUTB-1):0] genp; // Partial Product for this stage

            // --- Step A: Calculate Partial Product ---
            // Multiply the current 2 bits of A (r_a[k]) by B (r_b[k]).
            // Result 'genp' can be 0, B, 2B, or 3B.
            bimpy #(
                .BW(BW)
            ) genmpy(
                .i_clk(i_clk), .i_reset(1'b0), .i_ce(i_ce),
                .i_a(r_a[k][(LUTB-1):0]), // The bottom 2 bits of current A
                .i_b(r_b[k]),             // Current B
                .o_r(genp)
            );

            // --- Step B: Accumulate ---
            // Add the new partial product to the running total.
            // We must SHIFT 'genp' to the left because it represents higher significance bits.
            //
            // Shift Calculation:
            // Stage -1 (Initial): Processed bits [3:0].
            // Stage k=0: Processes bits [5:4]. Needs shift of 4 (LUTB * 2).
            // Formula: shift = LUTB * (k + 2)
            
            initial acc[k+1] = 0;
            always @(posedge i_clk)
            if (i_ce)
                acc[k+1] <= acc[k] + { {(IW-LUTB*(k+3)){1'b0}}, // Zero padding top
                                       genp,                    // The value
                                       {(LUTB*(k+2)){1'b0}} };  // The Left Shift
        end 
    end end endgenerate


    // ====================================================================
    // 11. FINAL OUTPUT LOGIC
    // ====================================================================

    // --- Sign Application ---
    // We performed the math on Absolute Values (Unsigned).
    // Now we check the sign bit ('r_s') that traveled down the pipeline.
    // If sign is 1, negate the result (Two's Complement). Else keep it.
    // 'w_r' is the signed result wire.
    assign  w_r = (r_s[TLEN-1]) ? (-acc[TLEN-2]) : acc[TLEN-2];

    // --- Output Registering ---
    // Capture the final result into the output register.
    // We truncate to the requested output width (AW+BW).
    always @(posedge i_clk)
    if (i_ce)
        o_r <= w_r[(AW+BW-1):0];


    // ====================================================================
    // 12. UNUSED SIGNAL HANDLING
    // ====================================================================
    // If IW > AW (we padded inputs), the result 'w_r' might have extra
    // bits at the top that we don't need for 'o_r'. 
    // This block explicitly assigns them to 'unused' to suppress linter warnings.
    
    generate begin : GUNUSED
    if (IW > AW)
    begin : VUNUSED
        wire    unused;
        // OR-reduce the unused upper bits to show they are connected but ignored.
        assign  unused = &{ 1'b0, w_r[(IW+BW-1):(AW+BW)] };
    end end endgenerate
endmodule