`default_nettype none

// ============================================================================
// Module: bitreverse
// ============================================================================
// Purpose:
//   Reorders FFT outputs from Bit-Reversed Order → Natural Order.
//
// Context:
//   Radix-2 DIF FFT produces frequency bins in bit-reversed order.
//   This module buffers a full frame and reads it out correctly.
//
// Throughput:
//   • Two samples per clock (Double-stream)
//
// Key Idea:
//   Use memory buffering + bit-reversed addressing
// ============================================================================

module bitreverse #(
        // --------------------------------------------------------------------
        // Parameters
        // --------------------------------------------------------------------
        parameter LGSIZE = 5,   // log2(FFT size)
        parameter WIDTH  = 24   // Complex sample width
)(
        // --------------------------------------------------------------------
        // Ports
        // --------------------------------------------------------------------
        input  wire                     i_clk,
        input  wire                     i_reset,
        input  wire                     i_clk_enable,

        // Two complex samples per cycle
        input  wire [(2*WIDTH-1):0]     i_in_0,
        input  wire [(2*WIDTH-1):0]     i_in_1,

        // Reordered outputs
        output wire [(2*WIDTH-1):0]     o_out_0,
        output wire [(2*WIDTH-1):0]     o_out_1,

        // Frame synchronization
        output reg                      o_sync
);

    // ========================================================================
    // LOCAL DECLARATIONS
    // ========================================================================

    // in_reset:
    //   Internal reset extension flag.
    //   Remains high until memory is fully primed with valid FFT data.
    reg in_reset;

    // iaddr:
    //   Master address counter.
    //   Drives both:
    //      • Write addressing
    //      • Read addressing
    //
    // Width:
    //      LGSIZE bits → Covers full FFT frame
    reg [(LGSIZE-1):0] iaddr;

    // braddr:
    //   Bit-reversed address derived from iaddr.
    //
    // Size:
    //      LGSIZE-2 bits (top/bottom bits used elsewhere)
    wire [(LGSIZE-3):0] braddr;

    // ========================================================================
    // MEMORY BANKS
    // ========================================================================
    //
    // Two independent memory arrays:
    //
    //      mem_e → Even samples
    //      mem_o → Odd samples
    //
    // Depth:
    //      2^LGSIZE entries
    //
    // Why separate banks?
    //
    //      • Avoid dual-port conflicts
    //      • Support 2-sample-per-clock architecture
    //

    reg [(2*WIDTH-1):0] mem_e [0:((1<<LGSIZE)-1)];
    reg [(2*WIDTH-1):0] mem_o [0:((1<<LGSIZE)-1)];

    // ========================================================================
    // OUTPUT REGISTERS
    // ========================================================================
    //
    // Pipeline registers for memory read staging
    //

    reg [(2*WIDTH-1):0] evn_out_0, evn_out_1;
    reg [(2*WIDTH-1):0] odd_out_0, odd_out_1;

    // adrz:
    //   Phase tracking bit.
    //   Controls read/write alternation behavior.
    reg adrz;

    // ========================================================================
    // BIT-REVERSED ADDRESS GENERATION
    // ========================================================================
    //
    // braddr[k] = reverse(iaddr bits)
    //
    // Example:
    //
    //      iaddr = b4 b3 b2 b1 b0
    //      braddr = b2 b1 b0 (reversed subset)
    //
    // Purpose:
    //
    //      Map sequential FFT outputs → natural index positions
    //

    genvar k;
    generate
        for (k = 0; k < LGSIZE-2; k = k + 1)
        begin : gen_a_bit_reversed_value
            assign braddr[k] = iaddr[LGSIZE-3-k];
        end
    endgenerate

    // ========================================================================
    // ADDRESS COUNTER & RESET MANAGEMENT
    // ========================================================================
    //
    // Responsibilities:
    //
    //      • Increment address
    //      • Detect frame completion
    //      • Control sync generation
    //

    always @(posedge i_clk)
    if (i_reset)
    begin
        iaddr    <= 0;
        in_reset <= 1'b1;  // Hold until memory filled
        o_sync   <= 1'b0;
    end
    else if (i_clk_enable)
    begin
        // --------------------------------------------------------------------
        // Address Counter
        // --------------------------------------------------------------------
        //
        // Linear increment across FFT frame
        //
        iaddr <= iaddr + 1'b1;

        // --------------------------------------------------------------------
        // Reset Exit Condition
        // --------------------------------------------------------------------
        //
        // When address saturates → memory primed
        //
        if (&iaddr[(LGSIZE-2):0])
            in_reset <= 1'b0;

        // --------------------------------------------------------------------
        // Sync Generation
        // --------------------------------------------------------------------
        //
        // During reset phase → suppress sync
        //
        if (in_reset)
            o_sync <= 1'b0;
        else
            // Sync pulses at start of reordered frame
            o_sync <= ~(|iaddr[(LGSIZE-2):0]);
    end
    // ========================================================================
    // MEMORY WRITE LOGIC
    // ========================================================================
    //
    // The module accepts TWO complex samples per clock:
    //
    //      i_in_0 → Even stream
    //      i_in_1 → Odd stream
    //
    // These are written into SEPARATE memory banks:
    //
    //      mem_e → Stores even samples
    //      mem_o → Stores odd samples
    //
    // Why separate banks?
    //
    // 1. Avoid write contention (two writes per clock)
    // 2. Simplify dual-stream architecture
    // 3. Enable simultaneous read/write operations
    //

    always @(posedge i_clk)
    if (i_clk_enable)
        // Store EVEN input sample at linear address
        mem_e[iaddr] <= i_in_0;

    always @(posedge i_clk)
    if (i_clk_enable)
        // Store ODD input sample at linear address
        mem_o[iaddr] <= i_in_1;


    // ========================================================================
    // MEMORY READ LOGIC (BIT-REVERSED ACCESS)
    // ========================================================================
    //
    // Key Concept:
    //
    // FFT outputs arrive SEQUENTIALLY but represent BIT-REVERSED indices.
    //
    // We must read memory using:
    //
    //      BitReversed(iaddr)
    //
    // Address Composition:
    //
    //      { BankSelect, EvenOddSelect, braddr }
    //
    // Components Explained:
    //
    // ------------------------------------------------------------------------
    // 1. !iaddr[LGSIZE-1]
    // ------------------------------------------------------------------------
    //
    // Toggles memory half selection:
    //
    //      iaddr MSB = Write phase / Read phase indicator
    //
    // Inversion (!):
    //
    //      Enables reading from previously written half-frame
    //
    // Effect:
    //
    //      Implements "Ping-Pong Buffering"
    //
    // ------------------------------------------------------------------------
    // 2. 1'b0 / 1'b1
    // ------------------------------------------------------------------------
    //
    // Selects EVEN / ODD complex pair inside memory bank
    //
    // ------------------------------------------------------------------------
    // 3. braddr
    // ------------------------------------------------------------------------
    //
    // Bit-reversed version of address bits
    //
    // Ensures NATURAL ORDER output
    //

    always @(posedge i_clk)
    if (i_clk_enable)
        // EVEN Bank Read – Output 0
        evn_out_0 <= mem_e[{!iaddr[LGSIZE-1], 1'b0, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        // EVEN Bank Read – Output 1
        evn_out_1 <= mem_e[{!iaddr[LGSIZE-1], 1'b1, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        // ODD Bank Read – Output 0
        odd_out_0 <= mem_o[{!iaddr[LGSIZE-1], 1'b0, braddr}];

    always @(posedge i_clk)
    if (i_clk_enable)
        // ODD Bank Read – Output 1
        odd_out_1 <= mem_o[{!iaddr[LGSIZE-1], 1'b1, braddr}];


    // ========================================================================
    // OUTPUT PHASE CONTROL (adrz)
    // ========================================================================
    //
    // adrz:
    //
    //      Controls which memory bank drives outputs.
    //
    // Derived from:
    //
    //      iaddr[LGSIZE-2]
    //
    // Why this bit?
    //
    //      • Represents half-frame phase
    //      • Alternates EVEN/ODD ordering
    //
    // Function:
    //
    //      adrz = 0 → Output EVEN bank
    //      adrz = 1 → Output ODD bank
    //

    always @(posedge i_clk)
    if (i_clk_enable)
        adrz <= iaddr[LGSIZE-2];


    // ========================================================================
    // FINAL OUTPUT MUX (BANK COMMUTATOR)
    // ========================================================================
    //
    // This selects which bank appears at output:
    //
    //      EVEN phase → evn_out_*
    //      ODD phase  → odd_out_*
    //
    // Effect:
    //
    //      Maintains correct ordering for dual-stream FFT output
    //

    assign o_out_0 = (adrz) ? odd_out_0 : evn_out_0;
    assign o_out_1 = (adrz) ? odd_out_1 : evn_out_1;

endmodule
