// -----------------------------------------------------------------------------
// Module: fftmain
// Description:
//   Top-level module for the 4096-point Radix-2 SDF FFT.
//   This block connects all FFT stages, manages synchronization,
//   and interfaces input/output streams.
//
// Parameters:
//   i_clk        - System clock. All logic is synchronous to this clock.
//   i_reset      - Synchronous reset (active high). Resets pipeline state.
//   i_clk_enable - Global clock enable. When low, pipeline stalls.
//   i_left       - Even-indexed complex input sample.
//   i_right      - Odd-indexed complex input sample.
//   o_left       - Even-indexed complex FFT output sample.
//   o_right      - Odd-indexed complex FFT output sample.
//   o_sync       - Frame synchronization pulse. High on first valid output.
//
// Data Format:
//   Inputs  : { Real[11:0], Imag[11:0] } → 24-bit complex
//   Outputs : { Real[18:0], Imag[18:0] } → 38-bit complex
// -----------------------------------------------------------------------------
`default_nettype none

module fftmain(
    // Clock and Reset
    i_clk,
    i_reset,
    i_clk_enable, // Global pipeline stall/enable

    // Data Inputs: Processing 2 samples per clock (Double Clock)
    // i_left  = Even sample
    // i_right = Odd sample
    i_left,
    i_right,

    // Data Outputs
    o_left,
    o_right,
    o_sync    // Synchronization pulse marking the start of a frame
  );

  // --- Configuration Parameters ---
  localparam  IWIDTH  = 12; // Input bit width per component (real/imag)
  localparam  LGWIDTH = 12; // log2(FFT size) → 2^12 = 4096
  localparam  OWIDTH  = 19; // Output bit width per component (after bit growth)

  // --- Ports ---
  input  wire                      i_clk;
  input  wire                      i_reset;
  input  wire                      i_clk_enable;

  input  wire [(2*IWIDTH-1):0]     i_left;
  input  wire [(2*IWIDTH-1):0]     i_right; // Complex input samples

  output reg  [(2*OWIDTH-1):0]     o_left;
  output reg  [(2*OWIDTH-1):0]     o_right; // Complex FFT outputs

  output reg                       o_sync;  // Output frame sync pulse

  // --- Internal Signals ---
  // Bit-reversal stage outputs (final reordering)
  wire                             br_sync;
  wire [(2*OWIDTH-1):0]            br_left;
  wire [(2*OWIDTH-1):0]            br_right;
  // --------------------------------------------------------------------------
  // Stage Output Width Growth Plan
  // --------------------------------------------------------------------------
  // Bit growth is controlled across FFT stages to:
  //   1) Prevent overflow
  //   2) Preserve numerical precision
  //   3) Minimize hardware cost
  //
  // Growth strategy:
  //   - Some stages allow +1 bit growth
  //   - Others maintain width (scaled / bounded)
  //
  localparam STAGE1_OWIDTH  = 13; // 12 → 13  (+1 growth)
  localparam STAGE2_OWIDTH  = 14; // 13 → 14  (+1 growth)
  localparam STAGE3_OWIDTH  = 14; // No growth
  localparam STAGE4_OWIDTH  = 15; // +1 growth
  localparam STAGE5_OWIDTH  = 15; // No growth
  localparam STAGE6_OWIDTH  = 16; // +1 growth
  localparam STAGE7_OWIDTH  = 16; // No growth
  localparam STAGE8_OWIDTH  = 17; // +1 growth
  localparam STAGE9_OWIDTH  = 17; // +1 growth
  localparam STAGE10_OWIDTH = 18; // +1 growth
  localparam STAGE11_OWIDTH = 18; // +1 growth
  localparam STAGE12_OWIDTH = 19; // Final output width

  // ==========================================================================
  // STAGE 1: 4096-point FFT Decomposition
  // ==========================================================================
  // In a Radix-2 DIF (Decimation in Frequency) SDF pipeline:
  //
  //   Stage 1 performs:
  //     - Butterfly operation
  //     - Twiddle multiplication
  //     - Delay feedback of half-frame
  //
  //   Decomposition:
  //     4096-point FFT → two 2048-point sub-problems
  //
  // Since input is double-rate (2 samples/clock):
  //     Required delay = 2048 samples / 2 = 1024 clocks
  //

  // --- Stage 1 Outputs ---
  wire              w_s4096;     // Sync output from even path
  wire              w_os4096;    // Sync output from odd path (unused)

  // Complex data:
  //   13-bit Real + 13-bit Imag = 26-bit complex
  wire  [(2*STAGE1_OWIDTH-1):0]      w_e4096;     // Even stream output
  wire  [(2*STAGE1_OWIDTH-1):0]      w_o4096;     // Odd stream output

  // --------------------------------------------------------------------------
  // Path 1 → Even (Left) Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(IWIDTH),           // Input width = 12 bits/component
             .CWIDTH(IWIDTH+4),         // Twiddle coefficient width = 16 bits
             .OWIDTH(STAGE1_OWIDTH),    // Output width = 13 bits/component

             .LGSPAN(10),               // Delay span = 2^10 = 1024 clocks
             // Explanation:
             //   Stage 1 delay = N/4 = 4096/4 = 1024 cycles (for 2 samples/clk)

             .BFLYSHIFT(0),             // No scaling shift
             .OPT_HWMPY(0),             // Use logic multipliers
             .CKPCE(1),                 // One clock per clock-enable
             .COEFFILE("cmem_e8192.hex")// Twiddle ROM file (even path)
           ) stage_e4096 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(!i_reset),         // Sync asserted after reset release
             .i_data(i_left),           // Even-indexed input samples

             .o_data(w_e4096),          // Output to Stage 2
             .o_sync(w_s4096)           // Sync forwarded downstream
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd (Right) Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(IWIDTH),
             .CWIDTH(IWIDTH+4),
             .OWIDTH(STAGE1_OWIDTH),

             .LGSPAN(10),               // Same delay span
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o8192.hex")// Twiddle ROM file (odd path)
           ) stage_o4096 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(!i_reset),
             .i_data(i_right),          // Odd-indexed input samples

             .o_data(w_o4096),
             .o_sync(w_os4096)
           );
  // ==========================================================================
  // STAGE 2: 2048-point FFT Decomposition
  // ==========================================================================
  // Receives 13-bit complex samples from Stage 1.
  //
  // Function:
  //   2048-point FFT → two 1024-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 1024 samples
  //   With 2 samples/clock → 1024 / 2 = 512 clocks → LGSPAN = 9
  //

  wire              w_s2048;     // Sync from even path
  wire              w_os2048;    // Sync from odd path (unused)

  // Complex width:
  //   14-bit Real + 14-bit Imag = 28-bit complex
  wire  [(2*STAGE2_OWIDTH-1):0]      w_e2048;     // Even stream
  wire  [(2*STAGE2_OWIDTH-1):0]      w_o2048;     // Odd stream
  // Note: Bit growth 13 → 14 bits

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE1_OWIDTH),        // Input width = 13 bits/component
             .CWIDTH(STAGE1_OWIDTH+4),      // Twiddle width = 17 bits
             .OWIDTH(STAGE2_OWIDTH),        // Output width = 14 bits/component

             .LGSPAN(9),                    // Delay span = 2^9 = 512 clocks
             // Explanation:
             //   Delay = 1024 samples / 2 samples/clk = 512 cycles

             .BFLYSHIFT(0),                 // No scaling
             .OPT_HWMPY(0),                 // Logic multipliers
             .CKPCE(1),                     // One clock per CE
             .COEFFILE("cmem_e4096.hex")    // Twiddle ROM
           ) stage_e2048 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s4096),              // Sync chained from Stage 1
             .i_data(w_e4096),              // Data chained from Stage 1

             .o_data(w_e2048),
             .o_sync(w_s2048)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE1_OWIDTH),
             .CWIDTH(STAGE1_OWIDTH+4),
             .OWIDTH(STAGE2_OWIDTH),

             .LGSPAN(9),                    // Same delay span
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o4096.hex")
           ) stage_o2048 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s4096),              // Sync aligned with even stream
             .i_data(w_o4096),

             .o_data(w_o2048),
             .o_sync(w_os2048)
           );

  // ==========================================================================
  // STAGE 3: 1024-point FFT Decomposition
  // ==========================================================================
  // Receives 14-bit complex samples from Stage 2.
  //
  // Function:
  //   1024-point FFT → two 512-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 512 samples
  //   With 2 samples/clock → 512 / 2 = 256 clocks → LGSPAN = 8
  //
  // No bit growth configured (14 → 14)
  //

  wire              w_s1024;     // Sync from even path
  wire              w_os1024;    // Sync from odd path (unused)

  // Complex width remains:
  //   14-bit Real + 14-bit Imag = 28-bit complex
  wire  [(2*STAGE3_OWIDTH-1):0]      w_e1024;
  wire  [(2*STAGE3_OWIDTH-1):0]      w_o1024;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE2_OWIDTH),        // Input width = 14 bits/component
             .CWIDTH(STAGE2_OWIDTH+4),      // Twiddle width = 18 bits
             .OWIDTH(STAGE3_OWIDTH),        // Output width = 14 bits/component

             .LGSPAN(8),                    // Delay span = 2^8 = 256 clocks
             // Explanation:
             //   Delay = 512 samples / 2 samples/clk = 256 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e2048.hex")
           ) stage_e1024 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s2048),              // Sync from Stage 2
             .i_data(w_e2048),

             .o_data(w_e1024),
             .o_sync(w_s1024)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE2_OWIDTH),
             .CWIDTH(STAGE2_OWIDTH+4),
             .OWIDTH(STAGE3_OWIDTH),

             .LGSPAN(8),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o2048.hex")
           ) stage_o1024 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s2048),
             .i_data(w_o2048),

             .o_data(w_o1024),
             .o_sync(w_os1024)
           );
  // ==========================================================================
  // STAGE 4: 512-point FFT Decomposition
  // ==========================================================================
  // Receives 14-bit complex samples from Stage 3.
  //
  // Function:
  //   512-point FFT → two 256-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 256 samples
  //   With 2 samples/clock → 256 / 2 = 128 clocks → LGSPAN = 7
  //
  // Bit growth resumes (14 → 15)
  //

  wire              w_s512;      // Sync from even path
  wire              w_os512;     // Sync from odd path (unused)

  // Complex width:
  //   15-bit Real + 15-bit Imag = 30-bit complex
  wire  [(2*STAGE4_OWIDTH-1):0]      w_e512;
  wire  [(2*STAGE4_OWIDTH-1):0]      w_o512;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE3_OWIDTH),        // Input width = 14 bits/component
             .CWIDTH(STAGE3_OWIDTH+4),      // Twiddle width = 18 bits
             .OWIDTH(STAGE4_OWIDTH),        // Output width = 15 bits/component

             .LGSPAN(7),                    // Delay span = 2^7 = 128 clocks
             // Explanation:
             //   Delay = 256 samples / 2 samples/clk = 128 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e1024.hex")
           ) stage_e512 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s1024),              // Sync from Stage 3
             .i_data(w_e1024),

             .o_data(w_e512),
             .o_sync(w_s512)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE3_OWIDTH),
             .CWIDTH(STAGE3_OWIDTH+4),
             .OWIDTH(STAGE4_OWIDTH),

             .LGSPAN(7),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o1024.hex")
           ) stage_o512 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s1024),
             .i_data(w_o1024),

             .o_data(w_o512),
             .o_sync(w_os512)
           );

  // ==========================================================================
  // STAGE 5: 256-point FFT Decomposition
  // ==========================================================================
  // Receives 15-bit complex samples from Stage 4.
  //
  // Function:
  //   256-point FFT → two 128-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 128 samples
  //   With 2 samples/clock → 128 / 2 = 64 clocks → LGSPAN = 6
  //
  // No bit growth (15 → 15)
  //

  wire              w_s256;      // Sync from even path
  wire              w_os256;     // Sync from odd path (unused)

  // Complex width unchanged:
  //   15-bit Real + 15-bit Imag = 30-bit complex
  wire  [(2*STAGE5_OWIDTH-1):0]      w_e256;
  wire  [(2*STAGE5_OWIDTH-1):0]      w_o256;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE4_OWIDTH),        // Input width = 15 bits/component
             .CWIDTH(STAGE4_OWIDTH+4),      // Twiddle width = 19 bits
             .OWIDTH(STAGE5_OWIDTH),        // Output width = 15 bits/component

             .LGSPAN(6),                    // Delay span = 2^6 = 64 clocks
             // Explanation:
             //   Delay = 128 samples / 2 samples/clk = 64 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e512.hex")
           ) stage_e256 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s512),               // Sync from Stage 4
             .i_data(w_e512),

             .o_data(w_e256),
             .o_sync(w_s256)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE4_OWIDTH),
             .CWIDTH(STAGE4_OWIDTH+4),
             .OWIDTH(STAGE5_OWIDTH),

             .LGSPAN(6),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o512.hex")
           ) stage_o256 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s512),
             .i_data(w_o512),

             .o_data(w_o256),
             .o_sync(w_os256)
           );
  // ==========================================================================
  // STAGE 6: 128-point FFT Decomposition
  // ==========================================================================
  // Receives 15-bit complex samples from Stage 5.
  //
  // Function:
  //   128-point FFT → two 64-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 64 samples
  //   With 2 samples/clock → 64 / 2 = 32 clocks → LGSPAN = 5
  //
  // Bit growth enabled (15 → 16)
  //

  wire              w_s128;      // Sync from even path
  wire              w_os128;     // Sync from odd path (unused)

  // Complex width:
  //   16-bit Real + 16-bit Imag = 32-bit complex
  wire  [(2*STAGE6_OWIDTH-1):0]      w_e128;
  wire  [(2*STAGE6_OWIDTH-1):0]      w_o128;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE5_OWIDTH),        // Input width = 15 bits/component
             .CWIDTH(STAGE5_OWIDTH+4),      // Twiddle width = 19 bits
             .OWIDTH(STAGE6_OWIDTH),        // Output width = 16 bits/component

             .LGSPAN(5),                    // Delay span = 2^5 = 32 clocks
             // Explanation:
             //   Delay = 64 samples / 2 samples/clk = 32 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e256.hex")
           ) stage_e128 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s256),               // Sync from Stage 5
             .i_data(w_e256),

             .o_data(w_e128),
             .o_sync(w_s128)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE5_OWIDTH),
             .CWIDTH(STAGE5_OWIDTH+4),
             .OWIDTH(STAGE6_OWIDTH),

             .LGSPAN(5),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o256.hex")
           ) stage_o128 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s256),
             .i_data(w_o256),

             .o_data(w_o128),
             .o_sync(w_os128)
           );


  // ==========================================================================
  // STAGE 7: 64-point FFT Decomposition
  // ==========================================================================
  // Receives 16-bit complex samples from Stage 6.
  //
  // Function:
  //   64-point FFT → two 32-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 32 samples
  //   With 2 samples/clock → 32 / 2 = 16 clocks → LGSPAN = 4
  //
  // No bit growth (16 → 16)
  //

  wire              w_s64;       // Sync from even path
  wire              w_os64;      // Sync from odd path (unused)

  // Complex width unchanged:
  wire  [(2*STAGE7_OWIDTH-1):0]      w_e64;
  wire  [(2*STAGE7_OWIDTH-1):0]      w_o64;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE6_OWIDTH),        // Input width = 16 bits/component
             .CWIDTH(STAGE6_OWIDTH+4),      // Twiddle width = 20 bits
             .OWIDTH(STAGE7_OWIDTH),        // Output width = 16 bits/component

             .LGSPAN(4),                    // Delay span = 2^4 = 16 clocks
             // Explanation:
             //   Delay = 32 samples / 2 samples/clk = 16 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e128.hex")
           ) stage_e64 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s128),               // Sync from Stage 6
             .i_data(w_e128),

             .o_data(w_e64),
             .o_sync(w_s64)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE6_OWIDTH),
             .CWIDTH(STAGE6_OWIDTH+4),
             .OWIDTH(STAGE7_OWIDTH),

             .LGSPAN(4),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o128.hex")
           ) stage_o64 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s128),
             .i_data(w_o128),

             .o_data(w_o64),
             .o_sync(w_os64)
           );
  // ==========================================================================
  // STAGE 8: 32-point FFT Decomposition
  // ==========================================================================
  // Receives 16-bit complex samples from Stage 7.
  //
  // Function:
  //   32-point FFT → two 16-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 16 samples
  //   With 2 samples/clock → 16 / 2 = 8 clocks → LGSPAN = 3
  //
  // Bit growth enabled (16 → 17)
  //

  wire              w_s32;       // Sync from even path
  wire              w_os32;      // Sync from odd path (unused)

  // Complex width:
  //   17-bit Real + 17-bit Imag = 34-bit complex
  wire  [(2*STAGE8_OWIDTH-1):0]      w_e32;
  wire  [(2*STAGE8_OWIDTH-1):0]      w_o32;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE7_OWIDTH),        // Input width = 16 bits/component
             .CWIDTH(STAGE7_OWIDTH+4),      // Twiddle width = 20 bits
             .OWIDTH(STAGE8_OWIDTH),        // Output width = 17 bits/component

             .LGSPAN(3),                    // Delay span = 2^3 = 8 clocks
             // Explanation:
             //   Delay = 16 samples / 2 samples/clk = 8 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e64.hex")
           ) stage_e32 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s64),                // Sync from Stage 7
             .i_data(w_e64),

             .o_data(w_e32),
             .o_sync(w_s32)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE7_OWIDTH),
             .CWIDTH(STAGE7_OWIDTH+4),
             .OWIDTH(STAGE8_OWIDTH),

             .LGSPAN(3),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o64.hex")
           ) stage_o32 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s64),
             .i_data(w_o64),

             .o_data(w_o32),
             .o_sync(w_os32)
           );


  // ==========================================================================
  // STAGE 9: 16-point FFT Decomposition
  // ==========================================================================
  // Receives 17-bit complex samples from Stage 8.
  //
  // Function:
  //   16-point FFT → two 8-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 8 samples
  //   With 2 samples/clock → 8 / 2 = 4 clocks → LGSPAN = 2
  //
  // No bit growth (17 → 17)
  //

  wire              w_s16;       // Sync from even path
  wire              w_os16;      // Sync from odd path (unused)

  wire  [(2*STAGE9_OWIDTH-1):0]      w_e16;
  wire  [(2*STAGE9_OWIDTH-1):0]      w_o16;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE8_OWIDTH),        // Input width = 17 bits/component
             .CWIDTH(STAGE8_OWIDTH+4),      // Twiddle width = 21 bits
             .OWIDTH(STAGE9_OWIDTH),        // Output width = 17 bits/component

             .LGSPAN(2),                    // Delay span = 2^2 = 4 clocks
             // Explanation:
             //   Delay = 8 samples / 2 samples/clk = 4 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e32.hex")
           ) stage_e16 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s32),                // Sync from Stage 8
             .i_data(w_e32),

             .o_data(w_e16),
             .o_sync(w_s16)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE8_OWIDTH),
             .CWIDTH(STAGE8_OWIDTH+4),
             .OWIDTH(STAGE9_OWIDTH),

             .LGSPAN(2),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o32.hex")
           ) stage_o16 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s32),
             .i_data(w_o32),

             .o_data(w_o16),
             .o_sync(w_os16)
           );
  // ==========================================================================
  // STAGE 10: 8-point FFT Decomposition
  // ==========================================================================
  // Receives 17-bit complex samples from Stage 9.
  //
  // Function:
  //   8-point FFT → two 4-point sub-problems
  //
  // Delay requirement:
  //   Stage delay = 4 samples
  //   With 2 samples/clock → 4 / 2 = 2 clocks → LGSPAN = 1
  //
  // Bit growth enabled (17 → 18)
  //

  wire              w_s8;        // Sync from even path
  wire              w_os8;       // Sync from odd path (unused)

  // Complex width:
  //   18-bit Real + 18-bit Imag = 36-bit complex
  wire  [(2*STAGE10_OWIDTH-1):0]      w_e8;
  wire  [(2*STAGE10_OWIDTH-1):0]      w_o8;

  // --------------------------------------------------------------------------
  // Path 1 → Even Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE9_OWIDTH),        // Input width = 17 bits/component
             .CWIDTH(STAGE9_OWIDTH+4),      // Twiddle width = 21 bits
             .OWIDTH(STAGE10_OWIDTH),       // Output width = 18 bits/component

             .LGSPAN(1),                    // Delay span = 2^1 = 2 clocks
             // Explanation:
             //   Delay = 4 samples / 2 samples/clk = 2 cycles

             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_e16.hex")
           ) stage_e8 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s16),                // Sync from Stage 9
             .i_data(w_e16),

             .o_data(w_e8),
             .o_sync(w_s8)
           );

  // --------------------------------------------------------------------------
  // Path 2 → Odd Stream
  // --------------------------------------------------------------------------
  fftstage #(
             .IWIDTH(STAGE9_OWIDTH),
             .CWIDTH(STAGE9_OWIDTH+4),
             .OWIDTH(STAGE10_OWIDTH),

             .LGSPAN(1),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_o16.hex")
           ) stage_o8 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s16),
             .i_data(w_o16),

             .o_data(w_o8),
             .o_sync(w_os8)
           );


  // ==========================================================================
  // STAGE 11: Quarter Rotator Stage (4-point Decomposition)
  // ==========================================================================
  // At this stage:
  //
  //   4-point FFT decomposition → trivial twiddle factors
  //
  // Twiddle factors are:
  //   ±1, ±j
  //
  // Instead of complex multipliers, this stage uses:
  //   ✔ Real/Imag swapping
  //   ✔ Sign inversion
  //
  // Benefits:
  //   - Eliminates multipliers
  //   - Reduces area and power
  //   - Shortens critical path
  //

  wire              w_s4;        // Sync from even path
  wire              w_os4;       // Sync from odd path (unused)

  wire  [(2*STAGE11_OWIDTH-1):0]      w_e4;        // 18-bit Real + 18-bit Imag
  wire  [(2*STAGE11_OWIDTH-1):0]      w_o4;

  // --------------------------------------------------------------------------
  // Even Stream Quarter Rotator
  // --------------------------------------------------------------------------
  qtrstage #(
             .IWIDTH(STAGE10_OWIDTH),   // Input width = 18 bits/component
             .OWIDTH(STAGE11_OWIDTH),   // Output width = 18 bits/component
             .LGWIDTH(12),              // FFT context = 4096-point FFT
             .ODD(0),                   // Even-path configuration
             .INVERSE(0),               // Forward FFT (0 = FFT, 1 = IFFT)
             .SHIFT(0)                  // No scaling shift
           ) stage_e4 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s8),             // Sync from Stage 10
             .i_data(w_e8),

             .o_data(w_e4),
             .o_sync(w_s4)
           );

  // --------------------------------------------------------------------------
  // Odd Stream Quarter Rotator
  // --------------------------------------------------------------------------
  qtrstage #(
             .IWIDTH(STAGE10_OWIDTH),
             .OWIDTH(STAGE11_OWIDTH),
             .LGWIDTH(12),
             .ODD(1),                   // Odd-path configuration
             .INVERSE(0),
             .SHIFT(0)
           ) stage_o4 (
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),

             .i_sync(w_s8),
             .i_data(w_o8),

             .o_data(w_o4),
             .o_sync(w_os4)
           );
  // ==========================================================================
  // STAGE 12: Final Butterfly (2-point Decomposition)
  // ==========================================================================
  // Final Radix-2 butterfly stage.
  //
  // Function:
  //   2-point FFT → simple add/subtract
  //
  // Twiddle factors:
  //   W0 = +1
  //   WN/2 = −1
  //
  // Implementation:
  //   ✔ No multipliers required
  //   ✔ Only adders/subtractors
  //
  // Bit growth:
  //   18 → 19 bits (final precision)
  //

  wire              w_s2;       // Final sync pulse
  wire  [(2*STAGE12_OWIDTH-1):0]      w_e2;       // 19-bit Real + 19-bit Imag
  wire  [(2*STAGE12_OWIDTH-1):0]      w_o2;

  laststage #(
              .IWIDTH(STAGE11_OWIDTH),  // Input width = 18 bits/component
              .OWIDTH(STAGE12_OWIDTH),  // Output width = 19 bits/component
              .SHIFT(1)                 // Final scaling / normalization shift
            ) stage_2 (
              .i_clk(i_clk),
              .i_reset(i_reset),
              .i_clk_enable(i_clk_enable),

              .i_sync(w_s4),            // Sync from Stage 11
              .i_left(w_e4),
              .i_right(w_o4),           // Even & odd paths merged

              .o_left(w_e2),
              .o_right(w_o2),
              .o_sync(w_s2)
            );


  // ==========================================================================
  // BIT REVERSAL: Output Reordering
  // ==========================================================================
  // Radix-2 DIF produces outputs in bit-reversed order.
  //
  // This block:
  //   ✔ Buffers full FFT frame
  //   ✔ Outputs natural order sequence
  //
  // Required for:
  //   - Downstream DSP blocks
  //   - OFDM / 5G mapping
  
  wire   br_start;
  reg    r_br_started;

  // Frame-valid guard:
  //   Ignore invalid pipeline data before first FFT completion
  always @(posedge i_clk)
    if (i_reset)
      r_br_started <= 1'b0;
    else if (i_clk_enable)
      r_br_started <= r_br_started || w_s2;

  assign br_start = r_br_started || w_s2;

  bitreverse #(
               .LGSIZE(12),   // 4096-point FFT
               .WIDTH(19)     // 19-bit components
             ) revstage (
               .i_clk(i_clk),
               .i_reset(i_reset),
               .i_clk_enable(i_clk_enable & br_start),

               .i_in_0(w_e2), // Even stream
               .i_in_1(w_o2), // Odd stream

               .o_out_0(br_left),
               .o_out_1(br_right),
               .o_sync(br_sync)
             );


  // ==========================================================================
  // FINAL OUTPUT REGISTRATION
  // ==========================================================================
  // Registers outputs for timing closure
  //

  always @(posedge i_clk)
    if (i_reset)
      o_sync <= 1'b0;
    else if (i_clk_enable)
      o_sync <= br_sync;

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      o_left  <= br_left;
      o_right <= br_right;
    end
endmodule
