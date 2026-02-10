
`default_nettype	none
module	butterfly #(
		parameter IWIDTH=16,
		CWIDTH=20,		
		OWIDTH=17,
		parameter	SHIFT=0,

		parameter	CKPCE=1,
		localparam MXMPYBITS =
		((IWIDTH+2)>(CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH + 2),
	
		localparam	MPYDELAY=((MXMPYBITS+1)/2)+2,

		localparam	LCLDELAY = (CKPCE == 1) ? MPYDELAY
			: (CKPCE == 2) ? (MPYDELAY/2+2)
			: (MPYDELAY/3 + 2),
		// LGDELAY
		localparam	LGDELAY = (MPYDELAY>64) ? 7
			: (MPYDELAY > 32) ? 6
			: (MPYDELAY > 16) ? 5
			: (MPYDELAY >  8) ? 4
			: (MPYDELAY >  4) ? 3
			: 2,
		localparam	AUXLEN=(LCLDELAY+3),
		localparam	MPYREMAINDER = MPYDELAY - CKPCE*(MPYDELAY/CKPCE)
	) (
		input	wire	i_clk, i_reset, i_clk_enable,
		input	wire	[(2*CWIDTH-1):0] i_coef,
		input	wire	[(2*IWIDTH-1):0] i_left, i_right,
		input	wire	i_aux,
		output	wire	[(2*OWIDTH-1):0] o_left, o_right,
		output	reg	o_aux
	);


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
	// }}}

	// Break complex registers into their real and imaginary components
	// {{{
	assign	r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
	assign	r_left_i  = r_left[ (IWIDTH-1):0];
	assign	r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
	assign	r_right_i = r_right[(IWIDTH-1):0];

	assign	ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
	assign	ir_coef_i = r_coef_2[(CWIDTH-1):0];
	// }}}

	assign	fifo_read_addr = fifo_addr - LCLDELAY[(LGDELAY-1):0];

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

	initial fifo_addr = 0;
	always @(posedge i_clk)
	if (i_reset)
		fifo_addr <= 0;
	else if (i_clk_enable)

		fifo_addr <= fifo_addr + 1;

	always @(posedge i_clk)
	if (i_clk_enable)
		fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };

	generate if (CKPCE <= 1)
	begin : CKPCE_ONE

		wire	[(CWIDTH):0]	p3c_in;
		wire	[(IWIDTH+1):0]	p3d_in;

		assign	p3c_in = ir_coef_i + ir_coef_r;
		assign	p3d_in = r_dif_r + r_dif_i;

		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p1(
			.i_clk(i_clk), .i_clk_enable(i_clk_enable),
			.i_a_unsorted({ir_coef_r[CWIDTH-1],ir_coef_r}),
			.i_b_unsorted({r_dif_r[IWIDTH],r_dif_r}),
			.o_r(p_one)

		);

		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p2(
			// {{{
			.i_clk(i_clk), .i_clk_enable(i_clk_enable),
			.i_a_unsorted({ir_coef_i[CWIDTH-1],ir_coef_i}),
			.i_b_unsorted({r_dif_i[IWIDTH],r_dif_i}),
			.o_r(p_two)
		);
		// }}}

		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p3(
	
			.i_clk(i_clk), .i_clk_enable(i_clk_enable),
			.i_a_unsorted(p3c_in),
			.i_b_unsorted(p3d_in),
			.o_r(p_three)
		);

	end endgenerate

	assign	fifo_r = { {2{fifo_read[2*(IWIDTH+1)-1]}},
		fifo_read[(2*(IWIDTH+1)-1):(IWIDTH+1)], {(CWIDTH-2){1'b0}} };
	assign	fifo_i = { {2{fifo_read[(IWIDTH+1)-1]}},
		fifo_read[((IWIDTH+1)-1):0], {(CWIDTH-2){1'b0}} };
	
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
	
	always @(posedge i_clk)
	if (i_clk_enable)
	begin
		// First clock, recover all values
		fifo_read <= fifo_left[fifo_read_addr];
		mpy_r <= p_one - p_two;
		mpy_i <= p_three - p_one - p_two;
	end
	
	always @(posedge i_clk)
	if (i_reset)
		aux_pipeline <= 0;
	else if (i_clk_enable)
		aux_pipeline <= { aux_pipeline[(AUXLEN-2):0], i_aux };

	always @(posedge i_clk)
	if (i_reset)
		o_aux <= 1'b0;
	else if (i_clk_enable)
	begin
		// Second clock, latch for final clock
		o_aux <= aux_pipeline[AUXLEN-1];
	end

	assign	o_left = { rnd_left_r, rnd_left_i };
	assign	o_right= { rnd_right_r,rnd_right_i};

endmodule
