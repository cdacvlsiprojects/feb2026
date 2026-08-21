// ---------------------------------------------------------------------------
// dmac_channel_ctrl - one DMA channel.
//
// Holds the read-side pointer/counter and the write-side pointer/counter
// independently, because with unaligned addresses the two sides move a
// different number of beats:
//
//   soff = src[OFF-1:0]        read beats  = len + (soff != 0)
//   doff = dst[OFF-1:0]        write beats = len + (doff != 0)
//
// Addresses handed to the AXI engines are always beat-aligned; the byte
// offsets are handled by dmac_rd_align / dmac_wr_align and WSTRB.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_channel_ctrl
  import dmac_pkg::*;
#(
  parameter int ADDR_WD  = dmac_pkg::ADDR_WD,
  parameter int DATA_WD  = dmac_pkg::DATA_WD,
  parameter int LEN_WD   = dmac_pkg::LEN_WD,
  parameter int BEAT_WD  = LEN_WD + 1,
  parameter int BLEN_WD  = dmac_pkg::cw(dmac_pkg::MAX_BURST_LEN) + 1,
  parameter int OFF_WD   = dmac_pkg::cw(DATA_WD/8)
) (
  input  wire                clk,
  input  wire                rst_n,

  // ---- allocation ---------------------------------------------------------
  input  wire                load,
  input  wire  [ADDR_WD-1:0] load_src,
  input  wire  [ADDR_WD-1:0] load_dst,
  input  wire  [LEN_WD-1:0]  load_len,     // beats, must be >= 1
  output logic               free,

  output logic [OFF_WD-1:0]  soff,
  output logic [OFF_WD-1:0]  doff,

  // ---- read side ----------------------------------------------------------
  output logic               rd_valid,
  output logic [ADDR_WD-1:0] rd_addr,      // beat aligned
  output logic [BEAT_WD-1:0] rd_beats,
  output logic               rd_first,     // no read beat granted yet
  input  wire                rd_gnt,
  input  wire  [BLEN_WD-1:0] rd_gnt_beats,

  // ---- write side ---------------------------------------------------------
  output logic               wr_valid,
  output logic [ADDR_WD-1:0] wr_addr,      // beat aligned
  output logic [BEAT_WD-1:0] wr_beats,
  output logic               wr_first,     // no write beat granted yet
  input  wire                wr_gnt,
  input  wire  [BLEN_WD-1:0] wr_gnt_beats,

  // ---- completion and errors ---------------------------------------------
  input  wire                done_valid,
  input  wire  [BLEN_WD-1:0] done_beats,
  input  wire                done_err,
  input  wire                rd_err,

  // ---- interrupt ----------------------------------------------------------
  output logic               irq_valid,
  output logic               irq_err,
  input  wire                irq_ready
);

  localparam int STRB_WD = DATA_WD/8;
  localparam int SHFT    = dmac_pkg::sh(STRB_WD);

  typedef enum logic [1:0] { IDLE, RUN, DONE } state_e;

  state_e             state_q, state_d;
  logic [ADDR_WD-1:0] raddr_q, raddr_d;
  logic [ADDR_WD-1:0] waddr_q, waddr_d;
  logic [BEAT_WD-1:0] rbeat_q, rbeat_d;
  logic [BEAT_WD-1:0] wbeat_q, wbeat_d;
  logic [BEAT_WD-1:0] wout_q,  wout_d;    // write beats issued, not yet B'd
  logic [OFF_WD-1:0]  soff_q,  soff_d;
  logic [OFF_WD-1:0]  doff_q,  doff_d;
  logic               rfirst_q, rfirst_d;
  logic               wfirst_q, wfirst_d;
  logic               err_q,    err_d;

  // offsets of the incoming command; always zero when a beat is one byte
  wire [OFF_WD-1:0] new_soff = (STRB_WD > 1) ? load_src[OFF_WD-1:0] : '0;
  wire [OFF_WD-1:0] new_doff = (STRB_WD > 1) ? load_dst[OFF_WD-1:0] : '0;

  wire [ADDR_WD-1:0] align_mask = ~ADDR_WD'(STRB_WD-1);

  assign free      = (state_q == IDLE);
  assign soff      = soff_q;
  assign doff      = doff_q;

  assign rd_valid  = (state_q == RUN) && (rbeat_q != '0);
  assign rd_addr   = raddr_q;
  assign rd_beats  = rbeat_q;
  assign rd_first  = rfirst_q;

  assign wr_valid  = (state_q == RUN) && (wbeat_q != '0);
  assign wr_addr   = waddr_q;
  assign wr_beats  = wbeat_q;
  assign wr_first  = wfirst_q;

  assign irq_valid = (state_q == DONE);
  assign irq_err   = err_q;

  always_comb begin
    state_d  = state_q;
    raddr_d  = raddr_q;
    waddr_d  = waddr_q;
    rbeat_d  = rbeat_q;
    wbeat_d  = wbeat_q;
    wout_d   = wout_q;
    soff_d   = soff_q;
    doff_d   = doff_q;
    rfirst_d = rfirst_q;
    wfirst_d = wfirst_q;
    err_d    = err_q;

    unique case (state_q)

      IDLE: begin
        if (load) begin
          soff_d   = new_soff;
          doff_d   = new_doff;
          raddr_d  = load_src & align_mask;
          waddr_d  = load_dst & align_mask;
          rbeat_d  = BEAT_WD'(load_len) + BEAT_WD'(new_soff != '0);
          wbeat_d  = BEAT_WD'(load_len) + BEAT_WD'(new_doff != '0);
          wout_d   = '0;
          rfirst_d = 1'b1;
          wfirst_d = 1'b1;
          err_d    = 1'b0;
          state_d  = RUN;
        end
      end

      RUN: begin
        if (rd_gnt) begin
          raddr_d  = raddr_q + (ADDR_WD'(rd_gnt_beats) << SHFT);
          rbeat_d  = rbeat_q - BEAT_WD'(rd_gnt_beats);
          rfirst_d = 1'b0;
        end
        if (wr_gnt) begin
          waddr_d  = waddr_q + (ADDR_WD'(wr_gnt_beats) << SHFT);
          wbeat_d  = wbeat_q - BEAT_WD'(wr_gnt_beats);
          wfirst_d = 1'b0;
          wout_d   = wout_d + BEAT_WD'(wr_gnt_beats);
        end
        if (done_valid) wout_d = wout_d - BEAT_WD'(done_beats);
        if (done_err || rd_err) err_d = 1'b1;

        if ((rbeat_d == '0) && (wbeat_d == '0) && (wout_d == '0)) state_d = DONE;
      end

      DONE: begin
        if (irq_ready) state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= IDLE;
      raddr_q  <= '0;
      waddr_q  <= '0;
      rbeat_q  <= '0;
      wbeat_q  <= '0;
      wout_q   <= '0;
      soff_q   <= '0;
      doff_q   <= '0;
      rfirst_q <= 1'b1;
      wfirst_q <= 1'b1;
      err_q    <= 1'b0;
    end else begin
      state_q  <= state_d;
      raddr_q  <= raddr_d;
      waddr_q  <= waddr_d;
      rbeat_q  <= rbeat_d;
      wbeat_q  <= wbeat_d;
      wout_q   <= wout_d;
      soff_q   <= soff_d;
      doff_q   <= doff_d;
      rfirst_q <= rfirst_d;
      wfirst_q <= wfirst_d;
      err_q    <= err_d;
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(load && !free)) else $fatal(1, "channel_ctrl: load while busy");
    assert (!(load && (load_len == '0))) else $fatal(1, "channel_ctrl: zero length");
  end
`endif

endmodule

`default_nettype wire
