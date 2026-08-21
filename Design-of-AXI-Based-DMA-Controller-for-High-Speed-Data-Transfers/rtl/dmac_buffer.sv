// ---------------------------------------------------------------------------
// dmac_buffer - the DMAC Buffer of the block diagram.
//
//   Command Buffer : one FIFO of pending CPU instructions
//   Data Buffer    : one FIFO per channel, holding PACKED beats on their way
//                    from the read engine to the write engine
//
// Per-channel data FIFOs (rather than one shared FIFO) are what make unaligned
// transfers workable: read and write move a different number of beats, and the
// byte-realignment residue is per channel.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_buffer
  import dmac_pkg::*;
#(
  parameter int ADDR_WD         = dmac_pkg::ADDR_WD,
  parameter int DATA_WD         = dmac_pkg::DATA_WD,
  parameter int LEN_WD          = dmac_pkg::LEN_WD,
  parameter int CHANNEL_COUNT   = dmac_pkg::CHANNEL_COUNT,
  parameter int CMD_FIFO_DEPTH  = dmac_pkg::CMD_FIFO_DEPTH,
  parameter int DATA_FIFO_DEPTH = dmac_pkg::DATA_FIFO_DEPTH,
  parameter int CH_WD           = dmac_pkg::cw(CHANNEL_COUNT),
  parameter int ROOM_WD         = $clog2(DATA_FIFO_DEPTH+1)
) (
  input  wire                                   clk,
  input  wire                                   rst_n,

  // ---- command buffer -----------------------------------------------------
  input  wire                                   cmd_wr,
  input  wire  [ADDR_WD-1:0]                    cmd_src,
  input  wire  [ADDR_WD-1:0]                    cmd_dst,
  input  wire  [LEN_WD-1:0]                     cmd_len,
  output logic                                  cmd_full,

  input  wire                                   cmd_rd,
  output logic [ADDR_WD-1:0]                    cmd_src_o,
  output logic [ADDR_WD-1:0]                    cmd_dst_o,
  output logic [LEN_WD-1:0]                     cmd_len_o,
  output logic                                  cmd_empty,

  // ---- data buffer --------------------------------------------------------
  input  wire                                   push_valid,
  input  wire  [CH_WD-1:0]                      push_ch,
  input  wire  [DATA_WD-1:0]                    push_data,

  input  wire  [CHANNEL_COUNT-1:0]              pop,
  output logic [CHANNEL_COUNT-1:0][DATA_WD-1:0] dout,
  output logic [CHANNEL_COUNT-1:0][ROOM_WD-1:0] count
);

  localparam int CMD_WD = 2*ADDR_WD + LEN_WD;

  logic [CMD_WD-1:0] cmd_dout;

  dmac_fifo #(
    .WIDTH (CMD_WD),
    .DEPTH (CMD_FIFO_DEPTH)
  ) u_cmd (
    .clk   (clk),
    .rst_n (rst_n),
    .wr    (cmd_wr),
    .din   ({cmd_src, cmd_dst, cmd_len}),
    .full  (cmd_full),
    .rd    (cmd_rd),
    .dout  (cmd_dout),
    .empty (cmd_empty),
    .count ()
  );

  assign {cmd_src_o, cmd_dst_o, cmd_len_o} = cmd_dout;

  for (genvar g = 0; g < CHANNEL_COUNT; g++) begin : g_data
    dmac_fifo #(
      .WIDTH (DATA_WD),
      .DEPTH (DATA_FIFO_DEPTH)
    ) u_data (
      .clk   (clk),
      .rst_n (rst_n),
      .wr    (push_valid && (push_ch == CH_WD'(g))),
      .din   (push_data),
      .full  (),
      .rd    (pop[g]),
      .dout  (dout[g]),
      .empty (),
      .count (count[g])
    );
  end

endmodule

`default_nettype wire
