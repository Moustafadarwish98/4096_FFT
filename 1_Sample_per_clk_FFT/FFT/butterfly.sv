
// caculates a butterfly for a decimation
//	in frequency version of an FFT.  Specifically, given
//	complex Left and Right values together with a coefficient, the output
//	of this routine is given by:
//
//		L' = L + R
//		R' = (L - R)*C
//
//	The rest of the junk below handles timing , to make certain
//	that L' and R' reach the output at the same clock.  Further, just to
//	make certain that is the case, an 'aux' input exists.  This aux value
//	will come out of this routine synchronized to the values it came in
//	with.  (i.e., both L', R', and aux all have the same delay.)  Hence,
//	a caller of this routine may set aux on the first input with valid
//	data, and then wait to see aux set on the output to know when to find
//	the first output with valid data.
//
//	All bits are preserved until the very last clock, where any more bits
//	than OWIDTH will be quietly discarded.
//	3-MULTIPLIES:
//		It should also be possible to do this with three multiplies
//		and an extra two addition cycles.
//
//		We want
//			R+I = (a + jb) * (c + jd)
//			R+I = (ac-bd) + j(ad+bc)
//		We multiply
//			P1 = ac
//			P2 = bd
//			P3 = (a+b)(c+d)
//		Then
//			R+I=(P1-P2)+j(P3-P2-P1)


