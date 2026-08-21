// ---------------------------------------------------------------------------
// axi_mem_pkg / axi_mem_model - AXI4 slave memory.
//
// Byte addressed sparse memory, so WSTRB and unaligned regions are trivial to
// model. The array lives in a package so the scoreboard can read it back
// without hierarchical references.
//
// READY signals carry randomised back-pressure so the DUT's handshake logic is
// actually exercised rather than always seeing a free bus.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

package axi_mem_pkg;

  logic [7:0] mem [longint unsigned];

  function automatic void wr_byte(longint unsigned a, logic [7:0] d);
    mem[a] = d;
  endfunction

  function automatic logic [7:0] rd_byte(longint unsigned a);
    return mem.exists(a) ? mem[a] : 8'h00;
  endfunction

  // Position-derived pattern rather than random data. Two reasons:
  //   1. a wrong byte offset shows up as a recognisable shift instead of
  //      noise, which is exactly the failure mode an unaligned DMA has;
  //   2. $urandom() inside a PACKAGE function returns X under Questa's
  //      -voptargs=+acc, which silently preloads the model with unknowns.
  //      Reproducible data sidesteps the whole question.
  function automatic logic [7:0] pattern(longint unsigned a);
    return 8'(a) ^ 8'(a >> 8) ^ 8'(a >> 13) ^ 8'h5a;
  endfunction

  function automatic void fill(longint unsigned base, int unsigned nbytes);
    for (int unsigned i = 0; i < nbytes; i++) mem[base+i] = pattern(base+i);
  endfunction

  function automatic void clear();
    mem.delete();
  endfunction

endpackage


