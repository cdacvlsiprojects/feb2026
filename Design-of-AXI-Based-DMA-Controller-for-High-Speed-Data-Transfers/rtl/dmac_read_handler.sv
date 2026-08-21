// ---------------------------------------------------------------------------
// dmac_read_handler - consumes the R channel.
//
// Which channel a returning beat belongs to comes from the in-flight queue,
// popped on RLAST. That is sound because every AR uses the same ID, so AXI
// guarantees read data comes back in the order it was requested.
//
// RREADY is tied high: dmac_read_req_gen only issues a burst after committing
// room for it in the destination channel's data buffer, so a returning beat
// can never find the buffer full.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_read_handler
  import dmac_pkg::*;
#(
  parameter int DATA_WD       = dmac_pkg::DATA_WD,
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN = dmac_pkg::MAX_BURST_LEN,
  parameter int ID_WD         = dmac_pkg::ID_WD,
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int BLEN_WD       = dmac_pkg::cw(MAX_BURST_LEN) + 1
) (
  input  wire                clk,
  input  wire                rst_n,

  // in-flight queue head
  input  wire                trk_empty,
  input  wire  [CH_WD-1:0]   trk_ch,
  input  wire  [BLEN_WD-1:0] trk_beats,
  output logic               trk_rd,

  // AXI R
  input  wire  [ID_WD-1:0]   m_axi_rid,
  input  wire  [DATA_WD-1:0] m_axi_rdata,
  input  wire  [1:0]         m_axi_rresp,
  input  wire                m_axi_rlast,
  input  wire                m_axi_rvalid,
  output logic               m_axi_rready,

  // raw beat out, to the aligner
  output logic               raw_valid,
  output logic [DATA_WD-1:0] raw_data,
  output logic [CH_WD-1:0]   raw_ch,

  // error report
  output logic               err_valid,
  output logic [CH_WD-1:0]   err_ch
);

  logic [BLEN_WD-1:0] beat_q;   // beats already taken from the head burst

  wire beat = m_axi_rvalid && m_axi_rready;

  assign m_axi_rready = 1'b1;

  assign raw_valid = m_axi_rvalid;
  assign raw_data  = m_axi_rdata;
  assign raw_ch    = trk_ch;

  assign err_valid = m_axi_rvalid && m_axi_rresp[1];
  assign err_ch    = trk_ch;

  assign trk_rd    = beat && m_axi_rlast;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                     beat_q <= '0;
    else if (beat && m_axi_rlast)   beat_q <= '0;
    else if (beat)                  beat_q <= beat_q + 1'b1;
  end

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(m_axi_rvalid && trk_empty))
      else $fatal(1, "read_handler: R data with no burst in flight");
    assert (!(beat && m_axi_rlast && (beat_q + 1'b1 != trk_beats)))
      else $fatal(1, "read_handler: RLAST on beat %0d, expected %0d",
                  beat_q + 1'b1, trk_beats);
    assert (!(m_axi_rvalid && (m_axi_rid != '0)))
      else $fatal(1, "read_handler: unexpected RID %0h", m_axi_rid);
  end
`endif

endmodule

`default_nettype wire