`default_nettype	none

module	butterfly #(
    // the input data width
    parameter IWIDTH=16,

    // This is the width of the twiddle factor, the 'coefficient'
    // if you will.
    CWIDTH=20,
    // This is the width of the final output
    OWIDTH=17,
    // SHIFT
    // The shift controls whether or not the result will be
    // left shifted by SHIFT bits, throwing the overflow
    // away.
    parameter	SHIFT=0,

    parameter	CKPCE=1,

    // MXMPYBITS
    // The first step is to calculate how many clocks it takes
    // our multiply to come back with an answer within.  The
    // time in the multiply depends upon the input value with
    // the fewest number of bits--to keep the pipeline depth
    // short.
    localparam MXMPYBITS =
    ((IWIDTH+2)>(CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH + 2),
    // MPYDELAY
    // Given this "fewest" number of bits, we can calculate
    // the number of clocks the multiply itself will take.(Heuristic)
    localparam	MPYDELAY=((MXMPYBITS+1)/2)+2,

    localparam	LGDELAY = (MPYDELAY>64) ? 7
    : (MPYDELAY > 32) ? 6
    : (MPYDELAY > 16) ? 5
    : (MPYDELAY >  8) ? 4
    : (MPYDELAY >  4) ? 3
    : 2,
    localparam	AUXLEN=(MPYDELAY+3)
  ) (
    // {{{
    input	wire	i_clk, i_reset, i_clk_enable,
    input	wire	[(2*CWIDTH-1):0] i_coef,
    input	wire	[(2*IWIDTH-1):0] i_left, i_right,
    input	wire	i_aux,
    output	wire	[(2*OWIDTH-1):0] o_left, o_right,
    output	reg	o_aux
    // }}}
  );

  // Local declarations
  reg	[(2*IWIDTH-1):0]	r_left, r_right;
  reg	[(2*CWIDTH-1):0]	r_coef, r_coef_2;
  wire	signed	[(IWIDTH-1):0]	r_left_r, r_left_i, r_right_r, r_right_i;
  reg	signed	[(IWIDTH):0]	r_sum_r, r_sum_i, r_dif_r, r_dif_i;

  reg	[(LGDELAY-1):0]	fifo_addr;
  wire	[(LGDELAY-1):0]	fifo_read_addr;
  reg	[(2*IWIDTH+1):0]	fifo_left [ 0:((1<<LGDELAY)-1)];
  wire	signed	[(CWIDTH-1):0]	ir_coef_r, ir_coef_i;
  wire	signed	[((IWIDTH+2)+(CWIDTH+1)-1):0]	p_one, p_two, p_three;
  wire	signed	[(IWIDTH+CWIDTH):0]	fifo_i, fifo_r;

  reg		[(2*IWIDTH+1):0]	fifo_read;

  reg	signed	[(CWIDTH+IWIDTH+3-1):0]	mpy_r, mpy_i;

  wire	signed	[(OWIDTH-1):0]	rnd_left_r, rnd_left_i, rnd_right_r, rnd_right_i;

  wire	signed	[(CWIDTH+IWIDTH+3-1):0]	left_sr, left_si;
  reg	[(AUXLEN-1):0]	aux_pipeline;

  // Break complex registers into their real and imaginary components

  assign	r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
  assign	r_left_i  = r_left[ (IWIDTH-1):0];
  assign	r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
  assign	r_right_i = r_right[(IWIDTH-1):0];

  assign	ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
  assign	ir_coef_i = r_coef_2[(CWIDTH-1):0];


  assign	fifo_read_addr = fifo_addr - MPYDELAY[(LGDELAY-1):0];

  // r_left, r_right, r_coef, r_sum_[r|i], r_dif_[r|i], r_coef_2
  // Set up the input to the multiply
  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      // One clock just latches the inputs
      r_left <= i_left;	// No change in # of bits
      r_right <= i_right;
      r_coef  <= i_coef;
      // Next clock adds/subtracts
      r_sum_r <= r_left_r + r_right_r; // Now IWIDTH+1 bits
      r_sum_i <= r_left_i + r_right_i;
      r_dif_r <= r_left_r - r_right_r;
      r_dif_i <= r_left_i - r_right_i;
      // Other inputs are simply delayed on second clock
      r_coef_2<= r_coef;
    end

  // fifo_addr
  // Don't forget to record the even side, since it doesn't need
  // to be multiplied, but yet we still need the results in sync
  // with the answer when it is ready.

  always @(posedge i_clk)
    if (i_reset)
      fifo_addr <= 0;
    else if (i_clk_enable)
      // Need to delay the sum side--nothing else happens
      // to it, but it needs to stay synchronized with the
      // right side.
      fifo_addr <= fifo_addr + 1;

  // Write into the left-side input FIFO
  always @(posedge i_clk)
    if (i_clk_enable)
      fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };

  // Notes
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

  // Instantiate the multiplies

  // Local declarations
  wire	[(CWIDTH):0]	p3c_in;
  wire	[(IWIDTH+1):0]	p3d_in;

  assign	p3c_in = ir_coef_i + ir_coef_r;
  assign	p3d_in = r_dif_r + r_dif_i;

  // p_one = ir_coef_r * r_dif_r
  // We need to pad these first two multiplies by an extra
  // bit just to keep them aligned with the third,
  // simpler, multiply.
  longbimpy #(
              .IAW(CWIDTH+1), .IBW(IWIDTH+2)
            ) p1(
              // {{{
              .i_clk(i_clk), .i_clk_enable(i_clk_enable),
              .i_a_unsorted({ir_coef_r[CWIDTH-1],ir_coef_r}),
              .i_b_unsorted({r_dif_r[IWIDTH],r_dif_r}),
              .o_r(p_one)

            );

  // p_two = ir_coef_i * r_dif_i
  longbimpy #(
              .IAW(CWIDTH+1), .IBW(IWIDTH+2)
            ) p2(
              // {{{
              .i_clk(i_clk), .i_clk_enable(i_clk_enable),
              .i_a_unsorted({ir_coef_i[CWIDTH-1],ir_coef_i}),
              .i_b_unsorted({r_dif_i[IWIDTH],r_dif_i}),
              .o_r(p_two)

            );

  // p_three = (ir_coef_i + ir_coef_r) * (r_dif_r + r_dif_i)
  longbimpy #(
              .IAW(CWIDTH+1), .IBW(IWIDTH+2)
            ) p3(
              // {{{
              .i_clk(i_clk), .i_clk_enable(i_clk_enable),
              .i_a_unsorted(p3c_in),
              .i_b_unsorted(p3d_in),
              .o_r(p_three)
            );


  // fifo_r, fifo_i
  // These values are held in memory and delayed during the
  // multiply.  Here, we recover them.  During the multiply,
  // values were multiplied by 2^(CWIDTH-2)*exp{-j*2*pi*...},
  // therefore, the left_x values need to be right shifted by
  // CWIDTH-2 as well.  The additional bits come from a sign
  // extension.
  assign	fifo_r = { {2{fifo_read[2*(IWIDTH+1)-1]}},
                    fifo_read[(2*(IWIDTH+1)-1):(IWIDTH+1)], {(CWIDTH-2){1'b0}} };
  assign	fifo_i = { {2{fifo_read[(IWIDTH+1)-1]}},
                    fifo_read[((IWIDTH+1)-1):0], {(CWIDTH-2){1'b0}} };

  // Rounding and shifting
  // Notes
  // Let's do some rounding and remove unnecessary bits.
  // We have (IWIDTH+CWIDTH+3) bits here, we need to drop down to
  // OWIDTH, and SHIFT by SHIFT bits in the process.  The trick is
  // that we don't need (IWIDTH+CWIDTH+3) bits.  We've accumulated
  // them, but the actual values will never fill all these bits.
  // In particular, we only need:
  //	 IWIDTH bits for the input
  //	     +1 bit for the add/subtract
  //	+CWIDTH bits for the coefficient multiply
  //	     +1 bit for the add/subtract in the complex multiply
  //	 ------
  //	 (IWIDTH+CWIDTH+2) bits at full precision.
  //
  // However, the coefficient multiply multiplied by a maximum value
  // of 2^(CWIDTH-2).  Thus, we only have
  //	   IWIDTH bits for the input
  //	       +1 bit for the add/subtract
  //	+CWIDTH-2 bits for the coefficient multiply
  //	       +1 (optional) bit for the add/subtract in the cpx mpy.
  //	 -------- ... multiply.  (This last bit may be shifted out.)
  //	 (IWIDTH+CWIDTH) valid output bits.
  // Now, if the user wants to keep any extras of these (via OWIDTH),
  // or if he wishes to arbitrarily shift some of these off (via
  // SHIFT) we accomplish that here.

  assign	left_sr = { {(2){fifo_r[(IWIDTH+CWIDTH)]}}, fifo_r };
  assign	left_si = { {(2){fifo_i[(IWIDTH+CWIDTH)]}}, fifo_i };

  convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
            do_rnd_left_r(i_clk, i_clk_enable, left_sr, rnd_left_r);

  convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
            do_rnd_left_i(i_clk, i_clk_enable, left_si, rnd_left_i);

  convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
            do_rnd_right_r(i_clk, i_clk_enable, mpy_r, rnd_right_r);

  convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
            do_rnd_right_i(i_clk, i_clk_enable, mpy_i, rnd_right_i);

  // fifo_read, mpy_r, mpy_i

  // Unwrap the three multiplies into the two multiply results
  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      // First clock, recover all values
      fifo_read <= fifo_left[fifo_read_addr];
      // These values are IWIDTH+CWIDTH+3 bits wide
      // although they only need to be (IWIDTH+1)
      // + (CWIDTH) bits wide.  (We've got two
      // extra bits we need to get rid of.)
      mpy_r <= p_one - p_two;
      mpy_i <= p_three - p_one - p_two;
    end

  always @(posedge i_clk)
    if (i_reset)
      aux_pipeline <= 0;
    else if (i_clk_enable)
      aux_pipeline <= { aux_pipeline[(AUXLEN-2):0], i_aux };

  initial
    o_aux = 1'b0;
  always @(posedge i_clk)
    if (i_reset)
      o_aux <= 1'b0;
    else if (i_clk_enable)
    begin
      // Second clock, latch for final clock
      o_aux <= aux_pipeline[AUXLEN-1];
    end

  // o_left, o_right
  assign	o_left = { rnd_left_r, rnd_left_i };
  assign	o_right= { rnd_right_r,rnd_right_i};

endmodule