`default_nettype none

module axi_mem_model
  import axi_mem_pkg::*;
#(
  parameter int      ADDR_WD = 32,
  parameter int      DATA_WD = 32,
  parameter int      ID_WD   = 4,
  parameter int      STRB_WD = DATA_WD/8,
  parameter realtime TDRV    = 2ns
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire  [ID_WD-1:0]   awid,
  input  wire  [ADDR_WD-1:0] awaddr,
  input  wire  [7:0]         awlen,
  input  wire  [2:0]         awsize,
  input  wire  [1:0]         awburst,
  input  wire                awvalid,
  output logic               awready,

  input  wire  [DATA_WD-1:0] wdata,
  input  wire  [STRB_WD-1:0] wstrb,
  input  wire                wlast,
  input  wire                wvalid,
  output logic               wready,

  output logic [ID_WD-1:0]   bid,
  output logic [1:0]         bresp,
  output logic               bvalid,
  input  wire                bready,

  input  wire  [ID_WD-1:0]   arid,
  input  wire  [ADDR_WD-1:0] araddr,
  input  wire  [7:0]         arlen,
  input  wire  [2:0]         arsize,
  input  wire  [1:0]         arburst,
  input  wire                arvalid,
  output logic               arready,

  output logic [ID_WD-1:0]   rid,
  output logic [DATA_WD-1:0] rdata,
  output logic [1:0]         rresp,
  output logic               rlast,
  output logic               rvalid,
  input  wire                rready
);

  // ---- knobs, poked by the test -------------------------------------------
  int unsigned     gap_r    = 2;      // read-side stalling,  0 = never stall
  int unsigned     gap_w    = 2;      // write-side stalling, 0 = never stall
  int unsigned     b_lat    = 0;      // extra B-response latency, in cycles;
                                      // large values back up the master's
                                      // write in-flight queue
  bit              err_en   = 1'b0;
  longint unsigned err_lo   = 0;
  longint unsigned err_hi   = 0;
  logic [1:0]      err_resp = 2'b10;  // SLVERR; 2'b11 is DECERR

  typedef struct {
    longint unsigned addr;
    int unsigned     len;
    int unsigned     size;
  } req_t;

  req_t       ar_q [$];
  logic [1:0] b_q  [$];

  function automatic logic [1:0] resp_for(longint unsigned a, int unsigned nbytes);
    if (!err_en) return 2'b00;
    if ((a <= err_hi) && ((a + nbytes - 1) >= err_lo)) return err_resp;
    return 2'b00;
  endfunction

  // ---- write address + write data -----------------------------------------
  initial begin : p_write
    longint unsigned base;
    int unsigned     len, bytes, g;
    logic [1:0]      bad;

    awready = 1'b0;
    wready  = 1'b0;
    @(posedge rst_n);

    forever begin
      g = (gap_w == 0) ? 0 : $urandom_range(0, gap_w);
      if (g > 0) begin
        #TDRV awready = 1'b0;
        repeat (g) @(posedge clk);
      end
      // WREADY may legally be held high before the address arrives; the DUT
      // never sends W before AW so nothing can be lost, and it exercises the
      // "slave ready first" handshake case
      #TDRV;
      awready = 1'b1;
      wready  = ($urandom_range(0, 1) != 0);
      do @(posedge clk); while (!awvalid);
      base  = awaddr;
      len   = awlen;
      bytes = 1 << awsize;
      #TDRV;
      awready = 1'b0;
      wready  = 1'b0;

      bad = 2'b00;
      for (int i = 0; i <= len; i++) begin
        g = (gap_w == 0) ? 0 : $urandom_range(0, gap_w);
        if (g > 0) begin
          #TDRV wready = 1'b0;
          repeat (g) @(posedge clk);
        end
        #TDRV wready = 1'b1;
        do @(posedge clk); while (!wvalid);

        for (int b = 0; b < STRB_WD; b++) begin
          if (wstrb[b]) wr_byte(base + i*bytes + b, wdata[8*b +: 8]);
        end
        if (resp_for(base + i*bytes, bytes) != 2'b00) bad = resp_for(base + i*bytes, bytes);

        if (i == len) begin
          assert (wlast)
            else begin tb_err_pkg::bump(); $error("mem: WLAST missing on the last beat of a %0d beat burst", len+1); end
        end else begin
          assert (!wlast)
            else begin tb_err_pkg::bump(); $error("mem: WLAST early, beat %0d of %0d", i, len+1); end
        end
      end
      #TDRV wready = 1'b0;

      b_q.push_back(bad);
    end
  end

  // ---- write response ------------------------------------------------------
  initial begin : p_bresp
    logic [1:0] r;

    bvalid = 1'b0;
    bid    = '0;
    bresp  = 2'b00;
    @(posedge rst_n);

    forever begin
      @(posedge clk);
      if (b_q.size() > 0) begin
        r = b_q.pop_front();
        if (b_lat > 0) repeat (b_lat) @(posedge clk);
        if (gap_w > 0) repeat ($urandom_range(0, gap_w)) @(posedge clk);
        #TDRV;
        bvalid = 1'b1;
        bresp  = r;
        do @(posedge clk); while (!bready);
        #TDRV bvalid = 1'b0;
      end
    end
  end

  // ---- read address --------------------------------------------------------
  initial begin : p_araddr
    int unsigned g;

    arready = 1'b0;
    @(posedge rst_n);

    forever begin
      g = (gap_r == 0) ? 0 : $urandom_range(0, gap_r);
      if (g > 0) begin
        #TDRV arready = 1'b0;
        repeat (g) @(posedge clk);
      end
      #TDRV arready = 1'b1;
      do @(posedge clk); while (!arvalid);
      ar_q.push_back('{addr: araddr, len: arlen, size: arsize});
      #TDRV arready = 1'b0;
    end
  end

  // ---- read data -----------------------------------------------------------
  initial begin : p_rdata
    req_t               r;
    int unsigned        bytes;
    logic [DATA_WD-1:0] d;

    rvalid = 1'b0;
    rlast  = 1'b0;
    rid    = '0;
    rresp  = 2'b00;
    rdata  = '0;
    @(posedge rst_n);

    forever begin
      @(posedge clk);
      if (ar_q.size() > 0) begin
        r     = ar_q.pop_front();
        bytes = 1 << r.size;
        for (int i = 0; i <= r.len; i++) begin
          if (gap_r > 0) begin
            repeat ($urandom_range(0, gap_r)) begin
              #TDRV rvalid = 1'b0;
              @(posedge clk);
            end
          end
          for (int b = 0; b < STRB_WD; b++) d[8*b +: 8] = rd_byte(r.addr + i*bytes + b);
          #TDRV;
          rvalid = 1'b1;
          rdata  = d;
          rlast  = (i == r.len);
          rresp  = resp_for(r.addr + i*bytes, bytes);
          do @(posedge clk); while (!rready);
        end
        #TDRV;
        rvalid = 1'b0;
        rlast  = 1'b0;
      end
    end
  end

  // ---- protocol sanity -----------------------------------------------------
  always @(posedge clk) if (rst_n) begin
    assert (!(awvalid && (awburst != 2'b01)))
      else begin tb_err_pkg::bump(); $error("mem: only INCR bursts are modelled (AWBURST=%b)", awburst); end
    assert (!(arvalid && (arburst != 2'b01)))
      else begin tb_err_pkg::bump(); $error("mem: only INCR bursts are modelled (ARBURST=%b)", arburst); end
    assert (!(awvalid && ((awaddr & ADDR_WD'((1<<awsize)-1)) != 0)))
      else begin tb_err_pkg::bump(); $error("mem: unaligned AWADDR %0h for size %0d", awaddr, awsize); end
    assert (!(arvalid && ((araddr & ADDR_WD'((1<<arsize)-1)) != 0)))
      else begin tb_err_pkg::bump(); $error("mem: unaligned ARADDR %0h for size %0d", araddr, arsize); end
    assert (!(awvalid && (awid != '0)))
      else begin tb_err_pkg::bump(); $error("mem: unexpected AWID %0h", awid); end
    assert (!(arvalid && (arid != '0)))
      else begin tb_err_pkg::bump(); $error("mem: unexpected ARID %0h", arid); end
  end

endmodule

`default_nettype wire
