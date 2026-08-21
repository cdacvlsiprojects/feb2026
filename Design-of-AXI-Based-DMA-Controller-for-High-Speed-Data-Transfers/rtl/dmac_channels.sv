// ---------------------------------------------------------------------------
// dmac_channels - the array of CHANNEL_COUNT channel controllers.
// Nothing here but a generate loop and vector packing.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_channels
  import dmac_pkg::*;
#(
  parameter int ADDR_WD       = dmac_pkg::ADDR_WD,
  parameter int DATA_WD       = dmac_pkg::DATA_WD,
  parameter int LEN_WD        = dmac_pkg::LEN_WD,
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN = dmac_pkg::MAX_BURST_LEN,
  parameter int BEAT_WD       = LEN_WD + 1,
  parameter int BLEN_WD       = dmac_pkg::cw(MAX_BURST_LEN) + 1,
  parameter int OFF_WD        = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT)
) (
  input  wire                                     clk,
  input  wire                                     rst_n,

  input  wire  [CHANNEL_COUNT-1:0]                load,
  input  wire  [ADDR_WD-1:0]                      load_src,
  input  wire  [ADDR_WD-1:0]                      load_dst,
  input  wire  [LEN_WD-1:0]                       load_len,
  output logic [CHANNEL_COUNT-1:0]                free,

  output logic [CHANNEL_COUNT-1:0][OFF_WD-1:0]    soff,
  output logic [CHANNEL_COUNT-1:0][OFF_WD-1:0]    doff,

  output logic [CHANNEL_COUNT-1:0]                rd_valid,
  output logic [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   rd_addr,
  output logic [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   rd_beats,
  output logic [CHANNEL_COUNT-1:0]                rd_first,
  input  wire  [CHANNEL_COUNT-1:0]                rd_gnt,
  input  wire  [BLEN_WD-1:0]                      rd_gnt_beats,

  output logic [CHANNEL_COUNT-1:0]                wr_valid,
  output logic [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   wr_addr,
  output logic [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   wr_beats,
  output logic [CHANNEL_COUNT-1:0]                wr_first,
  input  wire  [CHANNEL_COUNT-1:0]                wr_gnt,
  input  wire  [BLEN_WD-1:0]                      wr_gnt_beats,

  input  wire                                     done_valid,
  input  wire  [CH_WD-1:0]                        done_ch,
  input  wire  [BLEN_WD-1:0]                      done_beats,
  input  wire                                     done_err,

  input  wire                                     rd_err_valid,
  input  wire  [CH_WD-1:0]                        rd_err_ch,

  output logic [CHANNEL_COUNT-1:0]                irq_valid,
  output logic [CHANNEL_COUNT-1:0]                irq_err,
  input  wire  [CHANNEL_COUNT-1:0]                irq_ready
);

  for (genvar g = 0; g < CHANNEL_COUNT; g++) begin : g_ch
    dmac_channel_ctrl #(
      .ADDR_WD (ADDR_WD),
      .DATA_WD (DATA_WD),
      .LEN_WD  (LEN_WD),
      .BEAT_WD (BEAT_WD),
      .BLEN_WD (BLEN_WD),
      .OFF_WD  (OFF_WD)
    ) u_ch (
      .clk          (clk),
      .rst_n        (rst_n),
      .load         (load[g]),
      .load_src     (load_src),
      .load_dst     (load_dst),
      .load_len     (load_len),
      .free         (free[g]),
      .soff         (soff[g]),
      .doff         (doff[g]),
      .rd_valid     (rd_valid[g]),
      .rd_addr      (rd_addr[g]),
      .rd_beats     (rd_beats[g]),
      .rd_first     (rd_first[g]),
      .rd_gnt       (rd_gnt[g]),
      .rd_gnt_beats (rd_gnt_beats),
      .wr_valid     (wr_valid[g]),
      .wr_addr      (wr_addr[g]),
      .wr_beats     (wr_beats[g]),
      .wr_first     (wr_first[g]),
      .wr_gnt       (wr_gnt[g]),
      .wr_gnt_beats (wr_gnt_beats),
      .done_valid   (done_valid && (done_ch == CH_WD'(g))),
      .done_beats   (done_beats),
      .done_err     (done_err),
      .rd_err       (rd_err_valid && (rd_err_ch == CH_WD'(g))),
      .irq_valid    (irq_valid[g]),
      .irq_err      (irq_err[g]),
      .irq_ready    (irq_ready[g])
    );
  end

endmodule

`default_nettype wire
