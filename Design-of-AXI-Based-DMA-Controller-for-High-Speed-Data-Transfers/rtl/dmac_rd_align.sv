// ---------------------------------------------------------------------------
// dmac_rd_align - turns raw read beats into packed beats.
//
// The source address may sit at any byte offset "so" inside a beat. Raw beat j
// covers source bytes [j*S, (j+1)*S). Packed beat j must cover transfer bytes
// [so + j*S, so + j*S + S), i.e. the top S-so bytes of raw[j] followed by the
// bottom so bytes of raw[j+1]:
//
//     packed = (raw_in << 8*(S-so)) | (res >> 8*so)         with res = raw[j]
//
// So the first raw beat of a transfer is swallowed (it only fills "res") and
// every later raw beat emits one packed beat. len+1 raw beats in, len out.
// When so == 0 there is nothing to do and the beat passes straight through.
//
// The residue is per channel, so bursts belonging to different channels may
// interleave freely on the bus.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_rd_align
  import dmac_pkg::*;
#(
  parameter int DATA_WD       = dmac_pkg::DATA_WD,
  parameter int CHANNEL_COUNT = dmac_pkg::CHANNEL_COUNT,
  parameter int OFF_WD        = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT)
) (
  input  wire                                  clk,
  input  wire                                  rst_n,

  input  wire  [CHANNEL_COUNT-1:0]             ch_load,   // restart a channel
  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0] soff,

  input  wire                                  in_valid,
  input  wire  [DATA_WD-1:0]                   in_data,
  input  wire  [CH_WD-1:0]                     in_ch,

  output logic                                 out_valid,
  output logic [DATA_WD-1:0]                   out_data,
  output logic [CH_WD-1:0]                     out_ch
);

  localparam int STRB_WD = DATA_WD/8;

  logic [CHANNEL_COUNT-1:0][DATA_WD-1:0] res_q;
  logic [CHANNEL_COUNT-1:0]              first_q;

  wire [OFF_WD-1:0] so      = soff[in_ch];
  wire              swallow = first_q[in_ch] && (so != '0);

  assign out_valid = in_valid && !swallow;
  assign out_ch    = in_ch;

  always_comb begin
    if (so == '0) out_data = in_data;
    else          out_data = (in_data << (8*(STRB_WD - so)))
                           | (res_q[in_ch] >> (8*so));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      first_q <= '1;
    end else begin
      for (int i = 0; i < CHANNEL_COUNT; i++) begin
        if (ch_load[i]) first_q[i] <= 1'b1;
      end
      if (in_valid) first_q[in_ch] <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (in_valid) res_q[in_ch] <= in_data;
  end

endmodule

`default_nettype wire
