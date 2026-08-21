// ---------------------------------------------------------------------------
// dmac_write_handler - consumes the B channel and retires beats against the
// owning channel. Which channel a response belongs to comes from the in-flight
// queue, which is in AW issue order (single ID, so B comes back in order too).
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_write_handler
  import dmac_pkg::*;
#(
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN = dmac_pkg::MAX_BURST_LEN,
  parameter int ID_WD         = dmac_pkg::ID_WD,
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int BLEN_WD       = dmac_pkg::cw(MAX_BURST_LEN) + 1
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                trk_empty,
  input  wire  [CH_WD-1:0]   trk_ch,
  input  wire  [BLEN_WD-1:0] trk_beats,
  output logic               trk_rd,

  input  wire  [ID_WD-1:0]   m_axi_bid,
  input  wire  [1:0]         m_axi_bresp,
  input  wire                m_axi_bvalid,
  output logic               m_axi_bready,

  output logic               done_valid,
  output logic [CH_WD-1:0]   done_ch,
  output logic [BLEN_WD-1:0] done_beats,
  output logic               done_err
);

  assign m_axi_bready = !trk_empty;

  wire fire = m_axi_bvalid && m_axi_bready;

  assign trk_rd     = fire;
  assign done_valid = fire;
  assign done_ch    = trk_ch;
  assign done_beats = trk_beats;
  assign done_err   = m_axi_bresp[1];

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(m_axi_bvalid && trk_empty))
      else $fatal(1, "write_handler: B response with no burst in flight");
    assert (!(m_axi_bvalid && (m_axi_bid != '0)))
      else $fatal(1, "write_handler: unexpected BID %0h", m_axi_bid);
  end
`endif

endmodule

`default_nettype wire
