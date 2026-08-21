// ---------------------------------------------------------------------------
// dmac_fifo - parameterised synchronous FIFO, first-word-fall-through.
// Used for the command buffer, the per-channel data buffers and the AXI
// in-flight tracking queues.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_fifo #(
  parameter int WIDTH  = 32,
  parameter int DEPTH  = 16,
  parameter int CNT_WD = $clog2(DEPTH+1)   // derived, do not override
) (
  input  wire               clk,
  input  wire               rst_n,

  input  wire               wr,
  input  wire  [WIDTH-1:0]  din,
  output logic              full,

  input  wire               rd,
  output logic [WIDTH-1:0]  dout,
  output logic              empty,

  output logic [CNT_WD-1:0] count
);

  localparam int PTR_WD = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  logic [WIDTH-1:0]  mem [DEPTH];
  logic [PTR_WD-1:0] wp, rp;
  logic [CNT_WD-1:0] cnt;

  wire do_wr = wr && !full;
  wire do_rd = rd && !empty;

  assign full  = (cnt == CNT_WD'(DEPTH));
  assign empty = (cnt == '0);
  assign count = cnt;
  assign dout  = mem[rp];

  always_ff @(posedge clk) begin
    if (do_wr) mem[wp] <= din;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wp  <= '0;
      rp  <= '0;
      cnt <= '0;
    end else begin
      if (do_wr) wp <= (wp == PTR_WD'(DEPTH-1)) ? '0 : wp + 1'b1;
      if (do_rd) rp <= (rp == PTR_WD'(DEPTH-1)) ? '0 : rp + 1'b1;
      case ({do_wr, do_rd})
        2'b10:   cnt <= cnt + 1'b1;
        2'b01:   cnt <= cnt - 1'b1;
        default: ;
      endcase
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk) if (rst_n) begin
    assert (!(wr && full))  else $fatal(1, "dmac_fifo: write while full");
    assert (!(rd && empty)) else $fatal(1, "dmac_fifo: read while empty");
  end
`endif

endmodule

`default_nettype wire
