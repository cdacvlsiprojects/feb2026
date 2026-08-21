// ---------------------------------------------------------------------------
// dmac_channel_requester - pops a command out of the command buffer and
// allocates it to a free channel, round robin.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_channel_requester
  import dmac_pkg::*;
#(
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT)
) (
  input  wire                       clk,
  input  wire                       rst_n,

  // command buffer read side
  input  wire                       cmd_empty,
  output logic                      cmd_rd,

  // channel array
  input  wire  [CHANNEL_COUNT-1:0]  ch_free,
  output logic [CHANNEL_COUNT-1:0]  ch_load,

  // observability: which channel took the command just popped
  output logic                      alloc_valid,
  output logic [CH_WD-1:0]          alloc_ch
);

  logic [CHANNEL_COUNT-1:0] gnt;
  logic [CH_WD-1:0]         gnt_id;
  logic                     any;
  logic                     go;

  dmac_rr_arb #(
    .N    (CHANNEL_COUNT),
    .ID_W (CH_WD)
  ) u_arb (
    .clk    (clk),
    .rst_n  (rst_n),
    .req    (ch_free),
    .upd    (go),
    .gnt    (gnt),
    .gnt_id (gnt_id),
    .any    (any)
  );

  assign go          = !cmd_empty && any;
  assign cmd_rd      = go;
  assign ch_load     = go ? gnt : '0;
  assign alloc_valid = go;
  assign alloc_ch    = gnt_id;

endmodule

`default_nettype wire
