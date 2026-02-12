
//
// Purpose:	This module bitreverses a pipelined FFT input.  Operation is
//		expected as follows:
//
//		i_clk	A running clock at whatever system speed is offered.
//		i_reset	A synchronous reset signal, that resets all internals
//		i_clk_enable	If this is one, one input is consumed and an output
//			is produced.
//		i_in_0, i_in_1
//			Two inputs to be consumed, each of width WIDTH.
//		o_out_0, o_out_1
//			Two of the bitreversed outputs, also of the same
//			width, WIDTH.  Of course, there is a delay from the
//			first input to the first output.  For this purpose,
//			o_sync is present.
//		o_sync	This will be a 1'b1 for the first value in any block.
//			Following a reset, this will only become 1'b1 once
//			the data has been loaded and is now valid.  After that,
//			all outputs will be valid.
//
// How do we do bit reversing at two smples per clock?  Can we separate out
// our work into eight memory banks, writing two banks at once and reading
// another two banks in the same clock?
//
//	mem[00xxx0] = s_0[n]
//	mem[00xxx1] = s_1[n]
//	o_0[n] = mem[10xxx0]
//	o_1[n] = mem[11xxx0]
//	...
//	mem[01xxx0] = s_0[m]
//	mem[01xxx1] = s_1[m]
//	o_0[m] = mem[10xxx1]
//	o_1[m] = mem[11xxx1]
//	...
//	mem[10xxx0] = s_0[n]
//	mem[10xxx1] = s_1[n]
//	o_0[n] = mem[00xxx0]
//	o_1[n] = mem[01xxx0]
//	...
//	mem[11xxx0] = s_0[m]
//	mem[11xxx1] = s_1[m]
//	o_0[m] = mem[00xxx1]
//	o_1[m] = mem[01xxx1]
//	...
//
//	The answer is that, yes we can but: we need to use four memory banks
//	to do it properly.  These four banks are defined by the two bits
//	that determine the top and bottom of the correct address.  Larger
//	FFT's would require more memories.

`default_nettype	none
module	bitreverse #(
		parameter			LGSIZE=5, WIDTH=24
	) (
		input	wire			i_clk, i_reset, i_clk_enable,
		input	wire	[(2*WIDTH-1):0]	i_in_0, i_in_1,
		output	wire	[(2*WIDTH-1):0]	o_out_0, o_out_1,
		output	reg			o_sync
	);

	// Local declarations
	reg			in_reset;
	reg	[(LGSIZE-1):0]	iaddr;
	wire	[(LGSIZE-3):0]	braddr;

	reg	[(2*WIDTH-1):0]	mem_e [0:((1<<(LGSIZE))-1)];
	reg	[(2*WIDTH-1):0]	mem_o [0:((1<<(LGSIZE))-1)];

	reg [(2*WIDTH-1):0] evn_out_0, evn_out_1, odd_out_0, odd_out_1;
	reg	adrz;

	// braddr
	genvar	k;
	generate for(k=0; k<LGSIZE-2; k=k+1)
	begin : gen_a_bit_reversed_value
		assign braddr[k] = iaddr[LGSIZE-3-k];
	end endgenerate

	// iaddr, in_reset, o_sync
	always @(posedge i_clk)
	if (i_reset)
	begin
		iaddr <= 0;
		in_reset <= 1'b1;
		o_sync <= 1'b0;
	end else if (i_clk_enable)
	begin
		iaddr <= iaddr + { {(LGSIZE-1){1'b0}}, 1'b1 };
		if (&iaddr[(LGSIZE-2):0])
			in_reset <= 1'b0;
		if (in_reset)
			o_sync <= 1'b0;
		else
			o_sync <= ~(|iaddr[(LGSIZE-2):0]);
	end

	// Write to memories mem_e and mem_o
	always @(posedge i_clk)
	if (i_clk_enable)
		mem_e[iaddr] <= i_in_0;

	always @(posedge i_clk)
	if (i_clk_enable)
		mem_o[iaddr] <= i_in_1;

	// Read from memories into: [evn|odd]_out_[0|1]
	always @(posedge i_clk)
	if (i_clk_enable)
		evn_out_0 <= mem_e[{!iaddr[LGSIZE-1],1'b0,braddr}];

	always @(posedge i_clk)
	if (i_clk_enable)
		evn_out_1 <= mem_e[{!iaddr[LGSIZE-1],1'b1,braddr}];

	always @(posedge i_clk)
	if (i_clk_enable)
		odd_out_0 <= mem_o[{!iaddr[LGSIZE-1],1'b0,braddr}];

	always @(posedge i_clk)
	if (i_clk_enable)
		odd_out_1 <= mem_o[{!iaddr[LGSIZE-1],1'b1,braddr}];

	// adrz
	always @(posedge i_clk)
	if (i_clk_enable)
		adrz <= iaddr[LGSIZE-2];

	assign	o_out_0 = (adrz)?odd_out_0:evn_out_0;
	assign	o_out_1 = (adrz)?odd_out_1:evn_out_1;

endmodule