
module	laststage #(
    parameter IWIDTH=16,OWIDTH=IWIDTH+1, SHIFT=0
  ) (
    input	wire			i_clk, i_reset, i_clk_enable, i_sync,
    input	wire  [(2*IWIDTH-1):0]	i_val,
    output	wire [(2*OWIDTH-1):0]	o_val,
    output	reg			o_sync
  );
  // Local declarations
  reg	signed	[(IWIDTH-1):0]	m_r, m_i;
  wire	signed	[(IWIDTH-1):0]	i_r, i_i;

  // Don't forget that we accumulate a bit by adding two values
  // together. Therefore our intermediate value must have one more
  // bit than the two originals.
  reg	signed	[(IWIDTH):0]	rnd_r, rnd_i, sto_r, sto_i;
  reg				wait_for_sync, stage;
  reg		[1:0]		sync_pipe;
  wire	signed	[(OWIDTH-1):0]	o_r, o_i;

  assign	i_r = i_val[(2*IWIDTH-1):(IWIDTH)];
  assign	i_i = i_val[(IWIDTH-1):0];

  // wait_for_sync, stage

  always @(posedge i_clk)
    if (i_reset)
    begin
      wait_for_sync <= 1'b1;
      stage         <= 1'b0;
    end
    else if ((i_clk_enable)&&((!wait_for_sync)||(i_sync))&&(!stage))
    begin
      wait_for_sync <= 1'b0;
      stage <= 1'b1;
    end
    else if (i_clk_enable)
      stage <= 1'b0;

  // sync_pipe

  always @(posedge i_clk)
    if (i_reset)
      sync_pipe <= 0;
    else if (i_clk_enable)
      sync_pipe <= { sync_pipe[0], i_sync };

  // o_sync

  always @(posedge i_clk)
    if (i_reset)
      o_sync <= 1'b0;
    else if (i_clk_enable)
      o_sync <= sync_pipe[1];
  
  // m_r, m_i, rnd_r, rnd_i
  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      if (!stage)
      begin
        // Clock 1
        m_r <= i_r;
        m_i <= i_i;
        // Clock 3
        rnd_r <= sto_r;
        rnd_i <= sto_i;
      end
      else
      begin
        // Clock 2
        rnd_r <= m_r + i_r;
        rnd_i <= m_i + i_i;
        
        sto_r <= m_r - i_r;
        sto_i <= m_i - i_i;
        
      end
    end

  // Round the results, generating o_r, o_i, and thus o_val
  convround #(IWIDTH+1,OWIDTH,SHIFT) do_rnd_r(i_clk, i_clk_enable, rnd_r, o_r);
  convround #(IWIDTH+1,OWIDTH,SHIFT) do_rnd_i(i_clk, i_clk_enable, rnd_i, o_i);

  assign	o_val  = { o_r, o_i };
 
endmodule
