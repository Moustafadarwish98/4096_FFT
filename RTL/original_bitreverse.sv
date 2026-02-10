
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

	genvar	k;
	generate for(k=0; k<LGSIZE-2; k=k+1)
	begin : gen_a_bit_reversed_value
		assign braddr[k] = iaddr[LGSIZE-3-k];
	end endgenerate

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
    begin
        mem_e[iaddr] <= i_in_0;
        mem_o[iaddr] <= i_in_1;
    end
	// Read from memories into: [evn|odd]_out_[0|1]
	always @(posedge i_clk)
	if (i_clk_enable)
    begin
		evn_out_0 <= mem_e[{!iaddr[LGSIZE-1],1'b0,braddr}];
        evn_out_1 <= mem_e[{!iaddr[LGSIZE-1],1'b1,braddr}];
        odd_out_0 <= mem_o[{!iaddr[LGSIZE-1],1'b0,braddr}];
        odd_out_1 <= mem_o[{!iaddr[LGSIZE-1],1'b1,braddr}];
        adrz <= iaddr[LGSIZE-2];
    end
		
	assign	o_out_0 = (adrz) ? odd_out_0:evn_out_0;
	assign	o_out_1 = (adrz) ? odd_out_1:evn_out_1;

endmodule
