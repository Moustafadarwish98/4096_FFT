// Operation:
//  Implements a Radix-2 Butterfly with Single-Path Delay Feedback (SDF).
//  It processes a stream of samples x[n].
//  1. The first N/2 samples are stored in a FIFO (Delay Line).
//  2. When the (N/2)-th sample arrives, the butterfly operation triggers:
//       Output 1: x[n] + x[n+N/2]
//       Output 2: (x[n] - x[n+N/2]) * TwiddleFactor
//  Ref: Paper Section IV.A describes this SDF structure[cite: 594].

`default_nettype    none

module  fftstage #(
    // --- Data Width Configuration ---
    parameter   IWIDTH=12,         // Input Bit Width 
    parameter   CWIDTH=20,         // Coefficient (Twiddle) Bit Width
                                   // Note: 5G typically needs 16-18 bits here for >50dB SQNR.
    parameter   OWIDTH=13,         // Output Bit Width (typically IWIDTH + 1 bit growth)

    // --- Architecture Configuration ---
    parameter   LGSPAN=10,         // Log2(Delay Length). 
                                   // Critical for Area Efficiency (Paper Sec IV.D).
                                   // LGSPAN=10 -> Delay = 1024 samples.
                                
    parameter   BFLYSHIFT=0,       // Static scaling shift (usually 0 to preserve precision)
    parameter   LGWIDTH=12,        // Log2(Total FFT Size) for context
    parameter [0:0] OPT_HWMPY = 1, // 1 = Use FPGA DSP Blocks, 0 = Use Logic Slices
    
    // --- Clocking Optimization ---
    // If input data rate < clock rate, we can share multipliers to save area.
    // For your 400MHz 5G target, you are likely running at full speed (CKPCE=1).
    parameter   CKPCE = 1,

    // --- Twiddle Factor Storage ---
    // Points to the pre-calculated Sine/Cosine table.
    // Optimization Target: Paper Sec IV.B suggests compressing this table 
    // to store only 0-pi/4 and using logic to reconstruct the rest[cite: 424, 685].
    parameter   COEFFILE="cmem_o8192.hex",
    /*2. The Technical Reason: "Double Clock" ResolutionThe architecture you are using is a Double Clock FFT 
    (processing 2 samples per clock cycle).In a standard (single-clock) Radix-2 FFT, the first stage (4096 points) splits data 
    into two groups and multiplies by Twiddle Factors $W_{4096}^k$.However, because this hardware processes two inputs at once 
    (Even and Odd streams in parallel), the internal indexing logic is more complex. The lookup table needs to support the 
    addressing scheme of two parallel butterflies.To avoid aliasing errors and ensure the hardware can grab the correct 
    Sine/Cosine values for both the "Left" and "Right" data streams simultaneously, the generator creates a table with 
    double the resolution.Therefore, for the 4096-point stage, it generates a table that has the resolution of 
    an 8192-point circle ($0$ to $2\pi$ divided into 8192 steps), even though you assume you only need 4096 steps.*/

    localparam [0:0]    ZERO_ON_IDLE = 1'b0
  ) (
    // --- System Ports ---
    input   wire                i_clk, i_reset,
    input   wire                i_clk_enable, // Global stall/enable for the pipeline
    input   wire                i_sync,       // Marks the start of a frame (x[0])

    // --- Data Ports ---
    // Complex Data: High bits = Real, Low bits = Imaginary
    input   wire    [(2*IWIDTH-1):0]    i_data,
    output  reg     [(2*OWIDTH-1):0]    o_data,
    output  reg                         o_sync
  );

  // ==========================================================================
  // Internal Signal Definitions
  // ==========================================================================
  // "ib_*" = Input to Butterfly (Data read from FIFO + Current Input)
  // "ob_*" = Output from Butterfly (Result of calculation)
  reg                       wait_for_sync; // Flag: Waiting for first valid frame
  reg   [(2*IWIDTH-1):0]    ib_a, ib_b;    // Butterfly Inputs (Complex)
  reg   [(2*CWIDTH-1):0]    ib_c;          // Twiddle Factor (Complex)
  reg                       ib_sync;       // Sync signal passed to butterfly

  reg                       b_started;     // Flag: Has butterfly processing started
  wire                      ob_sync;       // Sync signal out of butterfly
  wire  [(2*OWIDTH-1):0]    ob_a, ob_b;    // Butterfly Outputs (Sum and Diff)
  // ==========================================================================
  // TWIDDLE FACTOR ROM (cmem)
  // ==========================================================================
  // Corresponds to Paper Section IV.B "Twiddle Factor Table".
  // Storing full complex values here is the "standard" approach.
  // Optimization: The paper suggests storing only 0-pi/4 and using logic 
  // to generate the rest. If you implement that, this array becomes much smaller.
  reg   [(2*CWIDTH-1):0]    cmem [0:((1<<LGSPAN)-1)]; // The ROM Array

  // Initialize ROM from external HEX file
  initial
    $readmemh(COEFFILE, cmem);

  // ==========================================================================
  // DELAY LINE MEMORIES (FIFO)
  // ==========================================================================
  // Corresponds to Paper Section IV.D "Area-Efficient FIFO".
  //
  // 'imem': Input Memory. Stores the first N/2 samples (x[0]...x[N/2-1]).
  // 'omem': Output Memory. Temporarily stores butterfly results if needed 
  //         (though standard SDF often writes one output and stores the other).
  
  reg   [(LGSPAN):0]        iaddr;         // Master Counter (Controls Read/Write)
  reg   [(2*IWIDTH-1):0]    imem    [0:((1<<LGSPAN)-1)]; // FIFO RAM 1

  reg   [LGSPAN:0]          oaddr;
  reg   [(2*OWIDTH-1):0]    omem    [0:((1<<LGSPAN)-1)]; // FIFO RAM 2

  wire                      idle;
  reg   [(LGSPAN-1):0]      nxt_oaddr;
  reg   [(2*OWIDTH-1):0]    pre_ovalue;

  // ==========================================================================
  // CONTROL LOGIC: Synchronization & Addressing
  // ==========================================================================  
  always @(posedge i_clk)
    if (i_reset)
    begin
      wait_for_sync <= 1'b1;
      iaddr <= 0;
    end
    else if ((i_clk_enable) && ((!wait_for_sync) || (i_sync)))
    begin
      // Counter Logic:
      // iaddr counts from 0 to (2*DelayLength - 1).
      // Example for Stage 1 (LGSPAN=10): Counts 0 to 2047.
      //   0 to 1023:   Write Mode (Fill FIFO).
      //   1024 to 2047: Read Mode (Drain FIFO + Butterfly).    
      // Note: { {(LGSPAN){1'b0}}, 1'b1 } is just adding 1 to the counter.
      //iaddr <= iaddr + { {(LGSPAN){1'b0}}, 1'b1 };
      iaddr <= iaddr + 1'b1;
      // Once we see the first sync, we stop waiting.
      wait_for_sync <= 1'b0;
    end
  // ==========================================================================
  // FIFO WRITE LOGIC (The "Delay" Implementation)
  // ==========================================================================
  // This block implements the "Write" half of the Single-Path Delay Feedback.
  //
  // Condition: (!iaddr[LGSPAN])
  // This checks the MSB of the counter.
  // IF MSB is 0 (First half of the frame):
  //    We are receiving x[0], x[1]... x[N/2-1].
  //    We MUST store these in 'imem' because we can't process them 
  //    until we receive the corresponding x[N/2]... samples.
  always @(posedge i_clk)
    if ((i_clk_enable) && (!iaddr[LGSPAN])) 
      imem[iaddr[(LGSPAN-1):0]] <= i_data;
  

  // ==========================================================================
  // SYNC GENERATION (Starting the Butterfly)
  // ==========================================================================
  // In a Single-Path Delay Feedback (SDF) architecture, the butterfly cannot 
  // start until the first N/2 samples are stored in the FIFO.
  //
  // Example for Stage 1 (4096-point):
  //   LGSPAN = 10 (N/2 = 1024).
  //   The counter 'iaddr' counts 0...1023 (filling memory).
  //   At iaddr = 1024, the FIFO is full. The input 'i_data' is now x[1024].
  //   We can finally compute the first butterfly: Butterfly(x[0], x[1024]).
  always @(posedge i_clk)
    if (i_reset)
      ib_sync <= 1'b0;
    else if (i_clk_enable)
    begin
      // Trigger sync exactly when counter hits N/2 (1 << LGSPAN)
      ib_sync <= (iaddr == (1 << LGSPAN));
    end

  // ==========================================================================
  // BUTTERFLY INPUT FETCHING
  // ==========================================================================
  // Reads the three components needed for the calculation:
  //   1. ib_a: The "Old" sample x[n] (read from FIFO 'imem').
  //   2. ib_b: The "New" sample x[n + N/2] (current input 'i_data').
  //   3. ib_c: The Twiddle Factor W_N^k (read from ROM 'cmem').

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      // Optimization Note (Paper Sec IV.D):
      // If 'imem' is mapped to Block RAM, this read operation has a 1-cycle 
      // latency (read-during-write or distinct ports). Ensure timing analysis 
      // accounts for this register stage.
      ib_a <= imem[iaddr[(LGSPAN-1):0]];
      
      // Latch current input to align with memory read latency
      ib_b <= i_data;
      
      // Optimization Note (Paper Sec IV.B):
      // This line 'ib_c <= cmem[...]' is the bottleneck the paper aims to fix.
      // Currently, it reads a full-sized ROM.
      // To implement the paper's compression, you would replace this line 
      // with logic that reads a smaller table (0-pi/4) and swaps Real/Imag 
      // based on the quadrant of 'iaddr'.
      ib_c <= cmem[iaddr[(LGSPAN-1):0]];
    end

  // ==========================================================================
  // IDLE LOGIC (Candidate for Removal)
  // ==========================================================================
  assign idle = 1'b0; 


// ==========================================================================
  // 1. BUTTERFLY INSTANTIATION
  // ==========================================================================
  // This block performs the core radix-2 mathematical operation.
  //
  // Inputs:
  //   - i_left  (ib_a): The "Old" sample x[n] read from the Delay FIFO.
  //   - i_right (ib_b): The "New" sample x[n + N/2] coming from input.
  //   - i_coef  (ib_c): The Twiddle Factor W_N^k.
  //
  // Outputs:
  //   - o_left  (ob_a): The Sum (x[n] + x[n + N/2]). 
  //                     In SDF, this is sent out IMMEDIATELY.
  //   - o_right (ob_b): The Diff * Twiddle ((x[n] - x[n + N/2]) * W).
  //                     In SDF, this is STORED in 'omem' to be sent later.
  //
  // Optimization Note (Paper Section IV.C):
  // If you were implementing the "Quarter Rotator" logic inside the butterfly 
  // to avoid multipliers, you would modify the 'butterfly' or 'hwbfly' modules 
  // directly to detect trivial twiddles (1, -1, j, -j) and bypass the DSPs.

  generate if (OPT_HWMPY)
    begin : HWBFLY
      // ----------------------------------------------------------------------
      // Hardware Multiplier Version (DSP48 / DSP Slice)
      // ----------------------------------------------------------------------
      hwbfly #(
        .IWIDTH(IWIDTH),
        .CWIDTH(CWIDTH),
        .OWIDTH(OWIDTH),
        .CKPCE(CKPCE),     // Clocks per CE (1 for your high-speed 5G design)
        .SHIFT(BFLYSHIFT)  // Static scaling to prevent overflow
      ) bfly(
        .i_clk(i_clk), .i_reset(i_reset), .i_clk_enable(i_clk_enable),
        .i_coef(ib_c),     // The Twiddle Factor
        .i_left(ib_a),     // Input A (from FIFO)
        .i_right(ib_b),    // Input B (Current)
        .i_aux(ib_sync),   // Pass-through sync signal
        .o_left(ob_a),     // Result A (Sum)
        .o_right(ob_b),    // Result B (Diff)
        .o_aux(ob_sync)    // Sync signal valid when calculation finishes
      );
    end
    else
    begin : FWBFLY
      // ----------------------------------------------------------------------
      // Logic-Based Version (LUTs)
      // ----------------------------------------------------------------------
      // Implements multiplication using standard logic gates. 
      // Slower and larger area, but useful if you run out of DSPs.
      butterfly #(
        .IWIDTH(IWIDTH),
        .CWIDTH(CWIDTH),
        .OWIDTH(OWIDTH),
        .CKPCE(CKPCE),
        .SHIFT(BFLYSHIFT)
      ) bfly(
        .i_clk(i_clk), .i_reset(i_reset), .i_clk_enable(i_clk_enable),
        .i_coef(ib_c),
        .i_left(ib_a),
        .i_right(ib_b),
        .i_aux(ib_sync),
        .o_left(ob_a), .o_right(ob_b), .o_aux(ob_sync)
      );
    end
  endgenerate
  // ==========================================================================
  // 2. OUTPUT ADDRESSING & CONTROL (SDF Scheduling)
  // ==========================================================================
  // This logic controls the "Single-Path Delay Feedback" flow.
  // We need to manage the output stream based on 'oaddr'.
  //
  // The Cycle:
  //   0 to N/2-1: Output the 'Sum' (ob_a) immediately.
  //   N/2 to N-1: Output the 'Diff' (ob_b) that was stored in RAM.
  always @(posedge i_clk)
    if (i_reset)
    begin
      oaddr     <= 0;
      o_sync    <= 0;
      b_started <= 0;
    end
    else if (i_clk_enable)
    begin
      // ----------------------------------------------------------------------
      // A. Sync Generation
      // ----------------------------------------------------------------------
      // Passes the sync signal to the next stage.
      // Rule: Sync is only valid during the FIRST half of the frame (!oaddr[LGSPAN]),
      // because that marks the start of a new N-point sequence for the next stage.
      o_sync <= (!oaddr[LGSPAN]) ? ob_sync : 1'b0;

      // ----------------------------------------------------------------------
      // B. Output Address Counter
      // ----------------------------------------------------------------------
      // Counts 0 to N-1.
      // Increments only when we have valid data coming out of the butterfly (ob_sync)
      // OR if we are already in the middle of a frame (b_started).
      if (ob_sync || b_started)
        oaddr <= oaddr + 1'b1;

      // ----------------------------------------------------------------------
      // C. Start Flag
      // ----------------------------------------------------------------------
      // Latches high once the first valid butterfly output appears.
      // This keeps the 'oaddr' counter running even if 'ob_sync' pulses low.
      if ((ob_sync) && (!oaddr[LGSPAN]))
        b_started <= 1'b1;
    end
 // ==========================================================================
  // 3. MEMORY READ ADDRESS GENERATION (Latency Compensation)
  // ==========================================================================
  // We need to read from 'omem' to get the delayed 'ob_b' value.
  // Since Block RAMs have a 1-cycle read latency, we must calculate the 
  // read address (nxt_oaddr) one clock cycle ahead of time.

  // nxt_oaddr calculation
  always @(posedge i_clk)
    if (i_clk_enable)
      nxt_oaddr[0] <= oaddr[0]; // LSB follows current address

  generate if (LGSPAN > 1)
    begin : WIDE_LGSPAN
      always @(posedge i_clk)
        if (i_clk_enable)
          // Pre-calculate (oaddr + 1) for the upper bits
          nxt_oaddr[LGSPAN-1:1] <= oaddr[LGSPAN-1:1] + 1'b1;
    end
  endgenerate
//Should be replaced by this:
  // ==========================================================================
  // 3. MEMORY READ ADDRESS GENERATION (Latency Compensation)
  // ==========================================================================
  // We need to read from 'omem' to get the delayed 'ob_b' value.
  // Since Block RAMs have a 1-cycle read latency, we must calculate the 
  // read address (nxt_oaddr) one clock cycle ahead of time.
  // We use a simple linear increment to match the linear write order.
 /* always @(posedge i_clk)
    if (i_clk_enable)
      nxt_oaddr <= oaddr[(LGSPAN-1):0] + 1'b1;*/
   ////////////////////////////////////////////////////////////////// ////////////////////////////////////////////
//note: The above code is a simplified version of the address generation logic.
//In a real implementation, you would need to ensure that 'nxt_oaddr' correctly wraps around and matches the timing of when 'ob_b' is written to 'omem'.

  // ==========================================================================
  // 4. OUTPUT FIFO (omem) OPERATIONS
  // ==========================================================================
  // WRITE OPERATION
  // We write 'ob_b' (Diff) into memory during the FIRST half of the frame 
  // (!oaddr[LGSPAN]), so we can read it back during the second half.
  always @(posedge i_clk)
    if ((i_clk_enable) && (!oaddr[LGSPAN]))
      omem[oaddr[(LGSPAN-1):0]] <= ob_b;
  // READ OPERATION
  // We read from 'omem' using the pre-calculated 'nxt_oaddr'.
  // This 'pre_ovalue' will contain the data valid for the NEXT clock cycle.
  always @(posedge i_clk)
    if (i_clk_enable)
      pre_ovalue <= omem[nxt_oaddr[(LGSPAN-1):0]];
  // ==========================================================================
  // 5. FINAL OUTPUT MUX (The SDF Switch)
  // ==========================================================================
  // This selects the final output stream.
  //
  // Condition (!oaddr[LGSPAN]):
  //   TRUE (First Half): Output 'ob_a' (Immediate Sum).
  //   FALSE (Second Half): Output 'pre_ovalue' (Delayed Diff read from RAM).
  always @(posedge i_clk)
    if (i_clk_enable)
      o_data <= (!oaddr[LGSPAN]) ? ob_a : pre_ovalue;
endmodule