// ---------------------------------------------------------------------------
// dmac_pkg - single source of truth for every parameter in the design.
// Change a value here and the whole hierarchy follows; no other file holds a
// hard-coded width, depth or count.
// ---------------------------------------------------------------------------
`ifndef DMAC_PKG_SV
`define DMAC_PKG_SV

package dmac_pkg;

  // ---- brief-mandated parameters -------------------------------------------
  parameter int ADDR_WD       = 32;
  parameter int DATA_WD       = 32;
  parameter int CHANNEL_COUNT = 8;    // 8 channels
  parameter int MAX_BURST_LEN = 16;   // 16 beats

  // ---- supporting parameters -----------------------------------------------
  parameter int LEN_WD          = 16;               // command length, in BEATS
  parameter int ID_WD           = 4;
  parameter int CMD_FIFO_DEPTH  = 8;                // pending CPU commands
  parameter int DATA_FIFO_DEPTH = 2*MAX_BURST_LEN;  // per channel
  parameter int RD_OUTSTANDING  = 4;                // AR bursts in flight
  parameter int WR_OUTSTANDING  = 4;                // AW bursts in flight

  // ---- AXI constants --------------------------------------------------------
  parameter logic [1:0] BURST_INCR = 2'b01;
  parameter logic [1:0] RESP_OKAY  = 2'b00;
  parameter int         AXI_4K     = 4096;

  // ---- helpers --------------------------------------------------------------
  // clog2 that never returns 0, so a width is always at least 1 bit
  function automatic int cw(input int n);
    cw = (n > 1) ? $clog2(n) : 1;
  endfunction

  // log2 of a power of two, 0 for 1
  function automatic int sh(input int n);
    sh = (n > 1) ? $clog2(n) : 0;
  endfunction

  function automatic int maxi(input int a, input int b);
    maxi = (a > b) ? a : b;
  endfunction

endpackage

`endif
