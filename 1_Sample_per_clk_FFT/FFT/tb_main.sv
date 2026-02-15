`timescale 1ns/1ps
`default_nettype none

module tb_fftmain;

  // ============================================================
  // PARAMETERS
  // ============================================================
  localparam IWIDTH = 12;
  localparam OWIDTH = 19;
  localparam N      = 4096;

  localparam TESTMODE = 2;   // 0=Impulse, 1=DC, 2=Tone
  localparam TONE_BIN = 2;

  // ============================================================
  // CLOCK / CONTROL
  // ============================================================
  reg i_clk = 0;
  reg i_reset;
  reg i_clk_enable;

  always #5 i_clk = ~i_clk;

  // ============================================================
  // DUT SIGNALS
  // ============================================================
  reg  [(2*IWIDTH-1):0] i_sample;
  wire [(2*OWIDTH-1):0] o_result;
  wire o_sync;

  // ============================================================
  // DUT INSTANTIATION
  // ============================================================
  fftmain dut (
      .i_clk(i_clk),
      .i_reset(i_reset),
      .i_clk_enable(i_clk_enable),
      .i_sample(i_sample),
      .o_result(o_result),
      .o_sync(o_sync)
  );

  // ============================================================
  // OUTPUT UNPACKING
  // ============================================================
  wire signed [OWIDTH-1:0] o_real = o_result[2*OWIDTH-1:OWIDTH];
  wire signed [OWIDTH-1:0] o_imag = o_result[OWIDTH-1:0];

  // ============================================================
  // OUTPUT TRACKING
  // ============================================================
  integer fout;
  integer out_count;
  integer bin;
  reg frame_active;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      frame_active <= 0;
      out_count    <= 0;
      bin          <= 0;
    end
    else if (i_clk_enable)
    begin
      if (o_sync === 1'b1)
      begin
        frame_active <= 1'b1;
        out_count    <= 0;
        bin          <= 0;

        $display("\n=== FFT FRAME START @ %0t ===", $time);
      end
      else if (frame_active)
      begin
        out_count <= out_count + 1;
        bin       <= bin + 1;
      end
    end
  end

  // ============================================================
  // DEBUG PRINTS (Optional but useful)
  // ============================================================
  always @(posedge i_clk)
  if (i_clk_enable)
  begin
    if (dut.br_sync === 1'b1)
        $display("br_sync  @ %0t", $time);

    if (o_sync === 1'b1)
        $display("o_sync   @ %0t", $time);
  end

  // ============================================================
  // LATENCY MEASUREMENT (Robust)
  // ============================================================
  integer cycle_counter;
  integer core_latency;
  integer br_latency;
  integer total_latency;

  reg counting;
  reg core_measured;
  reg br_measured;

  always @(posedge i_clk)
  begin
    if (i_reset)
    begin
      cycle_counter <= 0;
      counting      <= 0;
      core_measured <= 0;
      br_measured   <= 0;
      core_latency  <= -1;
      br_latency    <= -1;
    end
    else if (i_clk_enable)
    begin
      if (counting)
        cycle_counter <= cycle_counter + 1;
    end
  end

  // Start counting EXACTLY when first valid input is applied
  always @(posedge i_clk)
  begin
    if (i_reset)
      counting <= 0;
    else if (i_clk_enable && !counting && i_sample !== 0)
      counting <= 1'b1;
  end

  // CORE FFT LATENCY (Input → br_sync)
  always @(posedge i_clk)
  begin
    if (i_clk_enable && counting && !core_measured)
    begin
      if (dut.br_sync === 1'b1)
      begin
        core_latency  <= cycle_counter;
        core_measured <= 1'b1;

        $display("\n------------------------------------------------");
        $display("CORE FFT LATENCY:");
        $display("First input → br_sync : %0d cycles", cycle_counter);
        $display("------------------------------------------------");
      end
    end
  end

  // BIT REVERSAL LATENCY (br_sync → o_sync)
  always @(posedge i_clk)
  begin
    if (i_clk_enable && counting && core_measured && !br_measured)
    begin
      if (o_sync === 1'b1)
      begin
        br_latency    <= cycle_counter - core_latency;
        total_latency <= cycle_counter;
        br_measured   <= 1'b1;

        $display("BIT REVERSAL LATENCY:");
        $display("br_sync → o_sync : %0d cycles",
                 cycle_counter - core_latency);
        $display("------------------------------------------------");
        $display("TOTAL LATENCY:");
        $display("First input → o_sync : %0d cycles", cycle_counter);
        $display("------------------------------------------------\n");
      end
    end
  end

  // ============================================================
  // STIMULUS
  // ============================================================
  integer k;

  initial
  begin
    fout = $fopen("fft_output.txt", "w");

    if (fout == 0)
    begin
      $display("ERROR: Cannot open fft_output.txt");
      $finish;
    end

    $fwrite(fout, "BIN,REAL,IMAG\n");

    // Reset phase
    i_reset      = 1;
    i_clk_enable = 0;
    i_sample     = 0;

    repeat (10) @(posedge i_clk);

    @(negedge i_clk);
    i_reset      <= 0;
    i_clk_enable <= 1;

    // Drive ONE full frame
    for (k = 0; k < N; k = k + 1)
    begin
      case (TESTMODE)

        0: // Impulse
          i_sample <= (k == 0) ? {12'sd2047,12'sd0} : 0;

        1: // DC
          i_sample <= {12'sd1000,12'sd0};

        2: // Tone
          i_sample <= {cos_lut(k),12'sd0};

      endcase

      @(negedge i_clk);
    end

    @(posedge i_clk);
    i_sample <= 0;

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
        $fwrite(fout,"%0d,%0d,%0d\n", bin, o_real, o_imag);

      if (out_count == N-1)
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
  // ABS FUNCTION
  // ============================================================
  function automatic [OWIDTH-1:0] abs_val;
    input signed [OWIDTH-1:0] val;
    begin
      abs_val = (val < 0) ? -val : val;
    end
  endfunction

endmodule
