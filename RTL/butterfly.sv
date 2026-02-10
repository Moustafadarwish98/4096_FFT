
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
        parameter   SHIFT=0,
        parameter   CKPCE=1,

        localparam MXMPYBITS = ((IWIDTH+2)>(CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH + 2),

        localparam  MPYDELAY=((MXMPYBITS+1)/2)+2,

        localparam  LCLDELAY = (CKPCE == 1) ? MPYDELAY
            : (CKPCE == 2) ? (MPYDELAY/2+2)
            : (MPYDELAY/3 + 2),

        localparam  LGDELAY = (MPYDELAY>64) ? 7
            : (MPYDELAY > 32) ? 6
            : (MPYDELAY > 16) ? 5
            : (MPYDELAY >  8) ? 4
            : (MPYDELAY >  4) ? 3
            : 2,
        
        localparam  AUXLEN=(LCLDELAY+3),
        localparam  MPYREMAINDER = MPYDELAY - CKPCE*(MPYDELAY/CKPCE)
    ) (
        // --- Ports ---
        input   wire                        i_clk, i_reset, i_clk_enable,
        input   wire    [(2*CWIDTH-1):0]    i_coef,         // Twiddle (Real+Imag)
        input   wire    [(2*IWIDTH-1):0]    i_left, i_right,// Inputs (Real+Imag)

        input   wire                        i_aux,
        
        output  wire    [(2*OWIDTH-1):0]    o_left, o_right,// Outputs (Real+Imag)
        
        output  reg                         o_aux
    );

    reg     [(2*IWIDTH-1):0]    r_left, r_right;
    reg     [(2*CWIDTH-1):0]    r_coef;         // Twiddle Factor (Stage 1)
    reg     [(2*CWIDTH-1):0]    r_coef_2;       // Twiddle Factor (Stage 2 - Pipelined),aligns coefficient with multiplier pipeline
    
    wire    signed  [(IWIDTH-1):0]  r_left_r, r_left_i;   // Left Real/Imag
    wire    signed  [(IWIDTH-1):0]  r_right_r, r_right_i; // Right Real/Imag
    reg     signed  [(IWIDTH):0]    r_sum_r, r_sum_i;     // Sum (L+R)
    reg     signed  [(IWIDTH):0]    r_dif_r, r_dif_i;     // Diff (L-R)

    reg     [(LGDELAY-1):0]     fifo_addr;       // Write Address Pointer
    wire    [(LGDELAY-1):0]     fifo_read_addr;  // Read Address Pointer

    reg     [(2*IWIDTH+1):0]    fifo_left [ 0:((1<<LGDELAY)-1)];
    // The Data read out of the FIFO (Delayed Sum)
    reg     [(2*IWIDTH+1):0]    fifo_read;
    // Unpacked Delayed Sum components
    wire    signed  [(IWIDTH):0]    fifo_r, fifo_i;
    
    wire    signed  [(CWIDTH-1):0]              ir_coef_r, ir_coef_i;
    wire    signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]   p_one, p_two, p_three; // Partial Products
    
    // Final Multiplication Result (before Rounding)
    reg     signed  [(CWIDTH+IWIDTH+3-1):0]     mpy_r, mpy_i;

    // --- Rounding Wires ---
    wire    signed  [(OWIDTH-1):0]  rnd_left_r, rnd_left_i;   // Final Rounded Sum
    wire    signed  [(OWIDTH-1):0]  rnd_right_r, rnd_right_i; // Final Rounded Diff

    wire    signed  [(CWIDTH+IWIDTH+3-1):0] left_sr, left_si;

    // --- Aux Pipeline ---
    // Delay line for the synchronization signal.
    reg     [(AUXLEN-1):0]      aux_pipeline;

    reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]  rp_one, rp_two, rp_three;
    reg signed  [((IWIDTH+2)+(CWIDTH+1)-1):0]  rp2_one, rp2_two, rp2_three, rp3_one;

    // Multiplier output wire (accessible to all generate blocks)
    wire signed [(CWIDTH+IWIDTH+3-1):0] mpy_pipe_out;
    
    assign  r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
    assign  r_left_i  = r_left[ (IWIDTH-1):0];
    assign  r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
    assign  r_right_i = r_right[(IWIDTH-1):0];

    // Coefficient unpacking (from the second pipeline stage register)
    assign  ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
    assign  ir_coef_i = r_coef_2[(CWIDTH-1):0];
    
    assign  fifo_read_addr = fifo_addr - LCLDELAY[(LGDELAY-1):0];

    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // --- Pipeline Stage 1: Input Latching ---
        // Isolates the internal logic from external routing delays.
        r_left  <= i_left;   // Latched Input A
        r_right <= i_right;  // Latched Input B
        r_coef  <= i_coef;   // Latched Twiddle Factor

        r_sum_r <= r_left_r + r_right_r; 
        r_sum_i <= r_left_i + r_right_i;
        r_dif_r <= r_left_r - r_right_r;
        r_dif_i <= r_left_i - r_right_i;
        // Pass the coefficient forward to Stage 2 to align with Diff result
        r_coef_2<= r_coef;
    end

    always @(posedge i_clk)
    if (i_reset)
        fifo_addr <= 0;
    else if (i_clk_enable)
        // Increment Write Pointer linearly
        fifo_addr <= fifo_addr + 1;

    always @(posedge i_clk)
    if (i_clk_enable)
        fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };

    generate if (CKPCE <= 1)
    begin : CKPCE_ONE

        wire    [(CWIDTH):0]    p3c_in; // Sum of Coeffs (Width + 1 bit growth)
        wire    [(IWIDTH+1):0]  p3d_in; // Sum of Data   (Width + 1 bit growth)
        // Math: (ir_coef_r + j ir_coef_i) -> Sum = Real + Imag
        assign  p3c_in = ir_coef_i + ir_coef_r;
        // Math: (r_dif_r + j r_dif_i)     -> Sum = Real + Imag
        assign  p3d_in = r_dif_r + r_dif_i;
 
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
        
        longbimpy #(
            .IAW(CWIDTH+1),  // Input A Width (Padded to match P3)
            .IBW(IWIDTH+2)   // Input B Width (Padded to match P3)
        ) p2(
            .i_clk(i_clk), 
            .i_clk_enable(i_clk_enable),

            .i_a_unsorted({ir_coef_i[CWIDTH-1], ir_coef_i}), 
            .i_b_unsorted({r_dif_i[IWIDTH],     r_dif_i}),
            
            .o_r(p_two) // Result P2
        );

        longbimpy #(
            .IAW(CWIDTH+1), 
            .IBW(IWIDTH+2)
        ) p3(
            .i_clk(i_clk), 
            .i_clk_enable(i_clk_enable),
            .i_a_unsorted(p3c_in),
            .i_b_unsorted(p3d_in),
            
            .o_r(p_three) // Result P3
        );

    end 
    
    endgenerate // End of Multiplier Architecture Generation
    // Align Karatsuba partial products
