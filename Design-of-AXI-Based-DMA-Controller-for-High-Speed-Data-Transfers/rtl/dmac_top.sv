// ---------------------------------------------------------------------------
// dmac_top - AXI4 multi-channel DMA controller.
//
//   cmd {src, dst, len}  ->  command buffer  ->  channel allocation (RR)
//                        ->  read engine  ->  per-channel data buffer
//                        ->  write engine ->  irq {ch, err}
//
// len is in BEATS. src and dst may sit at any byte offset; the aligners and
// WSTRB handle the rest. All AXI addresses leaving this block are beat
// aligned, INCR only, single ID.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_top
  import dmac_pkg::*;
#(
  parameter int ADDR_WD         = dmac_pkg::ADDR_WD,
  parameter int DATA_WD         = dmac_pkg::DATA_WD,
  parameter int CHANNEL_COUNT   = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN   = dmac_pkg::MAX_BURST_LEN,
  parameter int LEN_WD          = dmac_pkg::LEN_WD,
  parameter int ID_WD           = dmac_pkg::ID_WD,
  parameter int CMD_FIFO_DEPTH  = dmac_pkg::CMD_FIFO_DEPTH,
  parameter int DATA_FIFO_DEPTH = dmac_pkg::DATA_FIFO_DEPTH,
  parameter int RD_OUTSTANDING  = dmac_pkg::RD_OUTSTANDING,
  parameter int WR_OUTSTANDING  = dmac_pkg::WR_OUTSTANDING,
  parameter int STRB_WD         = DATA_WD/8,
  parameter int CH_WD           = dmac_pkg::cw(CHANNEL_COUNT)
) (
  input  wire                clk,
  input  wire                rst_n,

  // ---- CPU command port ---------------------------------------------------
  input  wire                cmd_valid,
  output logic               cmd_ready,
  input  wire  [ADDR_WD-1:0] cmd_src,
  input  wire  [ADDR_WD-1:0] cmd_dst,
  input  wire  [LEN_WD-1:0]  cmd_len,      // BEATS, >= 1

  // ---- allocation observability ------------------------------------------
  output logic               alloc_valid,
  output logic [CH_WD-1:0]   alloc_ch,

  // ---- interrupt to CPU ---------------------------------------------------
  output logic               irq_valid,
  input  wire                irq_ready,
  output logic [CH_WD-1:0]   irq_ch,
  output logic               irq_err,

  // ---- AXI4 master : write address ---------------------------------------
  output logic [ID_WD-1:0]   m_axi_awid,
  output logic [ADDR_WD-1:0] m_axi_awaddr,
  output logic [7:0]         m_axi_awlen,
  output logic [2:0]         m_axi_awsize,
  output logic [1:0]         m_axi_awburst,
  output logic               m_axi_awvalid,
  input  wire                m_axi_awready,

  // ---- AXI4 master : write data ------------------------------------------
  output logic [DATA_WD-1:0] m_axi_wdata,
  output logic [STRB_WD-1:0] m_axi_wstrb,
  output logic               m_axi_wlast,
  output logic               m_axi_wvalid,
  input  wire                m_axi_wready,

  // ---- AXI4 master : write response --------------------------------------
  input  wire  [ID_WD-1:0]   m_axi_bid,
  input  wire  [1:0]         m_axi_bresp,
  input  wire                m_axi_bvalid,
  output logic               m_axi_bready,

  // ---- AXI4 master : read address ----------------------------------------
  output logic [ID_WD-1:0]   m_axi_arid,
  output logic [ADDR_WD-1:0] m_axi_araddr,
  output logic [7:0]         m_axi_arlen,
  output logic [2:0]         m_axi_arsize,
  output logic [1:0]         m_axi_arburst,
  output logic               m_axi_arvalid,
  input  wire                m_axi_arready,

  // ---- AXI4 master : read data -------------------------------------------
  input  wire  [ID_WD-1:0]   m_axi_rid,
  input  wire  [DATA_WD-1:0] m_axi_rdata,
  input  wire  [1:0]         m_axi_rresp,
  input  wire                m_axi_rlast,
  input  wire                m_axi_rvalid,
  output logic               m_axi_rready
);

  localparam int BEAT_WD = LEN_WD + 1;
  localparam int BLEN_WD = dmac_pkg::cw(MAX_BURST_LEN) + 1;
  localparam int OFF_WD  = dmac_pkg::cw(STRB_WD);
  localparam int ROOM_WD = $clog2(DATA_FIFO_DEPTH+1);

  // ---- command buffer <-> requester ---------------------------------------
  logic               cmd_full, cmd_empty, cmd_rd;
  logic [ADDR_WD-1:0] q_src, q_dst;
  logic [LEN_WD-1:0]  q_len;

  // ---- channels ------------------------------------------------------------
  logic [CHANNEL_COUNT-1:0]              ch_free, ch_load;
  logic [CHANNEL_COUNT-1:0][OFF_WD-1:0]  soff, doff;

  logic [CHANNEL_COUNT-1:0]              rd_valid, rd_first, rd_gnt;
  logic [CHANNEL_COUNT-1:0][ADDR_WD-1:0] rd_addr;
  logic [CHANNEL_COUNT-1:0][BEAT_WD-1:0] rd_beats;
  logic [BLEN_WD-1:0]                    rd_gnt_beats;

  logic [CHANNEL_COUNT-1:0]              wr_valid, wr_first, wr_gnt;
  logic [CHANNEL_COUNT-1:0][ADDR_WD-1:0] wr_addr;
  logic [CHANNEL_COUNT-1:0][BEAT_WD-1:0] wr_beats;
  logic [BLEN_WD-1:0]                    wr_gnt_beats;

  logic                                  done_valid, done_err;
  logic [CH_WD-1:0]                      done_ch;
  logic [BLEN_WD-1:0]                    done_beats;
  logic                                  rerr_valid;
  logic [CH_WD-1:0]                      rerr_ch;

  logic [CHANNEL_COUNT-1:0]              irq_req, irq_err_vec, irq_ack;

  // ---- data buffer ---------------------------------------------------------
  logic                                    push_valid;
  logic [CH_WD-1:0]                        push_ch;
  logic [DATA_WD-1:0]                      push_data;
  logic [CHANNEL_COUNT-1:0]                buf_pop;
  logic [CHANNEL_COUNT-1:0][DATA_WD-1:0]   buf_dout;
  logic [CHANNEL_COUNT-1:0][ROOM_WD-1:0]   buf_count;

  assign cmd_ready = !cmd_full;

  dmac_buffer #(
    .ADDR_WD         (ADDR_WD),
    .DATA_WD         (DATA_WD),
    .LEN_WD          (LEN_WD),
    .CHANNEL_COUNT   (CHANNEL_COUNT),
    .CMD_FIFO_DEPTH  (CMD_FIFO_DEPTH),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH),
    .CH_WD           (CH_WD),
    .ROOM_WD         (ROOM_WD)
  ) u_buf (
    .clk        (clk),
    .rst_n      (rst_n),
    .cmd_wr     (cmd_valid && cmd_ready),
    .cmd_src    (cmd_src),
    .cmd_dst    (cmd_dst),
    .cmd_len    (cmd_len),
    .cmd_full   (cmd_full),
    .cmd_rd     (cmd_rd),
    .cmd_src_o  (q_src),
    .cmd_dst_o  (q_dst),
    .cmd_len_o  (q_len),
    .cmd_empty  (cmd_empty),
    .push_valid (push_valid),
    .push_ch    (push_ch),
    .push_data  (push_data),
    .pop        (buf_pop),
    .dout       (buf_dout),
    .count      (buf_count)
  );

  dmac_channel_requester #(
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .CH_WD         (CH_WD)
  ) u_req (
    .clk         (clk),
    .rst_n       (rst_n),
    .cmd_empty   (cmd_empty),
    .cmd_rd      (cmd_rd),
    .ch_free     (ch_free),
    .ch_load     (ch_load),
    .alloc_valid (alloc_valid),
    .alloc_ch    (alloc_ch)
  );

  dmac_channels #(
    .ADDR_WD       (ADDR_WD),
    .DATA_WD       (DATA_WD),
    .LEN_WD        (LEN_WD),
    .CHANNEL_COUNT (CHANNEL_COUNT),
    .MAX_BURST_LEN (MAX_BURST_LEN),
    .BEAT_WD       (BEAT_WD),
    .BLEN_WD       (BLEN_WD),
    .OFF_WD        (OFF_WD),
    .CH_WD         (CH_WD)
  ) u_chs (
    .clk          (clk),
    .rst_n        (rst_n),
    .load         (ch_load),
    .load_src     (q_src),
    .load_dst     (q_dst),
    .load_len     (q_len),
    .free         (ch_free),
    .soff         (soff),
    .doff         (doff),
    .rd_valid     (rd_valid),
    .rd_addr      (rd_addr),
    .rd_beats     (rd_beats),
    .rd_first     (rd_first),
    .rd_gnt       (rd_gnt),
    .rd_gnt_beats (rd_gnt_beats),
    .wr_valid     (wr_valid),
    .wr_addr      (wr_addr),
    .wr_beats     (wr_beats),
    .wr_first     (wr_first),
    .wr_gnt       (wr_gnt),
    .wr_gnt_beats (wr_gnt_beats),
    .done_valid   (done_valid),
    .done_ch      (done_ch),
    .done_beats   (done_beats),
    .done_err     (done_err),
    .rd_err_valid (rerr_valid),
    .rd_err_ch    (rerr_ch),
    .irq_valid    (irq_req),
    .irq_err      (irq_err_vec),
    .irq_ready    (irq_ack)
  );

  dmac_read_engine #(
    .ADDR_WD         (ADDR_WD),
    .DATA_WD         (DATA_WD),
    .LEN_WD          (LEN_WD),
    .CHANNEL_COUNT   (CHANNEL_COUNT),
    .MAX_BURST_LEN   (MAX_BURST_LEN),
    .ID_WD           (ID_WD),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH),
    .RD_OUTSTANDING  (RD_OUTSTANDING),
    .BEAT_WD         (BEAT_WD),
    .BLEN_WD         (BLEN_WD),
    .OFF_WD          (OFF_WD),
    .CH_WD           (CH_WD),
    .ROOM_WD         (ROOM_WD)
  ) u_rd (
    .clk           (clk),
    .rst_n         (rst_n),
    .ch_load       (ch_load),
    .rd_valid      (rd_valid),
    .rd_addr       (rd_addr),
    .rd_beats      (rd_beats),
    .rd_first      (rd_first),
    .soff          (soff),
    .rd_gnt        (rd_gnt),
    .rd_gnt_beats  (rd_gnt_beats),
    .buf_count     (buf_count),
    .push_valid    (push_valid),
    .push_ch       (push_ch),
    .push_data     (push_data),
    .err_valid     (rerr_valid),
    .err_ch        (rerr_ch),
    .m_axi_arid    (m_axi_arid),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rid     (m_axi_rid),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready)
  );

  dmac_write_engine #(
    .ADDR_WD         (ADDR_WD),
    .DATA_WD         (DATA_WD),
    .LEN_WD          (LEN_WD),
    .CHANNEL_COUNT   (CHANNEL_COUNT),
    .MAX_BURST_LEN   (MAX_BURST_LEN),
    .ID_WD           (ID_WD),
    .DATA_FIFO_DEPTH (DATA_FIFO_DEPTH),
    .WR_OUTSTANDING  (WR_OUTSTANDING),
    .BEAT_WD         (BEAT_WD),
    .BLEN_WD         (BLEN_WD),
    .OFF_WD          (OFF_WD),
    .CH_WD           (CH_WD),
    .ROOM_WD         (ROOM_WD),
    .STRB_WD         (STRB_WD)
  ) u_wr (
    .clk           (clk),
    .rst_n         (rst_n),
    .wr_valid      (wr_valid),
    .wr_addr       (wr_addr),
    .wr_beats      (wr_beats),
    .wr_first      (wr_first),
    .doff          (doff),
    .wr_gnt        (wr_gnt),
    .wr_gnt_beats  (wr_gnt_beats),
    .buf_count     (buf_count),
    .buf_dout      (buf_dout),
    .buf_rd        (buf_pop),
    .done_valid    (done_valid),
    .done_ch       (done_ch),
    .done_beats    (done_beats),
    .done_err      (done_err),
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
    .m_axi_wready  (m_axi_wready),
    .m_axi_bid     (m_axi_bid),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

  // ---- interrupt arbitration ----------------------------------------------
  logic [CHANNEL_COUNT-1:0] irq_gnt;
  logic [CH_WD-1:0]         irq_gnt_id;
  logic                     irq_any, irq_fire;

  dmac_rr_arb #(
    .N    (CHANNEL_COUNT),
    .ID_W (CH_WD)
  ) u_irq_arb (
    .clk    (clk),
    .rst_n  (rst_n),
    .req    (irq_req),
    .upd    (irq_fire),
    .gnt    (irq_gnt),
    .gnt_id (irq_gnt_id),
    .any    (irq_any)
  );

  assign irq_valid = irq_any;
  assign irq_ch    = irq_gnt_id;
  assign irq_err   = irq_err_vec[irq_gnt_id];
  assign irq_fire  = irq_valid && irq_ready;
  assign irq_ack   = irq_fire ? irq_gnt : '0;

`ifndef SYNTHESIS
  initial begin
    assert (MAX_BURST_LEN <= 256)
      else $fatal(1, "dmac_top: MAX_BURST_LEN must be <= 256 (AXI4 INCR limit)");
    assert ((MAX_BURST_LEN & (MAX_BURST_LEN-1)) == 0)
      else $fatal(1, "dmac_top: MAX_BURST_LEN must be a power of two");
    assert (DATA_FIFO_DEPTH >= MAX_BURST_LEN)
      else $fatal(1, "dmac_top: DATA_FIFO_DEPTH must be >= MAX_BURST_LEN");
    assert ((DATA_WD >= 8) && ((DATA_WD & (DATA_WD-1)) == 0))
      else $fatal(1, "dmac_top: DATA_WD must be a power of two, at least 8");
  end
`endif

endmodule

`default_nettype wire
