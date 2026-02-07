// Parameters:
//	i_clk	The clock.  All operations are synchronous with this clock.
//	i_reset	Synchronous reset, active high.  Setting this line will
//			force the reset of all of the internals to this routine.
//			Further, following a reset, the o_sync line will go
//			high the same time the first output sample is valid.
//	i_clk_enable	A clock enable line.  If this line is set, this module
//			will accept two complex values as inputs, and produce
//			two (possibly empty) complex values as outputs.
//	i_left	The first of two complex input samples.  This value is split
//			into two two's complement numbers, 12 bits each, with
//			the real portion in the high order bits, and the
//			imaginary portion taking the bottom 12 bits.
//	i_right	This is the same thing as i_left, only this is the second of
//			two such samples.  Hence, i_left would contain input
//			sample zero, i_right would contain sample one.  On the
//			next clock i_left would contain input sample two,
//			i_right number three and so forth.
//	o_left	The first of two output samples, of the same format as i_left,
//			only having 19 bits for each of the real and imaginary
//			components, leading to 38 bits total.
//	o_right	The second of two output samples produced each clock.  This has
//			the same format as o_left.
//	o_sync	A one bit output indicating the first valid sample produced by
//			this FFT following a reset.  Ever after, this will
//			indicate the first sample of an FFT frame.
`default_nettype    none

module fftmain(
    // Clock and Reset
    i_clk,
    i_reset,
    i_clk_enable, // Global pipeline stall/enable
    
    // Data Inputs: Processing 2 samples per clock (Double Clock)
    //              i_left = Even sample , i_right = Odd sample
    i_left,
    i_right,
    
    // Data Outputs
    o_left,
    o_right,
    o_sync    // Synchronization pulse marking the start of a frame
);

  // --- Configuration Parameters ---
  localparam  IWIDTH  = 12; // Input Bit Width (12 bits for real + 12 bits for imag = 24 bits total input)
  localparam  LGWIDTH = 12; // Log2(FFT Size) -> 2^12 = 4096 points
  localparam  OWIDTH  = 19; // Output Bit Width (Includes bit growth)
  
  // --- Ports ---
  input    wire                     i_clk, i_reset, i_clk_enable;
  input    wire [(2*IWIDTH-1):0]    i_left, i_right; // Complex inputs (Real + Imag)
  output   reg  [(2*OWIDTH-1):0]    o_left, o_right; // Complex outputs
  output   reg                      o_sync;

  // Internal wires for the final output (before bit reversal)
  wire              br_sync;
  wire  [(2*OWIDTH-1):0]    br_left, br_right;

  // ==========================================================================
  // STAGE 1: The 4096-point Decomposition
  // ==========================================================================
  // In a Radix-2 DIF (Decimation in Frequency) pipeline, the first stage 
  // separates the 4096-point problem into two 2048-point problems.
  // Note: Two parallel stages (stage_e4096, stage_o4096) handle the two data streams.

  wire              w_s4096;          // Sync signal out of Stage 1
  wire              w_os4096;         // (unused sync for the second path)
  wire  [25:0]      w_e4096, w_o4096; // Intermediate Data: 13 bits Real + 13 bits Imag = 26 bits
                                      // Note: Output width grew from 12 to 13 bits.

  // --- Path 1 (Left/Even Stream) ---
  fftstage  #(
             .IWIDTH(IWIDTH),         // Input: 12 bits
             .CWIDTH(IWIDTH+4),       // Coeff Width: 16 bits (12+4) for Twiddle Factors
             .OWIDTH(13),             // Output: 13 bits (1 bit growth)

             .LGSPAN(10),             // Delay Span: 2^10 = 1024 clocks.
                                      // Explanation: 4096 pt FFT requires 2048 sample delay.
                                      // Since we process 2 samples/clk, Delay = 2048/2 = 1024 clocks.

             .BFLYSHIFT(0),           // Scaling shift (0 = no scaling, preserves precision)
             .OPT_HWMPY(0),           // 1 = Use DSP blocks, 0 = Logic multipliers (for small bit widths, logic multipliers can be more efficient)
             .CKPCE(1),               // Clocks per clock enable (usually 1)
             .COEFFILE("cmem_e8192.hex") // Twiddle Factor ROM file
            ) stage_e4096(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(!i_reset),       // Sync starts high or toggles
             .i_data(i_left),         // Input: Left Stream
             .o_data(w_e4096),        // Output: To next stage
             .o_sync(w_s4096)         // Sync passed down the line
            );

  // --- Path 2 (Right/Odd Stream) ---
  fftstage  #(
             .IWIDTH(IWIDTH),
             .CWIDTH(IWIDTH+4),
             .OWIDTH(13),
             .LGSPAN(10),             // Same delay span
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o8192.hex")
            ) stage_o4096(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(!i_reset),
             .i_data(i_right),        // Input: Right Stream
             .o_data(w_o4096),
             .o_sync(w_os4096)
            );


  // ==========================================================================
  // STAGE 2: The 2048-point Decomposition
  // ==========================================================================
  // Receives data from Stage 1 and breaks it down further.
  
  wire              w_s2048;
  wire              w_os2048;
  wire  [27:0]      w_e2048, w_o2048; // Data: 14 bits Real + 14 bits Imag = 28 bits
                                      // Note: Bit growth 13 -> 14 bits.

  // --- Path 1 ---
  fftstage  #(
             .IWIDTH(13),             // Input width matches previous OWIDTH
             .CWIDTH(17),             // Twiddle width often grows or stays fixed
             .OWIDTH(14),             // Output width grows
             .LGSPAN(9),              // Delay Span: 2^9 = 512 clocks.
                                      // 2048 samples / 2 samples/clk / 2 (DIF stage) = 512.
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e4096.hex") // Next stage coefficients
            ) stage_e2048(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s4096),        // Chained Sync from previous stage
             .i_data(w_e4096),        // Chained Data from previous stage
             .o_data(w_e2048),
             .o_sync(w_s2048)
            );

  // --- Path 2 ---
  fftstage  #(
             .IWIDTH(13),
             .CWIDTH(17),
             .OWIDTH(14),
             .LGSPAN(9),              // Delay Span 512
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o4096.hex")
            )    stage_o2048(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s4096),        // Sync must match the "left" path sync
             .i_data(w_o4096),
             .o_data(w_o2048),
             .o_sync(w_os2048)
            );

// ==========================================================================
  // STAGE 3: The 1024-point Decomposition
  // ==========================================================================
  // Input: Data from the 2048-point stage.
  // Delay Line: 2^8 = 256 clock cycles.
  
  wire              w_s1024;
  wire              w_os1024;
  wire  [27:0]      w_e1024, w_o1024; // 14-bit Real + 14-bit Imag = 28 bits
                                      // Note: Previous stage output was 28 bits.
                                      // NO BIT GROWTH configured here (14 -> 14).

  // --- Path 1 (Even) ---
  fftstage  #(
             .IWIDTH(14),             // Input width matches previous OWIDTH
             .CWIDTH(18),             // Coefficient width (Twiddle precision)
             .OWIDTH(14),             // Output width held constant (truncation/rounding applied internally)
             .LGSPAN(8),              // Delay: 2^8 = 256 clocks.
                                    
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e2048.hex") // Coefficients for this stage
            ) stage_e1024(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s2048),
             .i_data(w_e2048),
             .o_data(w_e1024),
             .o_sync(w_s1024)
            );

  // --- Path 2 (Odd) ---
  fftstage  #(
             .IWIDTH(14),
             .CWIDTH(18),
             .OWIDTH(14),
             .LGSPAN(8),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o2048.hex")
            )    stage_o1024(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s2048),
             .i_data(w_o2048),
             .o_data(w_o1024),
             .o_sync(w_os1024)
            );


  // ==========================================================================
  // STAGE 4: The 512-point Decomposition
  // ==========================================================================
  // Delay Line: 2^7 = 128 clock cycles.
  
  wire              w_s512;
  wire              w_os512;
  wire  [29:0]      w_e512, w_o512;   // 15-bit Real + 15-bit Imag = 30 bits
                                      // Note: BIT GROWTH RESUMES (14 -> 15).

  fftstage  #(
             .IWIDTH(14),
             .CWIDTH(18),
             .OWIDTH(15),             // Growing to 15 bits to preserve precision
             .LGSPAN(7),              // Delay: 128 clocks.
                                      // 128 is small enough for LUTRAM (Distributed RAM) on many FPGAs.
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e1024.hex")
            ) stage_e512(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s1024),
             .i_data(w_e1024),
             .o_data(w_e512),
             .o_sync(w_s512)
            );

  fftstage  #(
             .IWIDTH(14),
             .CWIDTH(18),
             .OWIDTH(15),
             .LGSPAN(7),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o1024.hex")
            )    stage_o512(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s1024),
             .i_data(w_o1024),
             .o_data(w_o512),
             .o_sync(w_os512)
            );


  // ==========================================================================
  // STAGE 5: The 256-point Decomposition
  // ==========================================================================
  // Delay Line: 2^6 = 64 clock cycles.
  
  wire              w_s256;
  wire              w_os256;
  wire  [29:0]      w_e256, w_o256;   // 15-bit Real + 15-bit Imag = 30 bits
                                      // Note: NO BIT GROWTH (15 -> 15).

  fftstage  #(
             .IWIDTH(15),
             .CWIDTH(19),             // Coefficients getting slightly more precise
             .OWIDTH(15),             // Output width constant
             .LGSPAN(6),              // Delay: 64 clocks.
                                     
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e512.hex")
            ) stage_e256(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s512),
             .i_data(w_e512),
             .o_data(w_e256),
             .o_sync(w_s256)
            );

  fftstage  #(
             .IWIDTH(15),
             .CWIDTH(19),
             .OWIDTH(15),
             .LGSPAN(6),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o512.hex")
            )    stage_o256(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s512),
             .i_data(w_o512),
             .o_data(w_o256),
             .o_sync(w_os256)
            );

  // ==========================================================================
  // STAGE 6: The 128-point Decomposition
  // ==========================================================================
  // Delay Line: 2^5 = 32 clock cycles.
  // Bit Growth: 15 -> 16 bits.

  wire              w_s128;
  wire              w_os128;
  wire  [31:0]      w_e128, w_o128; // 16-bit Real + 16-bit Imag = 32 bits

  fftstage  #(
             .IWIDTH(15),
             .CWIDTH(19),
             .OWIDTH(16),             // Growth: YES
             .LGSPAN(5),              // Delay: 32 clocks. 
                                      
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e256.hex") 
            ) stage_e128(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s256),
             .i_data(w_e256),
             .o_data(w_e128),
             .o_sync(w_s128)
            );

  fftstage  #(
             .IWIDTH(15),
             .CWIDTH(19),
             .OWIDTH(16),
             .LGSPAN(5),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o256.hex")
            )    stage_o128(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s256),
             .i_data(w_o256),
             .o_data(w_o128),
             .o_sync(w_os128)
            );


  // ==========================================================================
  // STAGE 7: The 64-point Decomposition
  // ==========================================================================
  // Delay Line: 2^4 = 16 clock cycles.
  // Bit Growth: 16 -> 16 bits (None).

  wire              w_s64;
  wire              w_os64;
  wire  [31:0]      w_e64, w_o64;

  fftstage  #(
             .IWIDTH(16),
             .CWIDTH(20),             // Coefficient precision increased
             .OWIDTH(16),             // Growth: NO 
             .LGSPAN(4),              // Delay: 16 clocks.
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e128.hex")
            ) stage_e64(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s128),
             .i_data(w_e128),
             .o_data(w_e64),
             .o_sync(w_s64)
            );
  fftstage  #(
             .IWIDTH(16),
             .CWIDTH(20),
             .OWIDTH(16),
             .LGSPAN(4),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o128.hex")
            )    stage_o64(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s128),
             .i_data(w_o128),
             .o_data(w_o64),
             .o_sync(w_os64)
            );
  // ==========================================================================
  // STAGE 8: The 32-point Decomposition
  // ==========================================================================
  // Delay Line: 2^3 = 8 clock cycles.
  // Bit Growth: 16 -> 17 bits.

  wire              w_s32;
  wire              w_os32;
  wire  [33:0]      w_e32, w_o32;     // 17-bit Real + 17-bit Imag = 34 bits

  fftstage  #(
             .IWIDTH(16),
             .CWIDTH(20),
             .OWIDTH(17),             // Growth: YES
             .LGSPAN(3),              // Delay: 8 clocks.
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e64.hex")
            ) stage_e32(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s64),
             .i_data(w_e64),
             .o_data(w_e32),
             .o_sync(w_s32)
            );

  fftstage  #(
             .IWIDTH(16),
             .CWIDTH(20),
             .OWIDTH(17),
             .LGSPAN(3),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o64.hex")
            )    stage_o32(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s64),
             .i_data(w_o64),
             .o_data(w_o32),
             .o_sync(w_os32)
            );


  // ==========================================================================
  // STAGE 9: The 16-point Decomposition
  // ==========================================================================
  // Delay Line: 2^2 = 4 clock cycles.
  // Bit Growth: 17 -> 17 bits (None).

  wire              w_s16;
  wire              w_os16;
  wire  [33:0]      w_e16, w_o16;

  fftstage  #(
             .IWIDTH(17),
             .CWIDTH(21),
             .OWIDTH(17),             // Growth: NO
             .LGSPAN(2),              // Delay: 4 
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e32.hex")
            ) stage_e16(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s32),
             .i_data(w_e32),
             .o_data(w_e16),
             .o_sync(w_s16)
            );
  
    fftstage  #(
                 .IWIDTH(17),
                 .CWIDTH(21),
                 .OWIDTH(17),
                 .LGSPAN(2),
                 .BFLYSHIFT(0),
                 .OPT_HWMPY(0),
                 .CKPCE(1),
                 .COEFFILE("cmem_o32.hex")
                )    stage_o16(
                 .i_clk(i_clk),
                 .i_reset(i_reset),
                 .i_clk_enable(i_clk_enable),
                 .i_sync(w_s32),
                 .i_data(w_o32),
                 .o_data(w_o16),
                 .o_sync(w_os16)
                );

  // ==========================================================================
  // STAGE 10: The 8-point Decomposition
  // ==========================================================================
  // Delay Line: 2^1 = 2 clock cycles.
  // Bit Growth: 17 -> 18 bits.

  wire              w_s8;
  wire              w_os8;
  wire  [35:0]      w_e8, w_o8;       // 18-bit Real + 18-bit Imag = 36 bits

  fftstage  #(
             .IWIDTH(17),
             .CWIDTH(21),
             .OWIDTH(18),             // Growth: YES. Reaching high precision.
             .LGSPAN(1),              // Delay: 2 clocks.
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e16.hex")
            ) stage_e8(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s16),
             .i_data(w_e16),
             .o_data(w_e8),
             .o_sync(w_s8)
            );
    fftstage  #(
                 .IWIDTH(17),
                 .CWIDTH(21),
                 .OWIDTH(18),
                 .LGSPAN(1),
                 .BFLYSHIFT(0),
                 .OPT_HWMPY(0),
                 .CKPCE(1),
                 .COEFFILE("cmem_o16.hex")
                )    stage_o8(
                 .i_clk(i_clk),
                 .i_reset(i_reset),
                 .i_clk_enable(i_clk_enable),
                 .i_sync(w_s16),
                 .i_data(w_o16),
                 .o_data(w_o8),
                 .o_sync(w_os8)
                );
  // ==========================================================================
  // STAGE 11: The "Quarter Rotator" Stage (4-point decomposition)
  // =========================================================================
  // At this stage (going from 8 points to 4 points), the twiddle factors 
  // are all multiples of j (90 degrees). 
  // A standard multiplier is wasteful here. This module  uses 
  // simple real/imaginary swapping and sign inversion logic.
  wire              w_s4;
  wire              w_os4;
  wire  [35:0]      w_e4, w_o4; // 18-bit Real + 18-bit Imag = 36 bits

  qtrstage  #(
             .IWIDTH(18),
             .OWIDTH(18),             // No bit growth (18 -> 18)
             .LGWIDTH(12),            // Context: Part of a 4096-point FFT
             .ODD(0),                 // Even path configuration
             .INVERSE(0),             // Forward FFT (set to 1 for IFFT)
             .SHIFT(0)
            ) stage_e4(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s8),
             .i_data(w_e8),
             .o_data(w_e4),
             .o_sync(w_s4)
            );
  qtrstage  #(
             .IWIDTH(18),
             .OWIDTH(18),
             .LGWIDTH(12),
             .ODD(1),                 // Odd path configuration
             .INVERSE(0),
             .SHIFT(0)
            ) stage_o4(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s8),
             .i_data(w_o8),
             .o_data(w_o4),
             .o_sync(w_os4)
            );
  // ==========================================================================
  // STAGE 12: The Last Butterfly (2-point decomposition)
  // ==========================================================================
  // This is the final operation. It takes 4-point data and produces 
  // the final 2-point butterfly outputs.
  // The coefficients here are always 1 and -1 (W_0 and W_N/2).
  // No multipliers are needed, just adders/subtractors.
  wire              w_s2;
  wire  [37:0]      w_e2, w_o2;       // 19-bit Real + 19-bit Imag = 38 bits
                                      // Final Bit Growth: 18 -> 19 bits.
  laststage #(
              .IWIDTH(18),
              .OWIDTH(19),            // Final output precision
              .SHIFT(1)               //  a final scaling or bit shift
             ) stage_2(
              .i_clk(i_clk),
              .i_reset(i_reset),
              .i_clk_enable(i_clk_enable),
              .i_sync(w_s4),
              .i_left(w_e4), .i_right(w_o4), // Merges the two paths back
              .o_left(w_e2), .o_right(w_o2),
              .o_sync(w_s2)
             );
  // ==========================================================================
  // BIT REVERSAL: Reordering the Output
  // ==========================================================================
  // The Decimation-in-Frequency (DIF) algorithm produces outputs in 
  // "Bit-Reversed Order" (e.g., bin 1 comes out at index 2048).
  // This module buffers the entire frame and reads it out in natural order 
  // (0, 1, 2, 3...) required for 5G resource mapping.

  wire   br_start;
  reg    r_br_started;

  // Simple state machine to ignore invalid data before the first valid frame
  initial r_br_started = 1'b0;
  always @(posedge i_clk)
    if (i_reset)
      r_br_started <= 1'b0;
    else if (i_clk_enable)
      r_br_started <= r_br_started || w_s2;

  assign    br_start = r_br_started || w_s2;

  bitreverse    #(
                 .LGSIZE(12),         // 4096 points
                 .WIDTH(19)           // 19-bit data width
                ) revstage (
                 .i_clk(i_clk),
                 .i_reset(i_reset),
                 .i_clk_enable(i_clk_enable & br_start),
                 .i_in_0(w_e2),       // Even sample input
                 .i_in_1(w_o2),       // Odd sample input
                 .o_out_0(br_left),   // Even sample output (Ordered)
                 .o_out_1(br_right),  // Odd sample output (Ordered)
                 .o_sync(br_sync)     // Frame sync for downstream IP
                );

  // ==========================================================================
  // FINAL OUTPUT REGISTRATION
  // ==========================================================================
  // Registers the outputs for timing closure before leaving the module.
  initial
    o_sync  = 1'b0;
  always @(posedge i_clk)
    if (i_reset)
      o_sync  <= 1'b0;
    else if (i_clk_enable)
      o_sync  <= br_sync;

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      o_left  <= br_left;
      o_right <= br_right;
    end
endmodule