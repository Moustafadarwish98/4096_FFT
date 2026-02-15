// Parameters:
//	i_clk	The clock.  All operations are synchronous with this clock.
//	i_reset	Synchronous reset, active high.  Setting this line will
//			force the reset of all of the internals to this routine.
//			Further, following a reset, the o_sync line will go
//			high the same time the first output sample is valid.
//	i_clk_enable	A clock enable line.  If this line is set, this module
//			will accept one complex input value, and produce
//			one (possibly empty) complex output value.
//	i_sample	The complex input sample.  This value is split
//			into two two's complement numbers, 12 bits each, with
//			the real portion in the high order bits, and the
//			imaginary portion taking the bottom 12 bits.
//	o_result	The output result, of the same format as i_sample,
//			only having 19 bits for each of the real and imaginary
//			components, leading to 38 bits total.
//	o_sync	A one bit output indicating the first sample of the FFT frame.
//			It also indicates the first valid sample out of the FFT
//			on the first frame.



module fftmain(i_clk, i_reset, i_clk_enable,
                 i_sample, o_result, o_sync);

  localparam	IWIDTH=12, OWIDTH=19,  LGWIDTH=12;

  input	wire				i_clk, i_reset, i_clk_enable;

  input	wire	[(2*IWIDTH-1):0]	i_sample;
  output	reg	[(2*OWIDTH-1):0]	o_result;
  output	reg				o_sync;

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
  localparam STAGE11_OWIDTH = 19; // +1 growth
  // Outputs of the FFT, ready for bit reversal.
  wire				br_sync;
  wire	[(2*OWIDTH-1):0]	br_result;


  wire		w_s4096;
  wire	[2*STAGE1_OWIDTH-1:0]	w_d4096;
  fftstage	#(

             .IWIDTH(IWIDTH),
             .CWIDTH(IWIDTH+4),
             .OWIDTH(13),
             .LGSPAN(11),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_4096.hex")

           ) stage_4096(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(!i_reset),
             .i_data(i_sample),
             .o_data(w_d4096),
             .o_sync(w_s4096)
           );
  wire		w_s2048;
  wire	[2*STAGE2_OWIDTH-1:0]	w_d2048;
  fftstage	#(
             .IWIDTH(STAGE1_OWIDTH),
             .CWIDTH(STAGE1_OWIDTH+4),
             .OWIDTH(STAGE2_OWIDTH),
             .LGSPAN(10),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_2048.hex")
           ) stage_2048(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s4096),
             .i_data(w_d4096),
             .o_data(w_d2048),
             .o_sync(w_s2048)
           );

  wire		w_s1024;
  wire	[2*STAGE3_OWIDTH-1:0]	w_d1024;
  fftstage	#(

             .IWIDTH(STAGE2_OWIDTH),
             .CWIDTH(STAGE2_OWIDTH+4),
             .OWIDTH(STAGE3_OWIDTH),
             .LGSPAN(9),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_1024.hex")

           ) stage_1024(

             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s2048),
             .i_data(w_d2048),
             .o_data(w_d1024),
             .o_sync(w_s1024)

           );

  wire		w_s512;
  wire	[2*STAGE4_OWIDTH-1:0]	w_d512;
  fftstage	#(

             .IWIDTH(STAGE3_OWIDTH),
             .CWIDTH(STAGE3_OWIDTH+4),
             .OWIDTH(STAGE4_OWIDTH),
             .LGSPAN(8),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_512.hex")

           ) stage_512(

             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s1024),
             .i_data(w_d1024),
             .o_data(w_d512),
             .o_sync(w_s512)

           );

  wire		w_s256;
  wire	[2*STAGE5_OWIDTH-1:0]	w_d256;
  fftstage	#(

             .IWIDTH(STAGE4_OWIDTH),
             .CWIDTH(STAGE4_OWIDTH+4),
             .OWIDTH(STAGE5_OWIDTH),
             .LGSPAN(7),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_256.hex")

           ) stage_256(

             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s512),
             .i_data(w_d512),
             .o_data(w_d256),
             .o_sync(w_s256)

           );

  wire		w_s128;
  wire	[2*STAGE6_OWIDTH-1:0]	w_d128;
  fftstage	#(
             .IWIDTH(STAGE5_OWIDTH),
             .CWIDTH(STAGE5_OWIDTH+4),
             .OWIDTH(STAGE6_OWIDTH),
             .LGSPAN(6),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_128.hex")
           ) stage_128(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s256),
             .i_data(w_d256),
             .o_data(w_d128),
             .o_sync(w_s128)
           );

  wire		w_s64;
  wire	[2*STAGE7_OWIDTH-1:0]	w_d64;
  fftstage	#(
             .IWIDTH(STAGE6_OWIDTH),
             .CWIDTH(STAGE6_OWIDTH+4),
             .OWIDTH(STAGE7_OWIDTH),
             .LGSPAN(5),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_64.hex")
           ) stage_64(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s128),
             .i_data(w_d128),
             .o_data(w_d64),
             .o_sync(w_s64)
           );

  wire		w_s32;
  wire	[2*STAGE8_OWIDTH-1:0]	w_d32;
  fftstage	#(
             .IWIDTH(STAGE7_OWIDTH),
             .CWIDTH(STAGE7_OWIDTH+4),
             .OWIDTH(STAGE8_OWIDTH),
             .LGSPAN(4),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_32.hex")
           ) stage_32(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s64),
             .i_data(w_d64),
             .o_data(w_d32),
             .o_sync(w_s32)
           );

  wire		w_s16;
  wire	[2*STAGE9_OWIDTH-1:0]	w_d16;
  fftstage	#(
             .IWIDTH(STAGE8_OWIDTH),
             .CWIDTH(STAGE8_OWIDTH+4),
             .OWIDTH(STAGE9_OWIDTH),
             .LGSPAN(3),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_16.hex")
           ) stage_16(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s32),
             .i_data(w_d32),
             .o_data(w_d16),
             .o_sync(w_s16)
           );

  wire		w_s8;
  wire	[2*STAGE10_OWIDTH-1:0]	w_d8;
  fftstage	#(
             .IWIDTH(STAGE9_OWIDTH),
             .CWIDTH(STAGE9_OWIDTH+4),
             .OWIDTH(STAGE10_OWIDTH),
             .LGSPAN(2),
             .BFLYSHIFT(0),
             .OPT_HWMPY(0),
             .CKPCE(1),
             .COEFFILE("cmem_8.hex")
           ) stage_8(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s16),
             .i_data(w_d16),
             .o_data(w_d8),
             .o_sync(w_s8)
           );

  wire		w_s4;
  wire	[2*STAGE11_OWIDTH-1:0]	w_d4;
  qtrstage	#(
             .IWIDTH(STAGE10_OWIDTH),
             .OWIDTH(STAGE11_OWIDTH),
             .LGWIDTH(12),
             .INVERSE(0),
             .SHIFT(0)
           ) stage_4(
             .i_clk(i_clk),
             .i_reset(i_reset),
             .i_clk_enable(i_clk_enable),
             .i_sync(w_s8),
             .i_data(w_d8),
             .o_data(w_d4),
             .o_sync(w_s4)
           );
  wire		w_s2;

  wire	[2*STAGE11_OWIDTH-1:0]	w_d2;
  laststage	#(
              .IWIDTH(STAGE11_OWIDTH),
              .OWIDTH(OWIDTH),
              .SHIFT(1)
            ) stage_2(
              .i_clk(i_clk),
              .i_reset(i_reset),
              .i_clk_enable(i_clk_enable),
              .i_sync(w_s4),
              .i_val(w_d4),
              .o_val(w_d2),
              .o_sync(w_s2)
            );

  wire	br_start;
  reg	r_br_started;

  always @(posedge i_clk)
    if (i_reset)
      r_br_started <= 1'b0;
    else if (i_clk_enable)
      r_br_started <= r_br_started || w_s2;
  assign	br_start = r_br_started || w_s2;


  bitreverse	#(
               .LGSIZE(12), .WIDTH(OWIDTH)
             ) revstage (
               .i_clk(i_clk),
               .i_reset(i_reset),
               .i_clk_enable(i_clk_enable & br_start),
               .i_in(w_d2),
               .o_out(br_result),
               .o_sync(br_sync)
             );

  // Last clock: Register our outputs
  always @(posedge i_clk)
    if (i_reset)
      o_sync  <= 1'b0;
    else if (i_clk_enable)
      o_sync  <= br_sync;

  always @(posedge i_clk)
    if (i_clk_enable)
      o_result  <= br_result;


endmodule
