// ---------------------------------------------------------------------------
// dmac_driver - plays the CPU.
//
// Turns a randomised dmac_cmd into concrete addresses, snapshots the source
// bytes for the scoreboard, drives the command handshake, and acknowledges
// interrupts with random delay.
//
// Destinations come out of a bump allocator so two concurrent transfers can
// never write the same bytes - that is what keeps the scoreboard sound while
// eight channels run at once.
// ---------------------------------------------------------------------------

class dmac_driver;

  virtual dmac_if  vif;
  dmac_scoreboard  sb;

  int unsigned     strb;
  longint unsigned src_base;
  longint unsigned dst_base;
  longint unsigned dst_bump = 0;

  // error window, in source address space; 0..0 means "no window"
  longint unsigned err_lo = 0;
  longint unsigned err_hi = 0;

  realtime         tdrv = 2ns;
  int unsigned     irq_gap = 2;
  bit              verbose = 1'b0;

  function new(virtual dmac_if vif, dmac_scoreboard sb, int unsigned strb,
               longint unsigned src_base, longint unsigned dst_base);
    this.vif      = vif;
    this.sb       = sb;
    this.strb     = strb;
    this.src_base = src_base;
    this.dst_base = dst_base;
  endfunction

  task reset();
    vif.cmd_valid <= 1'b0;
    vif.cmd_src   <= '0;
    vif.cmd_dst   <= '0;
    vif.cmd_len   <= '0;
    vif.irq_ready <= 1'b0;
  endtask

  // ---- one command ---------------------------------------------------------
  task send(dmac_cmd c);
    dmac_xfer x = new();

    x.len    = c.len;
    x.nbytes = c.len * strb;
    x.src    = src_base + c.slot * strb + c.soff;

    if (c.near4k) begin
      // push the destination up against a page boundary too
      dst_bump = ((dst_bump + 4095) & ~64'd4095) + 4096 - (c.maxb/2) * strb;
    end
    x.dst    = dst_base + dst_bump + c.doff;
    dst_bump = dst_bump + (c.len + 2) * strb;

    // the slave's error window can sit over the source (RRESP) or the
    // destination (BRESP); either way the channel must report irq_err
    x.expect_err = (err_hi != 0)
                && ( ((x.src <= err_hi) && ((x.src + x.nbytes - 1) >= err_lo))
                  || ((x.dst <= err_hi) && ((x.dst + x.nbytes - 1) >= err_lo)) );

    x.snapshot();
    sb.issued(x);

    if (verbose) $display("[DRV] %0t issue %s (%s)", $time, x.show(), c.show());

    @(posedge vif.clk);
    #tdrv;
    vif.cmd_valid = 1'b1;
    vif.cmd_src   = x.src;
    vif.cmd_dst   = x.dst;
    vif.cmd_len   = c.len;
    do @(posedge vif.clk); while (!vif.cmd_ready);
    #tdrv;
    vif.cmd_valid = 1'b0;
  endtask

  // ---- interrupt acknowledge, runs forever --------------------------------
  task run_irq_ack();
    forever begin
      @(posedge vif.clk);
      if (irq_gap > 0) repeat ($urandom_range(0, irq_gap)) begin
        #tdrv vif.irq_ready = 1'b0;
        @(posedge vif.clk);
      end
      #tdrv vif.irq_ready = 1'b1;
      @(posedge vif.clk);
    end
  endtask

endclass
