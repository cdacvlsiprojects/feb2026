// ---------------------------------------------------------------------------
// dmac_read_engine - arbiter + request generator + AR initiator + R handler
// + byte aligner, plus the credit accounting that keeps the whole thing from
// deadlocking.
//
// Credits: at AR issue the burst's PACKED beat count is added to pend[ch].
// Every packed beat pushed into the buffer subtracts one. Room is therefore
// DEPTH - count - pend, i.e. space is committed at request time, never at
// data-arrival time. Data can never come back with nowhere to go.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_read_engine
  import dmac_pkg::*;
#(
  parameter int ADDR_WD         = dmac_pkg::ADDR_WD,
  parameter int DATA_WD         = dmac_pkg::DATA_WD,
  parameter int LEN_WD          = dmac_pkg::LEN_WD,
  parameter int CHANNEL_COUNT   = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN   = dmac_pkg::MAX_BURST_LEN,
  parameter int ID_WD           = dmac_pkg::ID_WD,
  parameter int DATA_FIFO_DEPTH = dmac_pkg::DATA_FIFO_DEPTH,
  parameter int RD_OUTSTANDING  = dmac_pkg::RD_OUTSTANDING,
  parameter int BEAT_WD         = LEN_WD + 1,
  parameter int BLEN_WD         = dmac_pkg::cw(MAX_BURST_LEN) + 1,
  parameter int OFF_WD          = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD           = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int ROOM_WD         = $clog2(DATA_FIFO_DEPTH+1)
) (
  input  wire                                     clk,
  input  wire                                     rst_n,

  // ---- channel array ------------------------------------------------------
  input  wire  [CHANNEL_COUNT-1:0]                ch_load,
  input  wire  [CHANNEL_COUNT-1:0]                rd_valid,
  input  wire  [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   rd_addr,
  input  wire  [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   rd_beats,
  input  wire  [CHANNEL_COUNT-1:0]                rd_first,
  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0]    soff,
  output logic [CHANNEL_COUNT-1:0]                rd_gnt,
  output logic [BLEN_WD-1:0]                      rd_gnt_beats,

  // ---- data buffer --------------------------------------------------------
  input  wire  [CHANNEL_COUNT-1:0][ROOM_WD-1:0]   buf_count,
  output logic                                    push_valid,
  output logic [CH_WD-1:0]                        push_ch,
  output logic [DATA_WD-1:0]                      push_data,

  // ---- error report -------------------------------------------------------
  output logic                                    err_valid,
  output logic [CH_WD-1:0]                        err_ch,

  // ---- AXI read -----------------------------------------------------------
  output logic [ID_WD-1:0]                        m_axi_arid,
  output logic [ADDR_WD-1:0]                      m_axi_araddr,
  output logic [7:0]                              m_axi_arlen,
  output logic [2:0]                              m_axi_arsize,
  output logic [1:0]                              m_axi_arburst,
  output logic                                    m_axi_arvalid,
  input  wire                                     m_axi_arready,

  input  wire  [ID_WD-1:0]                        m_axi_rid,
  input  wire  [DATA_WD-1:0]                      m_axi_rdata,
  input  wire  [1:0]                              m_axi_rresp,
  input  wire                                     m_axi_rlast,
  input  wire                                     m_axi_rvalid,
  output logic                                    m_axi_rready
);

  localparam int TRK_WD = CH_WD + BLEN_WD;

  // ---- credits -------------------------------------------------------------
  logic [CHANNEL_COUNT-1:0][ROOM_WD-1:0] pend_q, pend_d;
  logic [CHANNEL_COUNT-1:0][ROOM_WD-1:0] room;

  always_comb begin
    for (int i = 0; i < CHANNEL_COUNT; i++) begin
      room[i] = ROOM_WD'(DATA_FIFO_DEPTH) - buf_count[i] - pend_q[i];
    end
  end

  // ---- request generation --------------------------------------------------
  logic [CHANNEL_COUNT-1:0] gate, gnt;
  logic [CH_WD-1:0]         gnt_id;
  logic                     any;

  logic [ADDR_WD-1:0] req_addr;
  logic [7:0]         req_len;
  logic [BLEN_WD-1:0] req_beats, req_packed;
  logic               req_swallow;

  logic trk_full, trk_empty, trk_rd;
  logic req_valid, req_ready, accept;

  dmac_read_req_gen #(
    .ADDR_WD       (ADDR_WD),
    .DATA_WD       (DATA_WD),
    .LEN_WD        (LEN_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .MAX_BURST_LEN (MAX_BURST_LEN),
    .BEAT_WD       (BEAT_WD),
    .BLEN_WD       (BLEN_WD),
    .OFF_WD        (OFF_WD),
    .CH_WD         (CH_WD),
    .ROOM_WD       (ROOM_WD)
  ) u_req_gen (
    .rd_valid    (rd_valid),
    .rd_addr     (rd_addr),
    .rd_beats    (rd_beats),
    .rd_first    (rd_first),
    .soff        (soff),
    .room        (room),
    .gate        (gate),
    .gnt_id      (gnt_id),
    .req_addr    (req_addr),
    .req_len     (req_len),
    .req_beats   (req_beats),
    .req_packed  (req_packed),
    .req_swallow (req_swallow)
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

  assign req_valid    = any && !trk_full;
  assign accept       = req_valid && req_ready;
  assign rd_gnt       = accept ? gnt : '0;
  assign rd_gnt_beats = req_beats;

  dmac_read_initiator #(
    .ADDR_WD (ADDR_WD),
    .DATA_WD (DATA_WD),
    .ID_WD   (ID_WD)
  ) u_ini (
    .clk           (clk),
    .rst_n         (rst_n),
    .req_valid     (req_valid),
    .req_ready     (req_ready),
    .req_addr      (req_addr),
    .req_len       (req_len),
    .m_axi_arid    (m_axi_arid),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready)
  );

  // ---- in-flight queue -----------------------------------------------------
  logic [CH_WD-1:0]   trk_ch;
  logic [BLEN_WD-1:0] trk_beats;
  logic [TRK_WD-1:0]  trk_dout;

  dmac_fifo #(
    .WIDTH (TRK_WD),
    .DEPTH (RD_OUTSTANDING)
  ) u_trk (
    .clk   (clk),
    .rst_n (rst_n),
    .wr    (accept),
    .din   ({gnt_id, req_beats}),
    .full  (trk_full),
    .rd    (trk_rd),
    .dout  (trk_dout),
    .empty (trk_empty),
    .count ()
  );

  assign {trk_ch, trk_beats} = trk_dout;

  // ---- R handler and aligner ----------------------------------------------
  logic               raw_valid;
  logic [DATA_WD-1:0] raw_data;
  logic [CH_WD-1:0]   raw_ch;

  dmac_read_handler #(
    .DATA_WD       (DATA_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .MAX_BURST_LEN (MAX_BURST_LEN),
    .ID_WD         (ID_WD),
    .CH_WD         (CH_WD),
    .BLEN_WD       (BLEN_WD)
  ) u_hdl (
    .clk          (clk),
    .rst_n        (rst_n),
    .trk_empty    (trk_empty),
    .trk_ch       (trk_ch),
    .trk_beats    (trk_beats),
    .trk_rd       (trk_rd),
    .m_axi_rid    (m_axi_rid),
    .m_axi_rdata  (m_axi_rdata),
    .m_axi_rresp  (m_axi_rresp),
    .m_axi_rlast  (m_axi_rlast),
    .m_axi_rvalid (m_axi_rvalid),
    .m_axi_rready (m_axi_rready),
    .raw_valid    (raw_valid),
    .raw_data     (raw_data),
    .raw_ch       (raw_ch),
    .err_valid    (err_valid),
    .err_ch       (err_ch)
  );

  dmac_rd_align #(
    .DATA_WD       (DATA_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .OFF_WD        (OFF_WD),
    .CH_WD         (CH_WD)
  ) u_align (
    .clk       (clk),
    .rst_n     (rst_n),
    .ch_load   (ch_load),
    .soff      (soff),
    .in_valid  (raw_valid),
    .in_data   (raw_data),
    .in_ch     (raw_ch),
    .out_valid (push_valid),
    .out_data  (push_data),
    .out_ch    (push_ch)
  );

  // ---- credit bookkeeping --------------------------------------------------
  always_comb begin
    pend_d = pend_q;
    if (accept)     pend_d[gnt_id]  = pend_d[gnt_id]  + ROOM_WD'(req_packed);
    if (push_valid) pend_d[push_ch] = pend_d[push_ch] - ROOM_WD'(1);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) pend_q <= '0;
    else        pend_q <= pend_d;
  end

  wire _unused = &{1'b0, req_swallow};

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(accept && (req_beats == '0)))
      else $fatal(1, "read_engine: granted a zero-beat burst");
    for (int i = 0; i < CHANNEL_COUNT; i++) begin
      assert (buf_count[i] + pend_q[i] <= ROOM_WD'(DATA_FIFO_DEPTH))
        else $fatal(1, "read_engine: channel %0d over-committed", i);
    end
  end
`endif

endmodule

`default_nettype wire
