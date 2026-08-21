// ---------------------------------------------------------------------------
// dmac_tb_top - clock, reset, DUT, memory model, coverage, assertions and the
// tests themselves.
//
// Tests are selected with +TEST=<name>. One top with switchable constraint
// sets is simpler to navigate than a test library, which is what "keep the
// testbench simple" asks for.
//
//   basic     aligned only, exercises the plain path
//   unalign   random source and destination byte offsets
//   cross4k   transfers deliberately straddling 4 KB page boundaries
//   single    one-beat transfers
//   maxburst  lengths at and around MAX_BURST_LEN
//   long      transfers far longer than one burst
//   serial    one command at a time, so exactly one channel is ever active
//   wstall    write side heavily stalled, fills the per-channel buffers
//   err       SLVERR and DECERR, on both the read and the write side
//   irqstall  interrupt acknowledge withheld, completions pile up
//   nobp      no bus back-pressure, maximum throughput
//   full      everything mixed (default)
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module dmac_tb_top;

  import dmac_pkg::*;
  import dmac_tb_pkg::*;

  localparam int      ADDR_WD  = dmac_pkg::ADDR_WD;
  localparam int      DATA_WD  = dmac_pkg::DATA_WD;
  localparam int      LEN_WD   = dmac_pkg::LEN_WD;
  localparam int      ID_WD    = dmac_pkg::ID_WD;
  localparam int      STRB_WD  = DATA_WD/8;
  localparam int      CH_WD    = dmac_pkg::cw(dmac_pkg::CHANNEL_COUNT);
  localparam realtime TDRV     = 2ns;
  localparam realtime TCLK     = 10ns;

  localparam longint unsigned SRC_BASE = 64'h0000_1000;
  localparam longint unsigned DST_BASE = 64'h0080_0000;
  localparam int unsigned     SRC_SIZE = 64*1024;              // bytes
  localparam int unsigned     SRC_SLOTS = SRC_SIZE/STRB_WD;

  // error window: one page inside the source region
  localparam longint unsigned ERR_LO = SRC_BASE + 32*1024;
  localparam longint unsigned ERR_HI = ERR_LO + 4095;

  // ---- clock and reset -----------------------------------------------------
  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #(TCLK/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    #TDRV rst_n = 1'b1;
  end

  // ---- interface -----------------------------------------------------------
  dmac_if #(
    .ADDR_WD (ADDR_WD),
    .DATA_WD (DATA_WD),
    .LEN_WD  (LEN_WD),
    .ID_WD   (ID_WD),
    .CH_WD   (CH_WD),
    .STRB_WD (STRB_WD)
  ) intf (.clk(clk), .rst_n(rst_n));

  // ---- DUT -----------------------------------------------------------------
  dmac_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),

    .cmd_valid     (intf.cmd_valid),
    .cmd_ready     (intf.cmd_ready),
    .cmd_src       (intf.cmd_src),
    .cmd_dst       (intf.cmd_dst),
    .cmd_len       (intf.cmd_len),

    .alloc_valid   (intf.alloc_valid),
    .alloc_ch      (intf.alloc_ch),

    .irq_valid     (intf.irq_valid),
    .irq_ready     (intf.irq_ready),
    .irq_ch        (intf.irq_ch),
    .irq_err       (intf.irq_err),

    .m_axi_awid    (intf.awid),
    .m_axi_awaddr  (intf.awaddr),
    .m_axi_awlen   (intf.awlen),
    .m_axi_awsize  (intf.awsize),
    .m_axi_awburst (intf.awburst),
    .m_axi_awvalid (intf.awvalid),
    .m_axi_awready (intf.awready),

    .m_axi_wdata   (intf.wdata),
    .m_axi_wstrb   (intf.wstrb),
    .m_axi_wlast   (intf.wlast),
    .m_axi_wvalid  (intf.wvalid),
    .m_axi_wready  (intf.wready),

    .m_axi_bid     (intf.bid),
    .m_axi_bresp   (intf.bresp),
    .m_axi_bvalid  (intf.bvalid),
    .m_axi_bready  (intf.bready),

    .m_axi_arid    (intf.arid),
    .m_axi_araddr  (intf.araddr),
    .m_axi_arlen   (intf.arlen),
    .m_axi_arsize  (intf.arsize),
    .m_axi_arburst (intf.arburst),
    .m_axi_arvalid (intf.arvalid),
    .m_axi_arready (intf.arready),

    .m_axi_rid     (intf.rid),
    .m_axi_rdata   (intf.rdata),
    .m_axi_rresp   (intf.rresp),
    .m_axi_rlast   (intf.rlast),
    .m_axi_rvalid  (intf.rvalid),
    .m_axi_rready  (intf.rready)
  );

  // ---- memory model --------------------------------------------------------
  axi_mem_model #(
    .ADDR_WD (ADDR_WD),
    .DATA_WD (DATA_WD),
    .ID_WD   (ID_WD),
    .STRB_WD (STRB_WD),
    .TDRV    (TDRV)
  ) u_mem (
    .clk     (clk),
    .rst_n   (rst_n),
    .awid    (intf.awid),
    .awaddr  (intf.awaddr),
    .awlen   (intf.awlen),
    .awsize  (intf.awsize),
    .awburst (intf.awburst),
    .awvalid (intf.awvalid),
    .awready (intf.awready),
    .wdata   (intf.wdata),
    .wstrb   (intf.wstrb),
    .wlast   (intf.wlast),
    .wvalid  (intf.wvalid),
    .wready  (intf.wready),
    .bid     (intf.bid),
    .bresp   (intf.bresp),
    .bvalid  (intf.bvalid),
    .bready  (intf.bready),
    .arid    (intf.arid),
    .araddr  (intf.araddr),
    .arlen   (intf.arlen),
    .arsize  (intf.arsize),
    .arburst (intf.arburst),
    .arvalid (intf.arvalid),
    .arready (intf.arready),
    .rid     (intf.rid),
    .rdata   (intf.rdata),
    .rresp   (intf.rresp),
    .rlast   (intf.rlast),
    .rvalid  (intf.rvalid),
    .rready  (intf.rready)
  );

  // ---- assertions ----------------------------------------------------------
  dmac_axi_assert #(
    .ADDR_WD       (ADDR_WD),
    .DATA_WD       (DATA_WD),
    .ID_WD         (ID_WD),
    .MAX_BURST_LEN (dmac_pkg::MAX_BURST_LEN),
    .STRB_WD       (STRB_WD)
  ) u_assert (
    .clk     (clk),     .rst_n   (rst_n),
    .awid    (intf.awid),    .awaddr  (intf.awaddr),  .awlen   (intf.awlen),
    .awsize  (intf.awsize),  .awburst (intf.awburst), .awvalid (intf.awvalid),
    .awready (intf.awready),
    .wdata   (intf.wdata),   .wstrb   (intf.wstrb),   .wlast   (intf.wlast),
    .wvalid  (intf.wvalid),  .wready  (intf.wready),
    .bresp   (intf.bresp),   .bvalid  (intf.bvalid),  .bready  (intf.bready),
    .arid    (intf.arid),    .araddr  (intf.araddr),  .arlen   (intf.arlen),
    .arsize  (intf.arsize),  .arburst (intf.arburst), .arvalid (intf.arvalid),
    .arready (intf.arready),
    .rdata   (intf.rdata),   .rresp   (intf.rresp),   .rlast   (intf.rlast),
    .rvalid  (intf.rvalid),  .rready  (intf.rready)
  );

  // ---- coverage ------------------------------------------------------------
  dmac_coverage #(
    .ADDR_WD       (ADDR_WD),
    .DATA_WD       (DATA_WD),
    .LEN_WD        (LEN_WD),
    .MAX_BURST_LEN (dmac_pkg::MAX_BURST_LEN),
    .CHANNEL_COUNT (dmac_pkg::CHANNEL_COUNT),
    .STRB_WD       (STRB_WD)
  ) u_cov (
    .clk         (clk),           .rst_n     (rst_n),
    .cmd_valid   (intf.cmd_valid), .cmd_ready (intf.cmd_ready),
    .cmd_src     (intf.cmd_src),   .cmd_dst   (intf.cmd_dst),
    .cmd_len     (intf.cmd_len),
    .irq_valid   (intf.irq_valid), .irq_ready (intf.irq_ready),
    .irq_ch      (intf.irq_ch),    .irq_err   (intf.irq_err),
    .alloc_valid (intf.alloc_valid), .alloc_ch (intf.alloc_ch),
    .awaddr      (intf.awaddr),  .awlen   (intf.awlen),
    .awvalid     (intf.awvalid), .awready (intf.awready),
    .wstrb       (intf.wstrb),   .wlast   (intf.wlast),
    .wvalid      (intf.wvalid),  .wready  (intf.wready),
    .bresp       (intf.bresp),   .bvalid  (intf.bvalid), .bready (intf.bready),
    .araddr      (intf.araddr),  .arlen   (intf.arlen),
    .arvalid     (intf.arvalid), .arready (intf.arready),
    .rresp       (intf.rresp),   .rlast   (intf.rlast),
    .rvalid      (intf.rvalid),  .rready  (intf.rready)
  );

  // ---- coverage bound into the DUT hierarchy -------------------------------
  // Placed here rather than at compilation-unit scope so elaboration always
  // picks them up without needing -cuname.
  bind dmac_rr_arb   dmac_arb_cov  #(.N(N), .ID_W(ID_W))                u_cov (.*);
  bind dmac_fifo     dmac_fifo_cov #(.DEPTH(DEPTH), .CNT_WD(CNT_WD))    u_cov (.*);
  bind dmac_channels dmac_chan_cov #(.CHANNEL_COUNT(CHANNEL_COUNT))     u_cov (.*);

  // ---- environment ---------------------------------------------------------
  dmac_scoreboard sb;
  dmac_driver     drv;
  dmac_monitor    mon;

  string       test    = "full";
  int unsigned n_cmd   = 200;
  int unsigned n_fail  = 0;
  bit          verbose = 1'b0;

  task automatic run_stream(int unsigned count, bit align_only, bit near4k,
                            int unsigned fixed_len, int unsigned maxlen);
    dmac_cmd c;
    for (int unsigned i = 0; i < count; i++) begin
      c            = new();
      c.strb       = STRB_WD;
      c.maxb       = dmac_pkg::MAX_BURST_LEN;
      c.maxlen     = maxlen;
      c.slots      = SRC_SLOTS - maxlen - 2;
      c.align_only = align_only;
      c.near4k     = near4k;
      c.fixed_len  = fixed_len;
      if (!c.randomize()) $fatal(1, "dmac_cmd randomize failed");
      drv.send(c);
    end
  endtask

  // one command at a time: guarantees exactly one channel is ever active,
  // which is the only way to cover "the arbiter re-granted the same channel"
  task automatic run_serial(int unsigned count, int unsigned maxlen);
    dmac_cmd c;
    for (int unsigned i = 0; i < count; i++) begin
      c        = new();
      c.strb   = STRB_WD;
      c.maxb   = dmac_pkg::MAX_BURST_LEN;
      c.maxlen = maxlen;
      c.slots  = SRC_SLOTS - maxlen - 2;
      if (!c.randomize()) $fatal(1, "dmac_cmd randomize failed");
      drv.send(c);
      while (!sb.idle()) @(posedge clk);
      repeat (2) @(posedge clk);
    end
  endtask

  // one error flavour at a time; the window has to be quiet between phases or
  // in-flight transfers would be judged against the wrong expectation
  task automatic run_err_phase(int unsigned count, longint unsigned lo,
                               longint unsigned hi, logic [1:0] resp);
    drain(200_000);
    u_mem.err_en   = 1'b1;
    u_mem.err_lo   = lo;
    u_mem.err_hi   = hi;
    u_mem.err_resp = resp;
    drv.err_lo     = lo;
    drv.err_hi     = hi;
    run_stream(count, 1'b0, 1'b0, 0, 40);
    drain(200_000);
  endtask

  task automatic drain(int unsigned timeout_cycles);
    int unsigned n = 0;
    while (!sb.idle() && (n < timeout_cycles)) begin
      @(posedge clk);
      n++;
    end
    if (!sb.idle()) begin
      $error("[TB] timeout: %0d transfers never completed", sb.act.num() + sb.pend.size());
      n_fail++;
    end
  endtask

  initial begin
    if ($value$plusargs("TEST=%s", test));
    if ($value$plusargs("NCMD=%d", n_cmd));
    if ($test$plusargs("VERBOSE")) verbose = 1'b1;

    $display("==============================================================");
    $display("[TB] AXI4 DMA controller regression");
    $display("[TB] test=%s  channels=%0d  data=%0d  max_burst=%0d",
             test, dmac_pkg::CHANNEL_COUNT, DATA_WD, dmac_pkg::MAX_BURST_LEN);
    $display("==============================================================");

    // preload the source region with a known random pattern
    axi_mem_pkg::clear();
    axi_mem_pkg::fill(SRC_BASE, SRC_SIZE);

    // if the pattern is not actually in the model then every later compare is
    // meaningless, so check it before anything else runs
    for (int unsigned i = 0; i < 16; i++) begin
      if ($isunknown(axi_mem_pkg::rd_byte(SRC_BASE + i)))
        $fatal(1, "[TB] source preload failed: byte at %0h is %0h",
               SRC_BASE + i, axi_mem_pkg::rd_byte(SRC_BASE + i));
    end

    sb = new();
    sb.verbose = verbose;

    drv = new(intf, sb, STRB_WD, SRC_BASE, DST_BASE);
    drv.tdrv    = TDRV;
    drv.verbose = verbose;

    mon = new(intf, sb);
    mon.verbose = verbose;

    drv.reset();
    @(posedge rst_n);
    repeat (2) @(posedge clk);

    fork
      mon.run();
      drv.run_irq_ack();
    join_none

    case (test)
      "basic"    : run_stream(n_cmd, 1'b1, 1'b0, 0, 40);
      "unalign"  : run_stream(n_cmd, 1'b0, 1'b0, 0, 40);
      "cross4k"  : run_stream(n_cmd, 1'b0, 1'b1, 0, 40);
      "single"   : run_stream(n_cmd, 1'b0, 1'b0, 1, 40);
      "maxburst" : begin
        run_stream(n_cmd/3 + 1, 1'b0, 1'b0, dmac_pkg::MAX_BURST_LEN,   40);
        run_stream(n_cmd/3 + 1, 1'b0, 1'b0, dmac_pkg::MAX_BURST_LEN-1, 40);
        run_stream(n_cmd/3 + 1, 1'b0, 1'b0, dmac_pkg::MAX_BURST_LEN+1, 40);
      end
      "long"     : run_stream(n_cmd/4 + 1, 1'b0, 1'b0, 0, 250);
      "serial"   : run_serial(n_cmd/8 + 1, 40);
      "wstall"   : begin
        // phase A - read wide open, W beats heavily stalled: the per-channel
        // data buffers fill up and the read credit scheme gets a real workout
        u_mem.gap_r = 0;
        u_mem.gap_w = 12;
        u_mem.b_lat = 0;
        run_stream(n_cmd/8 + 1, 1'b0, 1'b0, 0, 120);
        drain(200_000);

        // phase B - W beats fast but B responses very slow, so bursts are
        // issued far quicker than they retire and the write in-flight queue
        // backs up to full
        u_mem.gap_w = 0;
        u_mem.b_lat = 200;
        run_stream(n_cmd/8 + 1, 1'b0, 1'b0, 0, 120);
      end
      "err"      : begin
        // four phases: SLVERR and DECERR, on the read side and the write side
        run_err_phase(n_cmd/4 + 1, SRC_BASE, SRC_BASE + SRC_SIZE - 1, 2'b10);
        run_err_phase(n_cmd/4 + 1, SRC_BASE, SRC_BASE + SRC_SIZE - 1, 2'b11);
        run_err_phase(n_cmd/4 + 1, DST_BASE, DST_BASE + 64'h0010_0000, 2'b10);
        run_err_phase(n_cmd/4 + 1, DST_BASE, DST_BASE + 64'h0010_0000, 2'b11);
      end
      "irqstall" : begin
        // hold the CPU's interrupt acknowledge off for long stretches so
        // several channels sit in DONE at once and the interrupt arbiter
        // actually has a crowd to arbitrate between
        drv.irq_gap = 80;
        run_stream(n_cmd/2 + 1, 1'b0, 1'b0, 0, 4);
      end
      "nobp"     : begin
        u_mem.gap_r = 0;
        u_mem.gap_w = 0;
        drv.irq_gap = 0;
        run_stream(n_cmd, 1'b0, 1'b0, 0, 40);
      end
      "full"     : begin
        run_stream(n_cmd/4, 1'b1, 1'b0, 0, 40);
        run_stream(n_cmd/4, 1'b0, 1'b0, 0, 40);
        run_stream(n_cmd/4, 1'b0, 1'b1, 0, 40);
        run_stream(n_cmd/8, 1'b0, 1'b0, 1, 40);
        run_stream(n_cmd/8, 1'b0, 1'b0, dmac_pkg::MAX_BURST_LEN, 40);
      end
      default    : $fatal(1, "[TB] unknown +TEST=%s", test);
    endcase

    drain(500_000);

    repeat (50) @(posedge clk);

    sb.report();
    n_fail += sb.n_errors;
    n_fail += tb_err_pkg::n_err;

    $display("[TB] commands allocated : %0d", mon.n_alloc);
    $display("[TB] interrupts seen    : %0d", mon.n_done);
    $display("[TB] protocol/model errs: %0d", tb_err_pkg::n_err);

    if (n_fail == 0) $display("TEST PASSED");
    else             $display("TEST FAILED (%0d errors)", n_fail);
    $display("==============================================================");
    $finish;
  end

  // ---- global watchdog -----------------------------------------------------
  initial begin
    #20ms;
    $display("TEST FAILED (global timeout)");
    $fatal(1, "[TB] global timeout");
  end

endmodule
