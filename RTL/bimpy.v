// Purpose:	A simple 2-bit multiply based upon the fact that LUT's allow
//		6-bits of input.  In other words, I could build a 3-bit
//	multiply from 6 LUTs (5 actually, since the first could have two
//	outputs).  This would allow multiplication of three bit digits, save
//	only for the fact that you would need two bits of carry.  The bimpy
//	approach throttles back a bit and does a 2x2 bit multiply in a LUT,
//	guaranteeing that it will never carry more than one bit.  While this
//	multiply is hardware independent (and can still run under Verilator
//	therefore), it is really motivated by trying to optimize for a
//	specific piece of hardware (Xilinx-7 series ...) that has at least
//	4-input LUT's with carry chains.
`default_nettype    none

// Purpose: A highly optimized 2xN bit multiplier.
// It maps efficiently to FPGA LUTs (Look-Up Tables) and Carry Chains.
module  bimpy #(
        parameter   BW=18, // Width of the large input (Input B)
        localparam  LUTB=2 // Width of the small input (Input A) - Fixed at 2
    ) (
        input   wire            i_clk, i_reset, i_clk_enable,
        input   wire    [(LUTB-1):0]    i_a, // The 2-bit Multiplier
        input   wire    [(BW-1):0]  i_b, // The N-bit Multiplicand
        output  reg [(BW+LUTB-1):0] o_r  // Result (Width = N + 2)
    );

    // ====================================================================
    // 1. COMBINATORIAL LOGIC (The Half-Adder)
    // ====================================================================
    // We are calculating: (i_a[1] * i_b << 1) + (i_a[0] * i_b)
    //
    // Instead of a full adder, we compute the "Sum" bits (XOR) and 
    // "Carry" bits (AND) separately.

    // w_r: The "Partial Sum" (XOR)
    // Conceptually: (Val1 XOR Val2)
    // Val1 = If a[1] is 1, take B and shift left 1. Else 0.
    // Val2 = If a[0] is 1, take B. Else 0.
    wire    [(BW+LUTB-2):0] w_r;
    
    assign  w_r = { ((i_a[1]) ? i_b : {(BW){1'b0}}), 1'b0 }  // (a[1] * B) << 1
                ^ { 1'b0, ((i_a[0]) ? i_b : {(BW){1'b0}}) }; // (a[0] * B)

    // c: The "Carry" (AND)
    // Conceptually: (Val1 AND Val2)
    // We check where BOTH terms have a '1', which would generate a carry 
    // to the next bit position.
    // Note on indices: We are aligning the bits that overlap.
    wire    [(BW+LUTB-3):1] c;
    
    assign  c = { ((i_a[1]) ? i_b[(BW-2):0] : {(BW-1){1'b0}}) }
              & { ((i_a[0]) ? i_b[(BW-1):1] : {(BW-1){1'b0}}) };

    // ====================================================================
    // 2. REGISTERED OUTPUT (The Final Addition)
    // ====================================================================
    // Now we use the FPGA's fast Carry Chain to add the Partial Sum ('w_r')
    // and the Carries ('c').
    //
    // The carries 'c' are shifted left by 2 ({c, 2'b0}) because a carry generated
    // at bit N contributes to bit N+1. Since our logic is 2-bit aligned, 
    // this specific shift aligns the carry to the correct addition column.

    always @(posedge i_clk)
    if (i_reset)
        o_r <= 0;
    else if (i_clk_enable)
        o_r <= w_r + { c, 2'b0 };

endmodule