// ---------------------------------------------------------------------------
// dmac_wr_align - places packed beats at an arbitrary byte offset "df" in the
// destination, and generates WSTRB.
//
// Write beat w must carry destination bytes [w*S, (w+1)*S). Byte b of that
// beat comes from packed beat w at byte b-df when b >= df, and from packed
// beat w-1 at byte S-df+b when b < df:
//
//     wdata = (packed << 8*df) | (res >> 8*(S-df))          with res = packed[w-1]
//
// When df == 0 the second term shifts out completely and this reduces to a
// pass-through, so there is no special case to write.
//
// Beat counts: len packed beats in, len+1 write beats out when df != 0. The
// extra last beat is pure residue, so it consumes nothing.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_wr_align
  import dmac_pkg::*;
#(
  parameter int DATA_WD       = dmac_pkg::DATA_WD,
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int OFF_WD        = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int STRB_WD       = DATA_WD/8
) (
  input  wire                                  clk,

  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0] doff,

  input  wire  [CH_WD-1:0]                     ch,
  input  wire                                  beat_valid,  // W beat accepted
  input  wire                                  beat_first,  // first of transfer
  input  wire                                  beat_last,   // last of transfer

  input  wire  [DATA_WD-1:0]                   fifo_data,
  output logic                                 fifo_rd,

  output logic [DATA_WD-1:0]                   wdata,
  output logic [STRB_WD-1:0]                   wstrb
);

  logic [CHANNEL_COUNT-1:0][DATA_WD-1:0] res_q;

  wire [OFF_WD-1:0] df           = doff[ch];
  wire              use_res_only = beat_last && (df != '0);

  assign wdata = (fifo_data << (8*df)) | (res_q[ch] >> (8*(STRB_WD - df)));

  always_comb begin
    wstrb = '1;
    if (df != '0) begin
      if      (beat_first) wstrb = ~((STRB_WD'(1) << df) - STRB_WD'(1));
      else if (beat_last)  wstrb =  ((STRB_WD'(1) << df) - STRB_WD'(1));
    end
  end

  assign fifo_rd = beat_valid && !use_res_only;

  always_ff @(posedge clk) begin
    if (beat_valid && !use_res_only) res_q[ch] <= fifo_data;
  end

endmodule

`default_nettype wire
