// ---------------------------------------------------------------------------
// Functional coverage.
//
//   dmac_coverage  - command shape, burst shape, AXI handshakes, interrupts.
//                    Instantiated in the testbench, on the DUT boundary.
//   dmac_arb_cov   - bound to every dmac_rr_arb, so read arbitration, write
//                    arbitration and interrupt arbitration are all measured.
//                    The "rotation" point is the evidence that scheduling
//                    really is round robin and not fixed priority.
//   dmac_fifo_cov  - bound to every dmac_fifo: occupancy including empty/full.
//   dmac_chan_cov  - bound to dmac_channels: how many channels run at once.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module dmac_coverage #(
  parameter int ADDR_WD       = 32,
  parameter int DATA_WD       = 32,
  parameter int LEN_WD        = 16,
  parameter int MAX_BURST_LEN = 16,
  parameter int CHANNEL_COUNT = 8,
  parameter int STRB_WD       = DATA_WD/8,
  parameter int OFF_WD        = (STRB_WD > 1) ? $clog2(STRB_WD) : 1,
  parameter int CH_WD         = (CHANNEL_COUNT > 1) ? $clog2(CHANNEL_COUNT) : 1
) (
  input wire                clk,
  input wire                rst_n,

  input wire                cmd_valid,
  input wire                cmd_ready,
  input wire  [ADDR_WD-1:0] cmd_src,
  input wire  [ADDR_WD-1:0] cmd_dst,
  input wire  [LEN_WD-1:0]  cmd_len,

  input wire                irq_valid,
  input wire                irq_ready,
  input wire  [CH_WD-1:0]   irq_ch,
  input wire                irq_err,

  input wire                alloc_valid,
  input wire  [CH_WD-1:0]   alloc_ch,

  input wire  [ADDR_WD-1:0] awaddr,
  input wire  [7:0]         awlen,
  input wire                awvalid,
  input wire                awready,
  input wire  [STRB_WD-1:0] wstrb,
  input wire                wlast,
  input wire                wvalid,
  input wire                wready,
  input wire  [1:0]         bresp,
  input wire                bvalid,
  input wire                bready,
  input wire  [ADDR_WD-1:0] araddr,
  input wire  [7:0]         arlen,
  input wire                arvalid,
  input wire                arready,
  input wire  [1:0]         rresp,
  input wire                rlast,
  input wire                rvalid,
  input wire                rready
);

  localparam int P4_BEATS = 4096/STRB_WD;

  wire cmd_fire = cmd_valid && cmd_ready;
  wire irq_fire = irq_valid && irq_ready;
  wire ar_fire  = arvalid  && arready;
  wire aw_fire  = awvalid  && awready;
  wire b_fire   = bvalid   && bready;
  wire r_fire   = rvalid   && rready;

  wire [OFF_WD-1:0] src_off = cmd_src[OFF_WD-1:0];
  wire [OFF_WD-1:0] dst_off = cmd_dst[OFF_WD-1:0];

  // does this burst finish exactly on a 4 KB page boundary?
  wire ar_hits_4k = (((araddr % 4096) / STRB_WD) + arlen + 1) == P4_BEATS;
  wire aw_hits_4k = (((awaddr % 4096) / STRB_WD) + awlen + 1) == P4_BEATS;

  // ---- command shape -------------------------------------------------------
  covergroup cg_cmd @(posedge clk iff (cmd_fire && rst_n));
    option.per_instance = 1;
    option.name         = "cg_cmd";

    cp_len : coverpoint cmd_len {
      bins one        = {1};
      bins tiny       = {[2:3]};
      bins sub_burst  = {[4:MAX_BURST_LEN-1]};
      bins exact      = {MAX_BURST_LEN};
      bins over       = {[MAX_BURST_LEN+1 : 4*MAX_BURST_LEN]};
      bins big        = {[4*MAX_BURST_LEN+1 : $]};
    }
    cp_soff : coverpoint src_off;                  // every byte offset
    cp_doff : coverpoint dst_off;
    cp_same : coverpoint (src_off == dst_off) {
      bins same_offset = {1};
      bins skewed      = {0};
    }
    x_off : cross cp_soff, cp_doff;
  endgroup

  // ---- burst shape ---------------------------------------------------------
  covergroup cg_burst @(posedge clk iff rst_n);
    option.per_instance = 1;
    option.name         = "cg_burst";

    cp_arlen : coverpoint arlen iff (ar_fire) {
      bins single = {0};
      bins mid    = {[1:MAX_BURST_LEN-2]};
      bins full   = {MAX_BURST_LEN-1};
    }
    cp_awlen : coverpoint awlen iff (aw_fire) {
      bins single = {0};
      bins mid    = {[1:MAX_BURST_LEN-2]};
      bins full   = {MAX_BURST_LEN-1};
    }
    cp_ar4k : coverpoint ar_hits_4k iff (ar_fire) {
      bins ends_on_page = {1};
      bins normal       = {0};
    }
    cp_aw4k : coverpoint aw_hits_4k iff (aw_fire) {
      bins ends_on_page = {1};
      bins normal       = {0};
    }
    // partial strobes only ever appear on the first and last beat of an
    // unaligned transfer, so this point is the unaligned-write evidence
    cp_wstrb : coverpoint wstrb iff (wvalid && wready) {
      bins all_bytes = {(1<<STRB_WD)-1};
      bins partial   = {[1 : (1<<STRB_WD)-2]};
    }
  endgroup

  // ---- AXI handshakes ------------------------------------------------------
  covergroup cg_axi @(posedge clk iff rst_n);
    option.per_instance = 1;
    option.name         = "cg_axi";

    cp_aw : coverpoint {awvalid, awready} {
      bins idle = {2'b00}; bins stall = {2'b10};
      bins ready_first = {2'b01}; bins xfer = {2'b11};
    }
    cp_w : coverpoint {wvalid, wready} {
      bins idle = {2'b00}; bins stall = {2'b10};
      bins ready_first = {2'b01}; bins xfer = {2'b11};
    }
    // BREADY is low only while no write burst is outstanding, and a legal
    // slave cannot send B then - so the master-stall encoding is unreachable
    cp_b : coverpoint {bvalid, bready} {
      bins idle = {2'b00};
      bins ready_first = {2'b01}; bins xfer = {2'b11};
      illegal_bins master_stall = {2'b10};
    }
    cp_ar : coverpoint {arvalid, arready} {
      bins idle = {2'b00}; bins stall = {2'b10};
      bins ready_first = {2'b01}; bins xfer = {2'b11};
    }
    // RREADY is tied high by design (the credit scheme guarantees room), so
    // the master-stall encoding must never appear
    cp_r : coverpoint {rvalid, rready} {
      bins idle = {2'b01}; bins xfer = {2'b11};
      illegal_bins master_stall = {2'b10};
    }
    cp_cmd_bp : coverpoint {cmd_valid, cmd_ready} {
      bins idle = {2'b00}; bins stall = {2'b10};
      bins ready_first = {2'b01}; bins xfer = {2'b11};
    }
    cp_bresp : coverpoint bresp iff (b_fire) {
      bins okay  = {2'b00};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_rresp : coverpoint rresp iff (r_fire) {
      bins okay  = {2'b00};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_wlast : coverpoint wlast iff (wvalid && wready);
    cp_rlast : coverpoint rlast iff (rvalid && rready);
  endgroup

  // ---- allocation and interrupts ------------------------------------------
  covergroup cg_irq @(posedge clk iff (irq_fire && rst_n));
    option.per_instance = 1;
    option.name         = "cg_irq";

    cp_ch  : coverpoint irq_ch;                    // every channel completes
    cp_err : coverpoint irq_err { bins clean = {0}; bins failed = {1}; }
    x_ch_err : cross cp_ch, cp_err;
  endgroup

  covergroup cg_alloc @(posedge clk iff (alloc_valid && rst_n));
    option.per_instance = 1;
    option.name         = "cg_alloc";
    cp_ch : coverpoint alloc_ch;                   // every channel gets used
  endgroup

  cg_cmd   u_cg_cmd   = new();
  cg_burst u_cg_burst = new();
  cg_axi   u_cg_axi   = new();
  cg_irq   u_cg_irq   = new();
  cg_alloc u_cg_alloc = new();

endmodule


// ---------------------------------------------------------------------------
module dmac_arb_cov #(
  parameter int N    = 8,
  parameter int ID_W = 3
) (
  input wire             clk,
  input wire             rst_n,
  input wire  [N-1:0]    req,
  input wire             upd,
  input wire  [ID_W-1:0] gnt_id,
  input wire             any
);

  logic [ID_W-1:0] prev_q;
  logic            seen_q;
  wire             fire = upd && any;

  // how far the grant moved since the previous one; a spread of non-zero
  // deltas is what distinguishes round robin from fixed priority
  wire [ID_W-1:0] delta = ID_W'((int'(gnt_id) - int'(prev_q) + N) % N);

  covergroup cg @(posedge clk iff (fire && rst_n));
    option.per_instance = 1;
    option.name         = "cg_arb";
    cp_id    : coverpoint gnt_id;
    cp_delta : coverpoint delta iff (seen_q);
    cp_nreq  : coverpoint $countones(req) {
      bins one  = {1};
      bins few  = {[2:3]};
      bins many = {[4:N]};
    }
  endgroup

  cg u_cg = new();

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_q <= '0;
      seen_q <= 1'b0;
    end else if (fire) begin
      prev_q <= gnt_id;
      seen_q <= 1'b1;
    end
  end

endmodule



// ---------------------------------------------------------------------------
module dmac_fifo_cov #(
  parameter int DEPTH  = 16,
  parameter int CNT_WD = 5
) (
  input wire               clk,
  input wire               rst_n,
  input wire               wr,
  input wire               rd,
  input wire [CNT_WD-1:0]  count
);

  covergroup cg @(posedge clk iff rst_n);
    option.per_instance = 1;
    option.name         = "cg_fifo";
    cp_occ : coverpoint count {
      bins empty = {0};
      bins low   = {[1 : DEPTH/2]};
      bins high  = {[DEPTH/2 + 1 : DEPTH-1]};
      bins full  = {DEPTH};
    }
    cp_op : coverpoint {wr, rd} {
      bins none = {2'b00}; bins push = {2'b10};
      bins pop  = {2'b01}; bins both = {2'b11};
    }
  endgroup

  cg u_cg = new();

endmodule



// ---------------------------------------------------------------------------
module dmac_chan_cov #(
  parameter int CHANNEL_COUNT = 8
) (
  input wire                     clk,
  input wire                     rst_n,
  input wire [CHANNEL_COUNT-1:0] free
);

  wire [31:0] busy = CHANNEL_COUNT - $countones(free);

  covergroup cg @(posedge clk iff rst_n);
    option.per_instance = 1;
    option.name         = "cg_chan";
    cp_busy : coverpoint busy {
      bins none = {0};
      bins n[]  = {[1:CHANNEL_COUNT]};   // one bin per concurrency level
    }
  endgroup

  cg u_cg = new();

endmodule


`default_nettype wire
