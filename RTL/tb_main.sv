/*`timescale 1ns/1ps
`default_nettype none

module tb_fftmain;

   // ====================================================================
   // 1. CONFIGURATION
   // ====================================================================
   localparam IWIDTH = 12;      // Input Width
   localparam OWIDTH = 19;      // Output Width
   localparam LGSIZE = 12;      // Log2(Size)
   localparam N      = 1<<LGSIZE; // 4096 points

   // ====================================================================
   // 2. SIGNALS
   // ====================================================================
   reg i_clk = 0;
   reg i_reset;
   reg i_clk_enable;

   // DUT Inputs
   reg  signed [(2*IWIDTH-1):0] i_left, i_right;
   
   // DUT Outputs
   wire signed [(2*OWIDTH-1):0] o_left, o_right;
   wire                         o_sync;

   // Unpacked Outputs for easier reading in Waveforms/Print
   wire signed [OWIDTH-1:0] o_left_r  = o_left[2*OWIDTH-1:OWIDTH];
   wire signed [OWIDTH-1:0] o_left_i  = o_left[OWIDTH-1:0];
   wire signed [OWIDTH-1:0] o_right_r = o_right[2*OWIDTH-1:OWIDTH];
   wire signed [OWIDTH-1:0] o_right_i = o_right[OWIDTH-1:0];

   // Helper Variables
   integer k;
   integer bin_counter;
   real    freq_bin = 7.0; // We will generate a tone at Bin 7

   // ====================================================================
   // 3. CLOCK GENERATION
   // ====================================================================
   always #5 i_clk = ~i_clk; // 100 MHz Clock (10ns period)

   // ====================================================================
   // 4. DUT INSTANTIATION
   // ====================================================================
   fftmain dut (
      .i_clk(i_clk),
      .i_reset(i_reset),
      .i_clk_enable(i_clk_enable),
      .i_left(i_left),
      .i_right(i_right),
      .o_left(o_left),
      .o_right(o_right),
      .o_sync(o_sync)
   );

   // ====================================================================
   // 5. STIMULUS (The Main Test)
   // ====================================================================
   initial begin
      // --- Setup Waveform Dumping (for GTKWave) ---
      $dumpfile("fft_dump.vcd");
      $dumpvars(0, tb_fftmain);

      // --- Initialization ---
      $display("Simulation Started.");
      i_reset      = 1;
      i_clk_enable = 0;
      i_left       = 0;
      i_right      = 0;

      // Hold reset for a few cycles
      repeat (20) @(posedge i_clk);

      // Release Reset
      @(posedge i_clk);
      i_reset      = 0;
      i_clk_enable = 1;

      // ----------------------------------------------------------------
      // FRAME 1: THE FLUSH (Write Zeros)
      // ----------------------------------------------------------------
      // We write 2048 clock cycles (4096 samples) of zeros.
      // This fills 'Bank A' of the ping-pong buffer with clean silence.
      // The output during this time will be garbage (reading uninitialized Bank B).
      $display("[T=%0t] Driving Frame 1 (Flush - Zeros)...", $time);
      
      for (k = 0; k < N/2; k = k + 1) begin
         i_left  <= 0;
         i_right <= 0;
         @(posedge i_clk);
      end

      // ----------------------------------------------------------------
      // FRAME 2: THE SIGNAL (Cosine Wave)
      // ----------------------------------------------------------------
      // We write 2048 clock cycles of a Cosine wave at Bin 7.
      // This fills 'Bank B'.
      // The output during this time will be the Zeros we wrote in Frame 1.
      $display("[T=%0t] Driving Frame 2 (Cosine Wave @ Bin 7)...", $time);

      for (k = 0; k < N/2; k = k + 1) begin
         // Generate input samples (Real only, Imag = 0)
         i_left  <= { cos_val(2*k),   12'sd0 };
         i_right <= { cos_val(2*k+1), 12'sd0 };
         @(posedge i_clk);
      end

      // ----------------------------------------------------------------
      // FRAME 3: THE READOUT (Silence)
      // ----------------------------------------------------------------
      // We write Zeros again to 'Bank A'.
      // The output during this time will be the Cosine Wave we wrote in Frame 2.
      $display("[T=%0t] Driving Frame 3 (Wait for Output)...", $time);

      i_left  <= 0;
      i_right <= 0;

      // Wait enough time for the full frame to emerge
      repeat (N/2 + 200) @(posedge i_clk);

      $display("[T=%0t] Simulation Finished.", $time);
      $finish;
   end


   // ====================================================================
   // 6. OUTPUT MONITOR
   // ====================================================================
   // This block watches the output. When 'o_sync' goes high, it knows
   // a new frame is starting (Bin 0).
   
   always @(posedge i_clk) begin
      if (i_reset) begin
         bin_counter <= -1;
      end else if (i_clk_enable) begin
         
         // Sync marks the start of a frame (Bin 0)
         if (o_sync) begin
            bin_counter <= 0;
            $display("\n--- FRAME START DETECTED ---");
         end 
         // If we are tracking a frame...
         else if (bin_counter >= 0 && bin_counter < N) begin
            bin_counter <= bin_counter + 2; // 2 samples per clock
         end

         // PRINT INTERESTING BINS
         // We expect energy at Bin 7 (and Bin 4089 due to symmetry).
         // We verify Bin 7 specifically.
         if (bin_counter == 6) begin // Next clock will be Bin 6 & 7 (wait, output logic delay...)
            // Just print the first 16 bins to be sure
         end
         
         if (bin_counter >= 0 && bin_counter < 16) begin
            $display("Bin %4d: %d + j%d", bin_counter,   o_left_r,  o_left_i);
            $display("Bin %4d: %d + j%d", bin_counter+1, o_right_r, o_right_i);
         end
      end
   end


   // ====================================================================
   // 7. HELPER FUNCTION (Cosine Generation)
   // ====================================================================
   function automatic signed [11:0] cos_val(input integer idx);
      real r;
      begin
         // cos(2 * pi * k * f / N)
         r = $cos(2.0 * 3.14159265359 * freq_bin * idx / N);
         // Scale to 12-bit signed (Max 2047)
         cos_val = $rtoi(r * 2047.0); 
      end
   endfunction

endmodule*/
`timescale 1ns/1ps
`default_nettype none

