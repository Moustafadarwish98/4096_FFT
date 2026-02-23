// Purpose:	This file encapsulates the 4 point stage of a decimation in
//		frequency FFT.  This particular implementation is optimized
//	so that all of the multiplies are accomplished by additions and
//	multiplexers only.
//
// Operation:
// 	The operation of this stage is identical to the regular stages of
// 	the FFT (see them for details), with one additional and critical
// 	difference: this stage doesn't require any hardware multiplication.
// 	The multiplies within it may all be accomplished using additions and
// 	subtractions.
//
// 	Let's see how this is done.  Given x[n] and x[n+2], cause thats the
// 	stage we are working on, with i_sync true for x[0] being input,
// 	produce the output:
//
// 	y[n  ] = x[n] + x[n+2]
// 	y[n+2] = (x[n] - x[n+2]) * e^{-j2pi n/2}	(forward transform)
// 	       = (x[n] - x[n+2]) * -j^n
//
// 	y[n].r = x[n].r + x[n+2].r	(This is the easy part)
// 	y[n].i = x[n].i + x[n+2].i
//
// 	y[2].r = x[0].r - x[2].r
// 	y[2].i = x[0].i - x[2].i
//
// 	y[3].r =   (x[1].i - x[3].i)		(forward transform)
// 	y[3].i = - (x[1].r - x[3].r)
//
// 	y[3].r = - (x[1].i - x[3].i)		(inverse transform)
// 	y[3].i =   (x[1].r - x[3].r)		(INVERSE = 1)

module	qtrstage(i_clk, i_reset, i_clk_enable, i_sync, i_data, o_data, o_sync);
  parameter	IWIDTH=16, OWIDTH=IWIDTH+1;
  parameter	LGWIDTH=8, INVERSE=0,SHIFT=0;
  input	wire				i_clk, i_reset, i_clk_enable, i_sync;
  input	wire	[(2*IWIDTH-1):0]	i_data;
  output	reg	[(2*OWIDTH-1):0]	o_data;
  output	reg				o_sync;

  reg		wait_for_sync;
  reg	[2:0]	pipeline;

  reg	signed [(IWIDTH):0]	sum_r, sum_i, diff_r, diff_i;

  reg	[(2*OWIDTH-1):0]	ob_a;
  wire	[(2*OWIDTH-1):0]	ob_b;
  reg	[(OWIDTH-1):0]		ob_b_r, ob_b_i;
  assign	ob_b = { ob_b_r, ob_b_i };

  reg	[(LGWIDTH-1):0]		iaddr;
  reg	[(2*IWIDTH-1):0]	imem	[0:1];

  wire	signed	[(IWIDTH-1):0]	imem_r, imem_i;
  assign	imem_r = imem[1][(2*IWIDTH-1):(IWIDTH)];
  assign	imem_i = imem[1][(IWIDTH-1):0];

  wire	signed	[(IWIDTH-1):0]	i_data_r, i_data_i;
  assign	i_data_r = i_data[(2*IWIDTH-1):(IWIDTH)];
  assign	i_data_i = i_data[(IWIDTH-1):0];

  reg	[(2*OWIDTH-1):0]	omem [0:1];

  // Round our output values down to OWIDTH bits
  wire	signed	[(OWIDTH-1):0]	rnd_sum_r, rnd_sum_i,
       rnd_diff_r, rnd_diff_i, n_rnd_diff_r, n_rnd_diff_i;
  convround #(IWIDTH+1,OWIDTH,SHIFT)	do_rnd_sum_r(i_clk, i_clk_enable,
            sum_r, rnd_sum_r);

  convround #(IWIDTH+1,OWIDTH,SHIFT)	do_rnd_sum_i(i_clk, i_clk_enable,
            sum_i, rnd_sum_i);

  convround #(IWIDTH+1,OWIDTH,SHIFT)	do_rnd_diff_r(i_clk, i_clk_enable,
            diff_r, rnd_diff_r);

  convround #(IWIDTH+1,OWIDTH,SHIFT)	do_rnd_diff_i(i_clk, i_clk_enable,
            diff_i, rnd_diff_i);

  assign n_rnd_diff_r = - rnd_diff_r;
  assign n_rnd_diff_i = - rnd_diff_i;

  always @(posedge i_clk)
    if (i_reset)
    begin
      wait_for_sync <= 1'b1;
      iaddr <= 0;
    end
    else if ((i_clk_enable)&&((!wait_for_sync)||(i_sync)))
    begin
      iaddr <= iaddr + 1'b1;
      wait_for_sync <= 1'b0;
    end

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      imem[0] <= i_data;
      imem[1] <= imem[0];
    end


  // Note that we don't check on wait_for_sync or i_sync here.
  // Why not?  Because iaddr will always be zero until after the
  // first i_clk_enable, so we are safe.

  always	@(posedge i_clk)
    if (i_reset)
      pipeline <= 3'h0;
    else if (i_clk_enable) // is our pipeline process full?  Which stages?
      pipeline <= { pipeline[1:0], iaddr[1] };

  // This is the pipeline[-1] stage, pipeline[0] will be set next.
  always	@(posedge i_clk)
    if ((i_clk_enable)&&(iaddr[1]))
    begin
      sum_r  <= imem_r + i_data_r;
      sum_i  <= imem_i + i_data_i;
      diff_r <= imem_r - i_data_r;
      diff_i <= imem_i - i_data_i;
    end

  // pipeline[1] takes sum_x and diff_x and produces rnd_x

  // Now for pipeline[2].  We can actually do this at all i_clk_enable
  // clock times, since nothing will listen unless pipeline[3]
  // on the next clock.  Thus, we simplify this logic and do
  // it independent of pipeline[2].
  always	@(posedge i_clk)
    if (i_clk_enable)
    begin
      ob_a <= { rnd_sum_r, rnd_sum_i };
      // on Even, W = e^{-j2pi 1/4 0} = 1
      if (!iaddr[0])
      begin
        ob_b_r <= rnd_diff_r;
        ob_b_i <= rnd_diff_i;
      end
      else if (INVERSE==0)
      begin
        // on Odd, W = e^{-j2pi 1/4} = -j
        ob_b_r <=   rnd_diff_i;
        ob_b_i <= n_rnd_diff_r;
      end
      else
      begin
        // on Odd, W = e^{j2pi 1/4} = j
        ob_b_r <= n_rnd_diff_i;
        ob_b_i <=   rnd_diff_r;
      end
    end

  always	@(posedge i_clk)
    if (i_clk_enable)
    begin // In sequence, clock = 3
      omem[0] <= ob_b;
      omem[1] <= omem[0];
      if (pipeline[2])
        o_data <= ob_a;
      else
        o_data <= omem[1];
    end

  always	@(posedge i_clk)
    if (i_reset)
      o_sync <= 1'b0;
    else if (i_clk_enable)
      o_sync <= (iaddr[2:0] == 3'b101);


endmodule
