// ---------------------------------------------------------------------------
// dmac_write_engine - arbiter + request generator + aligner + AW/W initiator
// + B handler.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_write_engine
  import dmac_pkg::*;
#(
  parameter int ADDR_WD         = dmac_pkg::ADDR_WD,
  parameter int DATA_WD         = dmac_pkg::DATA_WD,
  parameter int LEN_WD          = dmac_pkg::LEN_WD,
  parameter int CHANNEL_COUNT   = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN   = dmac_pkg::MAX_BURST_LEN,
  parameter int ID_WD           = dmac_pkg::ID_WD,
  parameter int DATA_FIFO_DEPTH = dmac_pkg::DATA_FIFO_DEPTH,
  parameter int WR_OUTSTANDING  = dmac_pkg::WR_OUTSTANDING,
  parameter int BEAT_WD         = LEN_WD + 1,
  parameter int BLEN_WD         = dmac_pkg::cw(MAX_BURST_LEN) + 1,
  parameter int OFF_WD          = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD           = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int ROOM_WD         = $clog2(DATA_FIFO_DEPTH+1),
  parameter int STRB_WD         = DATA_WD/8
) (
  input  wire                                     clk,
  input  wire                                     rst_n,

  // ---- channel array ------------------------------------------------------
  input  wire  [CHANNEL_COUNT-1:0]                wr_valid,
  input  wire  [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   wr_addr,
  input  wire  [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   wr_beats,
  input  wire  [CHANNEL_COUNT-1:0]                wr_first,
  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0]    doff,
  output logic [CHANNEL_COUNT-1:0]                wr_gnt,
  output logic [BLEN_WD-1:0]                      wr_gnt_beats,

  // ---- data buffer --------------------------------------------------------
  input  wire  [CHANNEL_COUNT-1:0][ROOM_WD-1:0]   buf_count,
  input  wire  [CHANNEL_COUNT-1:0][DATA_WD-1:0]   buf_dout,
  output logic [CHANNEL_COUNT-1:0]                buf_rd,

  // ---- completion ---------------------------------------------------------
  output logic                                    done_valid,
  output logic [CH_WD-1:0]                        done_ch,
  output logic [BLEN_WD-1:0]                      done_beats,
  output logic                                    done_err,

  // ---- AXI write ----------------------------------------------------------
  output logic [ID_WD-1:0]                        m_axi_awid,
  output logic [ADDR_WD-1:0]                      m_axi_awaddr,
  output logic [7:0]                              m_axi_awlen,
  output logic [2:0]                              m_axi_awsize,
  output logic [1:0]                              m_axi_awburst,
  output logic                                    m_axi_awvalid,
  input  wire                                     m_axi_awready,

  output logic [DATA_WD-1:0]                      m_axi_wdata,
  output logic [STRB_WD-1:0]                      m_axi_wstrb,
  output logic                                    m_axi_wlast,
  output logic                                    m_axi_wvalid,
  input  wire                                     m_axi_wready,

  input  wire  [ID_WD-1:0]                        m_axi_bid,
  input  wire  [1:0]                              m_axi_bresp,
  input  wire                                     m_axi_bvalid,
  output logic                                    m_axi_bready
);

  localparam int TRK_WD = CH_WD + BLEN_WD;

  logic [CHANNEL_COUNT-1:0] gate, gnt;
  logic [CH_WD-1:0]         gnt_id;
  logic                     any;

  logic [ADDR_WD-1:0] req_addr;
  logic [7:0]         req_len;
  logic [BLEN_WD-1:0] req_beats;
  logic               req_final;
  logic               req_valid, req_ready, accept;

  dmac_write_req_gen #(
    .ADDR_WD         (ADDR_WD),
    .DATA_WD         (DATA_WD),
    .LEN_WD          (LEN_WD),
    .CHANNEL_COUNT   (CHANNEL_COUNT),
    .MAX_BURST_LEN   (MAX_BURST_LEN),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH),
    .BEAT_WD         (BEAT_WD),
    .BLEN_WD         (BLEN_WD),
    .OFF_WD          (OFF_WD),
    .CH_WD           (CH_WD),
    .ROOM_WD         (ROOM_WD)
  ) u_req_gen (
    .wr_valid  (wr_valid),
    .wr_addr   (wr_addr),
    .wr_beats  (wr_beats),
    .doff      (doff),
    .avail     (buf_count),
    .gate      (gate),
    .gnt_id    (gnt_id),
    .req_addr  (req_addr),
    .req_len   (req_len),
    .req_beats (req_beats),
    .req_final (req_final)
  );

  dmac_rr_arb #(
    .N    (CHANNEL_COUNT),
    .ID_W (CH_WD)
  ) u_arb (
    .clk    (clk),
    .rst_n  (rst_n),
    .req    (gate),
    .upd    (accept),
    .gnt    (gnt),
    .gnt_id (gnt_id),
    .any    (any)
  );

  assign req_valid    = any;
  assign accept       = req_valid && req_ready;
  assign wr_gnt       = accept ? gnt : '0;
  assign wr_gnt_beats = req_beats;

  // ---- aligner -------------------------------------------------------------
  logic [CH_WD-1:0]   al_ch;
  logic               al_beat, al_first, al_last, al_rd;
  logic [DATA_WD-1:0] al_wdata;
  logic [STRB_WD-1:0] al_wstrb;

  dmac_wr_align #(
    .DATA_WD       (DATA_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .OFF_WD        (OFF_WD),
    .CH_WD         (CH_WD),
    .STRB_WD       (STRB_WD)
  ) u_align (
    .clk        (clk),
    .doff       (doff),
    .ch         (al_ch),
    .beat_valid (al_beat),
    .beat_first (al_first),
    .beat_last  (al_last),
    .fifo_data  (buf_dout[al_ch]),
    .fifo_rd    (al_rd),
    .wdata      (al_wdata),
    .wstrb      (al_wstrb)
  );

  always_comb begin
    buf_rd        = '0;
    buf_rd[al_ch] = al_rd;
  end

  // ---- in-flight queue -----------------------------------------------------
  logic               trk_full, trk_empty, trk_wr, trk_rd;
  logic [CH_WD-1:0]   trk_wch, trk_rch;
  logic [BLEN_WD-1:0] trk_wbeats, trk_rbeats;
  logic [TRK_WD-1:0]  trk_dout;

  dmac_fifo #(
    .WIDTH (TRK_WD),
    .DEPTH (WR_OUTSTANDING)
  ) u_trk (
    .clk   (clk),
    .rst_n (rst_n),
    .wr    (trk_wr),
    .din   ({trk_wch, trk_wbeats}),
    .full  (trk_full),
    .rd    (trk_rd),
    .dout  (trk_dout),
    .empty (trk_empty),
    .count ()
  );

  assign {trk_rch, trk_rbeats} = trk_dout;

  dmac_write_initiator #(
    .ADDR_WD       (ADDR_WD),
    .DATA_WD       (DATA_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .MAX_BURST_LEN (MAX_BURST_LEN),
    .ID_WD         (ID_WD),
    .CH_WD         (CH_WD),
    .BLEN_WD       (BLEN_WD),
    .STRB_WD       (STRB_WD)
  ) u_ini (
    .clk           (clk),
    .rst_n         (rst_n),
    .req_valid     (req_valid),
    .req_ready     (req_ready),
    .req_addr      (req_addr),
    .req_len       (req_len),
    .req_beats     (req_beats),
    .req_ch        (gnt_id),
    .req_first     (wr_first[gnt_id]),
    .req_final     (req_final),
    .trk_full      (trk_full),
    .trk_wr        (trk_wr),
    .trk_ch        (trk_wch),
    .trk_beats     (trk_wbeats),
    .al_ch         (al_ch),
    .al_beat       (al_beat),
    .al_first      (al_first),
    .al_last       (al_last),
    .al_wdata      (al_wdata),
    .al_wstrb      (al_wstrb),
    .m_axi_awid    (m_axi_awid),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready)
  );

  dmac_write_handler #(
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .MAX_BURST_LEN (MAX_BURST_LEN),
    .ID_WD         (ID_WD),
    .CH_WD         (CH_WD),
    .BLEN_WD       (BLEN_WD)
  ) u_hdl (
    .clk          (clk),
    .rst_n        (rst_n),
    .trk_empty    (trk_empty),
    .trk_ch       (trk_rch),
    .trk_beats    (trk_rbeats),
    .trk_rd       (trk_rd),
    .m_axi_bid    (m_axi_bid),
    .m_axi_bresp  (m_axi_bresp),
    .m_axi_bvalid (m_axi_bvalid),
    .m_axi_bready (m_axi_bready),
    .done_valid   (done_valid),
    .done_ch      (done_ch),
    .done_beats   (done_beats),
    .done_err     (done_err)
  );

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(accept && (req_beats == '0)))
      else $fatal(1, "write_engine: granted a zero-beat burst");
    assert (!(al_rd && (buf_count[al_ch] == '0)))
      else $fatal(1, "write_engine: popped an empty buffer on channel %0d", al_ch);
  end
`endif

endmodule

`default_nettype wire
