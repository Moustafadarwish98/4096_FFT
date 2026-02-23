// Operation:
// 	Given a stream of values, operate upon them as though they were
// 	value pairs, x[n] and x[n+N/2].  The stream begins when n=0, and ends
// 	when n=N/2-1 (i.e. there's a full set of N values).  When the value
// 	x[0] enters, the synchronization input, i_sync, must be true as well.
//
// 	For this stream, produce outputs
// 	y[n    ] = x[n] + x[n+N/2], and
// 	y[n+N/2] = (x[n] - x[n+N/2]) * c[n],
// 			where c[n] is a complex coefficient found in the
// 			external memory file COEFFILE.
// 	When y[0] is output, a synchronization bit o_sync will be true as
// 	well, otherwise it will be zero.


module	fftstage #(
    parameter	IWIDTH=12,CWIDTH=20,OWIDTH=13,

    parameter	LGSPAN=11, BFLYSHIFT=0,  LGWIDTH=12,
    parameter [0:0]	OPT_HWMPY = 0,

    parameter	CKPCE = 1,
    // The COEFFILE parameter contains the name of the file
    // containing the FFT twiddle factors
    parameter	COEFFILE="cmem_4096.hex"

  ) (
    input	wire				i_clk, i_reset,i_clk_enable, i_sync,
    input	wire	[(2*IWIDTH-1):0]	i_data,
    output	reg	[(2*OWIDTH-1):0]	o_data,
    output	reg				o_sync

  );

  // Local signal definitions
  // 	ib_*	to reference the inputs to the butterfly, and
  // 	ob_*	to reference the outputs from the butterfly
  reg	wait_for_sync;
  reg	[(2*IWIDTH-1):0]	ib_a, ib_b;
  reg	[(2*CWIDTH-1):0]	ib_c;
  reg	ib_sync;

  reg	b_started;
  wire	ob_sync;
  wire	[(2*OWIDTH-1):0]	ob_a, ob_b;

  // cmem is defined as an array of real and complex values,
  // where the top CWIDTH bits are the real value and the bottom
  // CWIDTH bits are the imaginary value.
  //
  // cmem[i] = { (2^(CWIDTH-2)) * cos(2*pi*i/(2^LGWIDTH)),
  //		(2^(CWIDTH-2)) * sin(2*pi*i/(2^LGWIDTH)) };
  //
  reg	[(2*CWIDTH-1):0]	cmem [0:((1<<LGSPAN)-1)];
  // Initialize ROM from external HEX file
  initial
    $readmemh(COEFFILE, cmem);


  reg	[(LGSPAN):0]		iaddr;
  reg	[(2*IWIDTH-1):0]	imem	[0:((1<<LGSPAN)-1)];

  reg	[LGSPAN:0]		oaddr;
  reg	[(2*OWIDTH-1):0]	omem	[0:((1<<LGSPAN)-1)];

  reg	[(LGSPAN-1):0]		nxt_oaddr;
  reg	[(2*OWIDTH-1):0]	pre_ovalue;

  // wait_for_sync, iaddr

  always @(posedge i_clk)
    if (i_reset)
    begin
      wait_for_sync <= 1'b1;
      iaddr <= 0;
    end
    else if ((i_clk_enable)&&((!wait_for_sync)||(i_sync)))
    begin
      // Record what we're not ready to use yet
      iaddr <= iaddr + { {(LGSPAN){1'b0}}, 1'b1 };
      wait_for_sync <= 1'b0;
    end
  // Write to imem
  always @(posedge i_clk) // Need to make certain here that we don't read
    if ((i_clk_enable)&&(!iaddr[LGSPAN])) // and write the same address on
      imem[iaddr[(LGSPAN-1):0]] <= i_data; // the same clk
  // ib_sync
  // Now, we have all the inputs, so let's feed the butterfly
  // ib_sync is the synchronization bit to the butterfly.  It will
  // be tracked within the butterfly, and used to create the o_sync
  // value when the results from this output are produced
  always @(posedge i_clk)
    if (i_reset)
      ib_sync <= 1'b0;
    else if (i_clk_enable)
    begin
      // Set the sync to true on the very first
      // valid input in, and hence on the very
      // first valid data out per FFT.
      ib_sync <= (iaddr==(1<<(LGSPAN)));
    end
  // ib_a, ib_b, ib_c
  // Read the values from our input memory, and use them to feed
  // first of two butterfly inputs
  always	@(posedge i_clk)
    if (i_clk_enable)
    begin
      // One input from memory, ...
      ib_a <= imem[iaddr[(LGSPAN-1):0]];
      // One input clocked in from the top
      ib_b <= i_data;
      // and the coefficient  twiddle factor
      ib_c <= cmem[iaddr[(LGSPAN-1):0]];
    end


  // Instantiate the butterfly
  butterfly #(
              .IWIDTH(IWIDTH),
              .CWIDTH(CWIDTH),
              .OWIDTH(OWIDTH),
              .CKPCE(CKPCE),
              .SHIFT(BFLYSHIFT)
            ) bfly(
              .i_clk(i_clk), .i_reset(i_reset), .i_clk_enable(i_clk_enable),
              .i_coef( (!i_clk_enable) ? {(2*CWIDTH){1'b0}} :ib_c),
              .i_left( (!i_clk_enable) ? {(2*IWIDTH){1'b0}} :ib_a),
              .i_right((!i_clk_enable) ? {(2*IWIDTH){1'b0}} :ib_b),
              .i_aux(ib_sync && i_clk_enable),
              .o_left(ob_a), .o_right(ob_b), .o_aux(ob_sync)
            );

  // oaddr, o_sync, b_started
  // Next step: recover the outputs from the butterfly
  //
  // The first output can go immediately to the output of this routine
  // The second output must wait until this time in the idle cycle
  // oaddr is the output memory address, keeping track of where we are
  // in this output cycle.

  always @(posedge i_clk)
    if (i_reset)
    begin
      oaddr     <= 0;
      o_sync    <= 0;
      // b_started will be true once we've seen the first ob_sync
      b_started <= 0;
    end
    else if (i_clk_enable)
    begin
      o_sync <= (!oaddr[LGSPAN])?ob_sync : 1'b0;
      if (ob_sync||b_started)
        oaddr <= oaddr + 1'b1;
      if ((ob_sync)&&(!oaddr[LGSPAN]))
        // If b_started is true, then a butterfly output
        // is available
        b_started <= 1'b1;
    end

  // nxt_oaddr

  always @(posedge i_clk)
    if (i_clk_enable)
      nxt_oaddr[0] <= oaddr[0];

  generate if (LGSPAN>1)
    begin : WIDE_LGSPAN

      always @(posedge i_clk)
        if (i_clk_enable)
          nxt_oaddr[LGSPAN-1:1] <= oaddr[LGSPAN-1:1] + 1'b1;

    end
  endgenerate
  // omem
  // Only write to the memory on the first half of the outputs
  // We'll use the memory value on the second half of the outputs
  always @(posedge i_clk)
    if ((i_clk_enable)&&(!oaddr[LGSPAN]))
      omem[oaddr[(LGSPAN-1):0]] <= ob_b;


  // pre_ovalue
  always @(posedge i_clk)
    if (i_clk_enable)
      pre_ovalue <= omem[nxt_oaddr[(LGSPAN-1):0]];

  // o_data
  always @(posedge i_clk)
    if (i_clk_enable)
      o_data <= (!oaddr[LGSPAN]) ? ob_a : pre_ovalue;
endmodule
