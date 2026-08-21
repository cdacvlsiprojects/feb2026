// ---------------------------------------------------------------------------
// dmac_rr_arb - parameterised round-robin arbiter (masked priority).
//
// The mask holds "indices strictly above the last grant". While anything in
// the mask is requesting it wins; otherwise the search wraps to the lowest
// requester. That is a true rotation, not a fixed priority with a tie-break.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_rr_arb #(
  parameter int N    = 8,
  parameter int ID_W = (N > 1) ? $clog2(N) : 1   // derived, do not override
) (
  input  wire             clk,
  input  wire             rst_n,

  input  wire  [N-1:0]    req,
  input  wire             upd,      // pulse when the grant is actually taken

  output logic [N-1:0]    gnt,
  output logic [ID_W-1:0] gnt_id,
  output logic            any
);

  logic [N-1:0] mask_q, mask_d;
  logic [N-1:0] hi, sel;

  function automatic logic [N-1:0] lsb(input logic [N-1:0] v);
    lsb = v & (~v + 1'b1);
  endfunction

  assign hi  = req & mask_q;
  assign sel = (|hi) ? lsb(hi) : lsb(req);
  assign any = |req;
  assign gnt = sel;

  always_comb begin
    gnt_id = '0;
    for (int i = 0; i < N; i++) if (sel[i]) gnt_id = ID_W'(i);
  end

  always_comb begin
    mask_d = '0;
    for (int i = 0; i < N; i++) mask_d[i] = (i > int'(gnt_id));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)              mask_q <= '1;
    else if (upd && any)     mask_q <= mask_d;
  end

endmodule

`default_nettype wire
