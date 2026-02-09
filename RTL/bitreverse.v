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
//
//
//	20150602 -- This module has undergone massive rework in order to
//		ensure that it uses resources efficiently.  As a result,
//		it now optimizes nicely into block RAMs.  As an unfortunately
//		side effect, it now passes it's bench test (dblrev_tb) but
//		fails the integration bench test (fft_tb).

`default_nettype    none

// Purpose: Reorders FFT data from linear to bit-reversed order (or vice versa).
// It processes 2 samples per clock using a Double-Buffer (Ping-Pong) strategy.

module  bitreverse #(
        parameter       LGSIZE=5, // Log2 of FFT Size (e.g., 5 = 32 points)
        parameter       WIDTH=24  // Data Width
    ) (
        input   wire            i_clk, i_reset, i_clk_enable,
        // Two inputs per clock (Even and Odd samples)
        input   wire    [(2*WIDTH-1):0] i_in_0, i_in_1,
        
        // Two outputs per clock (Bit-Reversed)
        output  wire    [(2*WIDTH-1):0] o_out_0, o_out_1,
        
        // Sync pulse: Goes high when the first valid output block starts
        output  reg         o_sync
    );

    // ====================================================================
    // 1. INTERNAL SIGNALS
    // ====================================================================
    reg         in_reset;         // Tracks if we are filling the first buffer
    reg [(LGSIZE-1):0]  iaddr;    // Main Linear Counter (Write Address)
    wire    [(LGSIZE-3):0]  braddr; // Bit-Reversed Address (Read Address)

    // Memory Banks:
    // We treat the memory as one large block, but effectively split it into
    // "Ping" (Lower Half) and "Pong" (Upper Half) using the MSB of the address.
    // mem_e: Stores Even inputs (i_in_0)
    // mem_o: Stores Odd inputs (i_in_1)
    reg [(2*WIDTH-1):0] mem_e [0:((1<<(LGSIZE))-1)];
    reg [(2*WIDTH-1):0] mem_o [0:((1<<(LGSIZE))-1)];

    // Read Data Registers
    reg [(2*WIDTH-1):0] evn_out_0, evn_out_1, odd_out_0, odd_out_1;
    reg adrz; // Delayed address bit for muxing output

    // ====================================================================
    // 2. BIT REVERSAL LOGIC
    // ====================================================================
    // We calculate the read address ('braddr') by reversing the bits of 
    // the write address ('iaddr'). 
    // Note: We skip the top 2 bits (Bank Select) and only reverse the internal index.
    
    

    genvar  k;
    generate for(k=0; k<LGSIZE-2; k=k+1)
    begin : gen_a_bit_reversed_value
        // Example for 5-bit address:
        // braddr[0] = iaddr[2]
        // braddr[1] = iaddr[1]
        // braddr[2] = iaddr[0]
        assign braddr[k] = iaddr[LGSIZE-3-k];
    end endgenerate

    // ====================================================================
    // 3. WRITE COUNTER & SYNC
    // ====================================================================
    
    always @(posedge i_clk)
    if (i_reset)
    begin
        iaddr <= 0;
        in_reset <= 1'b1; // We start in "Reset/Fill" mode
        o_sync <= 1'b0;
    end else if (i_clk_enable)
    begin
        // Increment linear counter
        iaddr <= iaddr + 1'b1;
        
        // Check if we have filled the first buffer (Halfway point)
        // If LGSIZE=5, we check if iaddr[3:0] is full.
        if (&iaddr[(LGSIZE-2):0])
            in_reset <= 1'b0; // First fill complete, outputs are now valid.
            
        // Generate Sync Pulse
        // Pulse high only at the start of a new block (address 0)
        if (in_reset)
            o_sync <= 1'b0;
        else
            o_sync <= ~(|iaddr[(LGSIZE-2):0]);
    end

    // ====================================================================
    // 4. MEMORY WRITE (LINEAR)
    // ====================================================================
    // We write linearly to the current bank.
    // Bank is selected by iaddr[LGSIZE-1] implicitly.
    
    always @(posedge i_clk)
    if (i_clk_enable)
        mem_e[iaddr] <= i_in_0; // Store Input 0

    always @(posedge i_clk)
    if (i_clk_enable)
        mem_o[iaddr] <= i_in_1; // Store Input 1

    // ====================================================================
    // 5. MEMORY READ (BIT REVERSED)
    // ====================================================================
    // We read from the OPPOSITE bank that we are writing to.
    // Logic: !iaddr[LGSIZE-1] selects the "other" half of memory.
    
    // We need to fetch 4 values because the bit-reversal mapping might 
    // scatter the data between the Even and Odd memory banks.
    
    always @(posedge i_clk)
    if (i_clk_enable)
        evn_out_0 <= mem_e[{!iaddr[LGSIZE-1], 1'b0, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        evn_out_1 <= mem_e[{!iaddr[LGSIZE-1], 1'b1, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        odd_out_0 <= mem_o[{!iaddr[LGSIZE-1], 1'b0, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        odd_out_1 <= mem_o[{!iaddr[LGSIZE-1], 1'b1, braddr}];

    // ====================================================================
    // 6. OUTPUT MUX
    // ====================================================================
    // We retrieved candidates from both the Even and Odd memories.
    // Now we must select the correct one based on the bit-reversed logic.
    // 'adrz' tracks the LSB of the reversed address (which corresponds to 
    // the MSB of the linear address minus the bank bit).
    
    always @(posedge i_clk)
    if (i_clk_enable)
        adrz <= iaddr[LGSIZE-2]; // Delay by 1 clock to match memory latency

    // Select the final output
    assign  o_out_0 = (adrz) ? odd_out_0 : evn_out_0;
    assign  o_out_1 = (adrz) ? odd_out_1 : evn_out_1;

endmodule

