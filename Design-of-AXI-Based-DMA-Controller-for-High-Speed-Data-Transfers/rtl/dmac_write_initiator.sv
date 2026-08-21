// ---------------------------------------------------------------------------
// dmac_write_initiator - drives AW then W for one burst at a time.
//
// The request is latched before AWVALID rises, so the address channel payload
// is stable while AWVALID is held. W beats follow the accepted AW; a new burst
// is not accepted until WLAST has gone out, which keeps the aligner's residue
// bookkeeping trivially in order.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_write_initiator
  import dmac_pkg::*;
#(
  parameter int ADDR_WD       = dmac_pkg::ADDR_WD,
  parameter int DATA_WD       = dmac_pkg::DATA_WD,
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN = dmac_pkg::MAX_BURST_LEN,
  parameter int ID_WD         = dmac_pkg::ID_WD,
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int BLEN_WD       = dmac_pkg::cw(MAX_BURST_LEN) + 1,
  parameter int STRB_WD       = DATA_WD/8
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                req_valid,
  output logic               req_ready,
  input  wire  [ADDR_WD-1:0] req_addr,
  input  wire  [7:0]         req_len,
  input  wire  [BLEN_WD-1:0] req_beats,
  input  wire  [CH_WD-1:0]   req_ch,
  input  wire                req_first,
  input  wire                req_final,

  // in-flight queue
  input  wire                trk_full,
  output logic               trk_wr,
  output logic [CH_WD-1:0]   trk_ch,
  output logic [BLEN_WD-1:0] trk_beats,

  // aligner control
  output logic [CH_WD-1:0]   al_ch,
  output logic               al_beat,
  output logic               al_first,
  output logic               al_last,
  input  wire  [DATA_WD-1:0] al_wdata,
  input  wire  [STRB_WD-1:0] al_wstrb,

  // AXI write address
  output logic [ID_WD-1:0]   m_axi_awid,
  output logic [ADDR_WD-1:0] m_axi_awaddr,
  output logic [7:0]         m_axi_awlen,
  output logic [2:0]         m_axi_awsize,
  output logic [1:0]         m_axi_awburst,
  output logic               m_axi_awvalid,
  input  wire                m_axi_awready,

  // AXI write data
  output logic [DATA_WD-1:0] m_axi_wdata,
  output logic [STRB_WD-1:0] m_axi_wstrb,
  output logic               m_axi_wlast,
  output logic               m_axi_wvalid,
  input  wire                m_axi_wready
);

  typedef enum logic [1:0] { S_IDLE, S_AW, S_W } state_e;

  state_e             state_q;
  logic [ADDR_WD-1:0] addr_q;
  logic [7:0]         len_q;
  logic [BLEN_WD-1:0] beats_q;
  logic [CH_WD-1:0]   ch_q;
  logic               first_q, final_q;
  logic [7:0]         beat_q;

  wire accept  = req_valid && req_ready;
  wire w_fire  = m_axi_wvalid && m_axi_wready;
  wire w_last  = (beat_q == len_q);

  assign req_ready = (state_q == S_IDLE) && !trk_full;

  assign trk_wr    = accept;
  assign trk_ch    = req_ch;
  assign trk_beats = req_beats;

  assign m_axi_awid    = '0;                      // single ID, see DD-003
  assign m_axi_awaddr  = addr_q;
  assign m_axi_awlen   = len_q;
  assign m_axi_awsize  = 3'(dmac_pkg::sh(STRB_WD));
  assign m_axi_awburst = dmac_pkg::BURST_INCR;
  assign m_axi_awvalid = (state_q == S_AW);

  assign m_axi_wvalid  = (state_q == S_W);
  assign m_axi_wlast   = w_last;
  assign m_axi_wdata   = al_wdata;
  assign m_axi_wstrb   = al_wstrb;

  assign al_ch    = ch_q;
  assign al_beat  = w_fire;
  assign al_first = first_q && (beat_q == '0);
  assign al_last  = final_q && w_last;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      addr_q  <= '0;
      len_q   <= '0;
      beats_q <= '0;
      ch_q    <= '0;
      first_q <= 1'b0;
      final_q <= 1'b0;
      beat_q  <= '0;
    end else begin
      unique case (state_q)

        S_IDLE: if (accept) begin
          addr_q  <= req_addr;
          len_q   <= req_len;
          beats_q <= req_beats;
          ch_q    <= req_ch;
          first_q <= req_first;
          final_q <= req_final;
          beat_q  <= '0;
          state_q <= S_AW;
        end

        S_AW: if (m_axi_awready) state_q <= S_W;

        S_W: if (w_fire) begin
          if (w_last) state_q <= S_IDLE;
          else        beat_q  <= beat_q + 1'b1;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  wire _unused = &{1'b0, beats_q};

endmodule

`default_nettype wire
