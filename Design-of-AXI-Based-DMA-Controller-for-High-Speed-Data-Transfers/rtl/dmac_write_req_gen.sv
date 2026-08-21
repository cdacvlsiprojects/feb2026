// ---------------------------------------------------------------------------
// dmac_write_req_gen - combinational burst splitter for the write side.
//
// Same three-way minimum as the read side, but applied to the destination
// pointer - src and dst can sit at different offsets inside their 4 KB pages,
// so the two sides split differently.
//
// A burst is only offered once the channel's buffer already holds every beat
// it will consume, so the W channel never stalls on an empty buffer and every
// burst is as long as the splitter allows. Settling for however many beats
// happen to be sitting there would work too, but it produces a stream of
// one-beat bursts whenever data trickles in, which wastes the bus.
//
// Waiting cannot deadlock: "need" is never more than the beats still to arrive
// for that channel, and if the read side is blocked for buffer room then the
// buffer is by definition nearly full, so the beats are already there.
//
// The final write beat of an unaligned transfer consumes nothing (it is pure
// residue out of dmac_wr_align), which is what "need" accounts for - a channel
// whose only remaining work is that tail beat is released with need == 0.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_write_req_gen
  import dmac_pkg::*;
#(
  parameter int ADDR_WD         = dmac_pkg::ADDR_WD,
  parameter int DATA_WD         = dmac_pkg::DATA_WD,
  parameter int LEN_WD          = dmac_pkg::LEN_WD,
  parameter int CHANNEL_COUNT   = dmac_pkg::CHANNEL_COUNT,
  parameter int MAX_BURST_LEN   = dmac_pkg::MAX_BURST_LEN,
  parameter int DATA_FIFO_DEPTH = dmac_pkg::DATA_FIFO_DEPTH,
  parameter int BEAT_WD         = LEN_WD + 1,
  parameter int BLEN_WD         = dmac_pkg::cw(MAX_BURST_LEN) + 1,
  parameter int OFF_WD          = dmac_pkg::cw(DATA_WD/8),
  parameter int CH_WD           = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int ROOM_WD         = $clog2(DATA_FIFO_DEPTH+1)
) (
  input  wire  [CHANNEL_COUNT-1:0]                wr_valid,
  input  wire  [CHANNEL_COUNT-1:0][ADDR_WD-1:0]   wr_addr,
  input  wire  [CHANNEL_COUNT-1:0][BEAT_WD-1:0]   wr_beats,
  input  wire  [CHANNEL_COUNT-1:0][OFF_WD-1:0]    doff,
  input  wire  [CHANNEL_COUNT-1:0][ROOM_WD-1:0]   avail,

  output logic [CHANNEL_COUNT-1:0]                gate,

  input  wire  [CH_WD-1:0]                        gnt_id,

  output logic [ADDR_WD-1:0]                      req_addr,
  output logic [7:0]                              req_len,     // AWLEN
  output logic [BLEN_WD-1:0]                      req_beats,
  output logic                                    req_final    // holds last beat
);

  localparam int STRB_WD = DATA_WD/8;
  localparam int SHFT    = dmac_pkg::sh(STRB_WD);
  localparam int P4_WD   = $clog2(dmac_pkg::AXI_4K) + 1;
  localparam int MW      = dmac_pkg::maxi(BEAT_WD, P4_WD);

  logic [CHANNEL_COUNT-1:0][MW-1:0] n_beats;

  always_comb begin
    for (int i = 0; i < CHANNEL_COUNT; i++) begin
      automatic logic [MW-1:0] b4k, nmax, need;
      automatic logic          fin;

      b4k  = MW'((dmac_pkg::AXI_4K - int'(wr_addr[i][P4_WD-2:0])) >> SHFT);

      nmax = MW'(MAX_BURST_LEN);
      if (MW'(wr_beats[i]) < nmax) nmax = MW'(wr_beats[i]);
      if (b4k              < nmax) nmax = b4k;

      fin  = (nmax == MW'(wr_beats[i])) && (doff[i] != '0);
      need = nmax - MW'(fin);

      n_beats[i] = (MW'(avail[i]) >= need) ? nmax : '0;
      gate[i]    = wr_valid[i] && (n_beats[i] != '0);
    end
  end

  wire [MW-1:0] n = n_beats[gnt_id];

  assign req_addr  = wr_addr[gnt_id];
  assign req_beats = BLEN_WD'(n);
  assign req_len   = 8'(n - 1);
  assign req_final = (n == MW'(wr_beats[gnt_id]));

endmodule

`default_nettype wire
