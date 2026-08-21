// ---------------------------------------------------------------------------
// dmac_read_req_gen - combinational burst splitter for the read side.
//
// Two jobs:
//   1. gate[]  - which channels may be arbitrated at all (they still have
//                beats to fetch AND their data buffer has committed room)
//   2. split   - carve one legal AXI burst out of the granted channel:
//                  n = min(MAX_BURST_LEN, beats_left, beats_to_4k, room)
//
// "room" is counted in PACKED beats. When the source is unaligned the very
// first raw read beat is swallowed by dmac_rd_align, so that burst produces
// one packed beat less than it fetches.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_read_req_gen
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
  parameter int CH_WD         = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int ROOM_WD       = $clog2(dmac_pkg::DATA_FIFO_DEPTH+1)
) (
  // per-channel state
  input  wire  [CHANNEL_COUNT-1:0]                rd_valid,
  input  wire  [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   rd_addr,
  input  wire  [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   rd_beats,
  input  wire  [CHANNEL_COUNT-1:0]                rd_first,
  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0]    soff,
  input  wire  [CHANNEL_COUNT-1:0][ROOM_WD-1:0]   room,

  output logic [CHANNEL_COUNT-1:0]                gate,

  // granted channel
  input  wire  [CH_WD-1:0]                        gnt_id,

  // one AXI burst
  output logic [ADDR_WD-1:0]                      req_addr,
  output logic [7:0]                              req_len,      // ARLEN
  output logic [BLEN_WD-1:0]                      req_beats,    // raw beats
  output logic [BLEN_WD-1:0]                      req_packed,   // packed beats
  output logic                                    req_swallow
);

  localparam int STRB_WD = DATA_WD/8;
  localparam int SHFT    = dmac_pkg::sh(STRB_WD);
  localparam int P4_WD   = $clog2(dmac_pkg::AXI_4K) + 1;
  localparam int MW      = dmac_pkg::maxi(BEAT_WD, P4_WD);

  // ---- gating -------------------------------------------------------------
  logic [CHANNEL_COUNT-1:0] swallow;

  always_comb begin
    for (int i = 0; i < CHANNEL_COUNT; i++) begin
      swallow[i] = rd_first[i] && (soff[i] != '0);
      gate[i]    = rd_valid[i] && ((room[i] != '0) || swallow[i]);
    end
  end

  // ---- split for the granted channel --------------------------------------
  wire [ADDR_WD-1:0] g_addr  = rd_addr[gnt_id];
  wire [BEAT_WD-1:0] g_beats = rd_beats[gnt_id];
  wire [ROOM_WD-1:0] g_room  = room[gnt_id];
  wire               g_swal  = swallow[gnt_id];

  logic [MW-1:0] b4k, n_lim, n;

  always_comb begin
    b4k   = MW'((dmac_pkg::AXI_4K - int'(g_addr[P4_WD-2:0])) >> SHFT);
    n_lim = MW'(g_room) + MW'(g_swal);

    n = MW'(MAX_BURST_LEN);
    if (MW'(g_beats) < n) n = MW'(g_beats);
    if (b4k          < n) n = b4k;
    if (n_lim        < n) n = n_lim;
  end

  assign req_addr    = g_addr;
  assign req_beats   = BLEN_WD'(n);
  assign req_len     = 8'(n - 1);
  assign req_swallow = g_swal;
  assign req_packed  = BLEN_WD'(n) - BLEN_WD'(g_swal);

endmodule

`default_nettype wire