always @(posedge i_clk)
if (i_clk_enable) begin
    rp_one   <= p_one;
    rp_two   <= p_two;
    rp_three <= p_three;
end


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
    
    assign  left_sr = { {(2){fifo_r[(IWIDTH+CWIDTH)]}}, fifo_r };
    assign  left_si = { {(2){fifo_i[(IWIDTH+CWIDTH)]}}, fifo_i };
    
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
    /*wire data_valid;
assign data_valid = aux_pipeline[AUXLEN-2];
always @(posedge i_clk)
if (i_clk_enable && data_valid)
    fifo_read <= fifo_left[fifo_read_addr];

*/
    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        fifo_read <= fifo_left[fifo_read_addr];
    mpy_r <= rp_one - rp_two;
    mpy_i <= rp_three - rp_one - rp_two;
    end

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
    /*reg [(2*OWIDTH-1):0] o_left_r, o_right_r;

always @(posedge i_clk)
if (i_reset) begin
    o_left_r  <= 0;
    o_right_r <= 0;
end else if (i_clk_enable && o_aux) begin
    o_left_r  <= { rnd_left_r,  rnd_left_i };
    o_right_r <= { rnd_right_r, rnd_right_i };
end

assign o_left  = o_left_r;
assign o_right = o_right_r;
*/

    assign  o_left  = { rnd_left_r,  rnd_left_i };
    assign  o_right = { rnd_right_r, rnd_right_i };

endmodule