module tb_fftmain;

  localparam IWIDTH = 12;
  localparam OWIDTH = 19;
  localparam N      = 4096;

  // Clock / Reset
  reg i_clk = 0;
  reg i_reset;
  reg i_clk_enable;

  always #10 i_clk = ~i_clk; // 100 MHz

  // DUT I/O
  reg  [(2*IWIDTH-1):0] i_left, i_right;
  wire [(2*OWIDTH-1):0] o_left, o_right;
  wire                  o_sync;

  fftmain dut (
    .i_clk(i_clk),
    .i_reset(i_reset),
    .i_clk_enable(i_clk_enable),
    .i_left(i_left),
    .i_right(i_right),
    .o_left(o_left),
    .o_right(o_right),
    .o_sync(o_sync)
  );

  // Unpack outputs
  wire signed [OWIDTH-1:0] o_left_r  = o_left[2*OWIDTH-1:OWIDTH];
  wire signed [OWIDTH-1:0] o_left_i  = o_left[OWIDTH-1:0];
  wire signed [OWIDTH-1:0] o_right_r = o_right[2*OWIDTH-1:OWIDTH];
  wire signed [OWIDTH-1:0] o_right_i = o_right[OWIDTH-1:0];

  integer n;
  integer bin;

 // -----------------------------------------------
// Drive one clean FFT frame
// -----------------------------------------------
integer k;

initial begin
  // Reset
  i_reset      = 1;
  i_clk_enable = 0;
  i_left       = 0;
  i_right      = 0;

  repeat (10) @(posedge i_clk);

  // Deassert reset = FRAME START
  i_reset      = 0;
  i_clk_enable = 1;

  // ------------------------------------------------
  // Frame-aligned data (MUST start immediately)
  // ------------------------------------------------
  for (k = 0; k < N/2; k = k + 1) begin
    @(posedge i_clk);
    i_left  <= { cos_lut(2*k),   12'sd0 };
    i_right <= { cos_lut(2*k+1), 12'sd0 };
  end

  // Stop driving
  @(posedge i_clk);
  i_left  <= 0;
  i_right <= 0;

  // Flush pipeline
  repeat (10000) @(posedge i_clk);
  $finish;
end


  // ------------------------------------------------------------
  // Output monitor (quiet & clean)
  // ------------------------------------------------------------
always @(posedge i_clk) begin
  if (i_reset) begin
    bin <= 0;
  end else if (i_clk_enable) begin

    if (o_sync) begin
      bin <= 0;
      $display("\n=== FFT OUTPUT (Single-Tone Test) ===");
    end else if (bin < 32) begin
      $display("BIN %0d: %0d + j%0d", bin,   o_left_r,  o_left_i);
      $display("BIN %0d: %0d + j%0d", bin+1, o_right_r, o_right_i);
      bin <= bin + 2;
    end
  end
end
function automatic signed [11:0] cos_lut(input integer idx);
  real r;
  begin
    r = $cos(2.0 * 3.141592653589793 * 7.0 * idx / N);
    cos_lut = $rtoi(r * 2047.0); // scale to 12-bit signed
  end
endfunction

endmodule
