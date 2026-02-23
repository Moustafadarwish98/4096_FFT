`timescale 1ns/1ps
`default_nettype none

module tb_fftmain;

  localparam IWIDTH = 12;
  localparam OWIDTH = 19;
  localparam N      = 4096;

  localparam TESTMODE = 2;   // 0=Impulse, 1=DC, 2=Tone
  localparam TONE_BIN = 2000;

  reg i_clk = 0;
  reg i_reset;
  reg i_clk_enable;
  integer out_count;

  integer fout;

  reg frame_active;

  always #5 i_clk = ~i_clk;

  reg  [(2*IWIDTH-1):0] i_left, i_right;
  wire [(2*OWIDTH-1):0] o_left, o_right;
  wire o_sync;

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

  // ----------------------------------------------------
  // Output unpacking
  // ----------------------------------------------------
  wire signed [OWIDTH-1:0] o_left_r  = o_left[2*OWIDTH-1:OWIDTH];
  wire signed [OWIDTH-1:0] o_left_i  = o_left[OWIDTH-1:0];
  wire signed [OWIDTH-1:0] o_right_r = o_right[2*OWIDTH-1:OWIDTH];
  wire signed [OWIDTH-1:0] o_right_i = o_right[OWIDTH-1:0];

  wire [OWIDTH:0] mag_left  = abs_val(o_left_r)  + abs_val(o_left_i);
  wire [OWIDTH:0] mag_right = abs_val(o_right_r) + abs_val(o_right_i);

  integer k;
  integer bin;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      out_count <= 0;
      frame_active <= 0;
    end
    else if (i_clk_enable)
    begin
      if (dut.br_sync)
      begin
        frame_active <= 1'b1;
        out_count <= 0;
        bin <= 0;
        $display("\n=== FFT FRAME START ===");
      end
      else if (frame_active)
      begin
        out_count <= out_count + 2;  // L + R
        bin <= bin + 2;
      end
    end
  end
    // ============================================================
  // LATENCY MEASUREMENT
  // ============================================================
    integer core_latency;
  integer br_latency;
  integer total_latency;

  integer core_counter;
  integer br_counter;

  reg core_measured;
  reg br_measured;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      core_counter   <= 0;
      br_counter     <= 0;
      core_measured  <= 0;
      br_measured    <= 0;
    end
    else if (i_clk_enable)
    begin
      // --------------------------------------------------------
      // Count cycles before CORE FFT produces valid output
      // --------------------------------------------------------
      if (!core_measured)
      begin
        core_counter <= core_counter + 1;

        if (dut.w_s2)   // Last FFT stage sync (before bit reversal)
        begin
          core_latency  <= core_counter;
          core_measured <= 1'b1;

          $display("\n------------------------------------------------");
          $display("CORE FFT LATENCY:");
          $display("Time to Laststage Output: %0d cycles", core_counter);
          $display("------------------------------------------------\n");
        end
      end

      // --------------------------------------------------------
      // Count cycles before BIT REVERSAL produces valid output
      // --------------------------------------------------------
      if (core_measured && !br_measured)
      begin
        br_counter <= br_counter + 1;

        if (dut.br_sync)   // Bit-reversed output sync
        begin
          br_latency  <= br_counter;
          total_latency <= core_latency + br_counter;
          br_measured <= 1'b1;

          $display("\n------------------------------------------------");
          $display("BIT REVERSAL LATENCY:");
          $display("Time from Laststage to BR Output: %0d cycles", br_counter);
          $display("------------------------------------------------");

          $display("TOTAL LATENCY:");
          $display("Input to Final Output: %0d cycles", core_latency + br_counter);
          $display("------------------------------------------------\n");
        end
      end
    end
  end



  // ============================================================
  // STIMULUS
  // ============================================================
  initial
  begin
    fout = $fopen("fft_output.txt", "w");

    if (fout == 0)
    begin
      $display("ERROR: Cannot open fft_output.txt");
      $finish;
    end

    // CSV header
    $fwrite(fout, "BIN,REAL,IMAG\n");

    // Reset phase
    i_reset      = 1;
    i_clk_enable = 0;
    i_left       = 0;
    i_right      = 0;

    repeat (10) @(posedge i_clk);

    // Frame start alignment
    @(negedge i_clk);
    i_reset      <= 0;
    i_clk_enable <= 1;

    // Drive exactly ONE frame
    for (k = 0; k < N/2; k = k + 1)
    begin

      case (TESTMODE)

        0:
        begin // Impulse
          if (k == 0)
          begin
            i_left  <= {12'sd2047, 12'sd0};
            i_right <= 0;
          end
          else
          begin
            i_left  <= 0;
            i_right <= 0;
          end
        end

        1:
        begin // DC
          i_left  <= {12'sd1000, 12'sd0};
          i_right <= {12'sd1000, 12'sd0};
        end

        2:
        begin // Single-tone cosine
          i_left  <= {cos_lut(2*k),   12'sd0};
          i_right <= {cos_lut(2*k+1), 12'sd0};
        end

      endcase

      @(negedge i_clk);
    end

    // Stop driving
    @(posedge i_clk);
    i_left  <= 0;
    i_right <= 0;

    $display("Input frame complete.");

  end

  // ============================================================
  // OUTPUT MONITOR
  // ============================================================
  always @(posedge i_clk)
  begin
    if (i_clk_enable && frame_active)
    begin
      if (out_count < N)
      begin
        $fwrite(fout,"%0d,%0d,%0d\n", bin,   o_left_r,  o_left_i);
        $fwrite(fout,"%0d,%0d,%0d\n", bin+1, o_right_r, o_right_i);
      end

      if (out_count >= N-2)
      begin
        $display("End of FFT frame captured.");
        $fclose(fout);
        $finish;
      end
    end
  end


  // ============================================================
  // COSINE GENERATOR
  // ============================================================
  function automatic signed [11:0] cos_lut(input integer idx);
    real r;
    begin
      r = $cos(2.0 * 3.141592653589793 * TONE_BIN * idx / N);
      cos_lut = $rtoi(r * 2047.0);

    end
  endfunction

  // ============================================================
  // ABS FUNCTION (ModelSim-safe)
  // ============================================================
  function automatic [OWIDTH-1:0] abs_val;
    input signed [OWIDTH-1:0] val;
    begin
      abs_val = (val < 0) ? -val : val;
    end
  endfunction

endmodule
