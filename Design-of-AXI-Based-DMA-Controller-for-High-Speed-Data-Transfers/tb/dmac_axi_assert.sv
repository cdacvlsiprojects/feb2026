// ---------------------------------------------------------------------------
// dmac_axi_assert - AXI4 protocol checks on the DUT's master port.
// This is the "verify correct VALID/READY handshaking" objective, made
// machine-checkable. Nothing here reaches inside the DUT.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module dmac_axi_assert #(
  parameter int ADDR_WD       = 32,
  parameter int DATA_WD       = 32,
  parameter int ID_WD         = 4,
  parameter int MAX_BURST_LEN = 16,
  parameter int STRB_WD       = DATA_WD/8
) (
  input wire                clk,
  input wire                rst_n,

  input wire  [ID_WD-1:0]   awid,
  input wire  [ADDR_WD-1:0] awaddr,
  input wire  [7:0]         awlen,
  input wire  [2:0]         awsize,
  input wire  [1:0]         awburst,
  input wire                awvalid,
  input wire                awready,

  input wire  [DATA_WD-1:0] wdata,
  input wire  [STRB_WD-1:0] wstrb,
  input wire                wlast,
  input wire                wvalid,
  input wire                wready,

  input wire  [1:0]         bresp,
  input wire                bvalid,
  input wire                bready,

  input wire  [ID_WD-1:0]   arid,
  input wire  [ADDR_WD-1:0] araddr,
  input wire  [7:0]         arlen,
  input wire  [2:0]         arsize,
  input wire  [1:0]         arburst,
  input wire                arvalid,
  input wire                arready,

  input wire  [DATA_WD-1:0] rdata,
  input wire  [1:0]         rresp,
  input wire                rlast,
  input wire                rvalid,
  input wire                rready
);

  localparam int SIZE_EXP = (STRB_WD > 1) ? $clog2(STRB_WD) : 0;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ---- VALID must hold until READY ----------------------------------------
  property p_hold(valid, ready);
    (valid && !ready) |=> valid;
  endproperty

  a_aw_hold : assert property (p_hold(awvalid, awready))
    else begin tb_err_pkg::bump(); $error("AXI: AWVALID dropped before AWREADY"); end
  a_w_hold  : assert property (p_hold(wvalid, wready))
    else begin tb_err_pkg::bump(); $error("AXI: WVALID dropped before WREADY"); end
  a_ar_hold : assert property (p_hold(arvalid, arready))
    else begin tb_err_pkg::bump(); $error("AXI: ARVALID dropped before ARREADY"); end

  // ---- payload stable while stalled ---------------------------------------
  a_aw_stable : assert property
    ((awvalid && !awready) |=> $stable({awid, awaddr, awlen, awsize, awburst}))
    else begin tb_err_pkg::bump(); $error("AXI: AW payload changed while AWVALID was held"); end

  a_w_stable : assert property
    ((wvalid && !wready) |=> $stable({wdata, wstrb, wlast}))
    else begin tb_err_pkg::bump(); $error("AXI: W payload changed while WVALID was held"); end

  a_ar_stable : assert property
    ((arvalid && !arready) |=> $stable({arid, araddr, arlen, arsize, arburst}))
    else begin tb_err_pkg::bump(); $error("AXI: AR payload changed while ARVALID was held"); end

  // ---- burst legality ------------------------------------------------------
  a_aw_len : assert property (awvalid |-> (awlen + 1 <= MAX_BURST_LEN))
    else begin tb_err_pkg::bump(); $error("AXI: AWLEN %0d exceeds MAX_BURST_LEN %0d", awlen+1, MAX_BURST_LEN); end
  a_ar_len : assert property (arvalid |-> (arlen + 1 <= MAX_BURST_LEN))
    else begin tb_err_pkg::bump(); $error("AXI: ARLEN %0d exceeds MAX_BURST_LEN %0d", arlen+1, MAX_BURST_LEN); end

  a_aw_incr : assert property (awvalid |-> (awburst == 2'b01))
    else begin tb_err_pkg::bump(); $error("AXI: AWBURST must be INCR"); end
  a_ar_incr : assert property (arvalid |-> (arburst == 2'b01))
    else begin tb_err_pkg::bump(); $error("AXI: ARBURST must be INCR"); end

  a_aw_size : assert property (awvalid |-> (awsize == 3'(SIZE_EXP)))
    else begin tb_err_pkg::bump(); $error("AXI: AWSIZE must match the data width"); end
  a_ar_size : assert property (arvalid |-> (arsize == 3'(SIZE_EXP)))
    else begin tb_err_pkg::bump(); $error("AXI: ARSIZE must match the data width"); end

  a_aw_align : assert property (awvalid |-> ((awaddr & (STRB_WD-1)) == 0))
    else begin tb_err_pkg::bump(); $error("AXI: AWADDR %0h is not beat aligned", awaddr); end
  a_ar_align : assert property (arvalid |-> ((araddr & (STRB_WD-1)) == 0))
    else begin tb_err_pkg::bump(); $error("AXI: ARADDR %0h is not beat aligned", araddr); end

  // ---- 4 KB boundary -------------------------------------------------------
  a_aw_4k : assert property
    (awvalid |-> (((awaddr % 4096) + ((awlen + 1) * STRB_WD)) <= 4096))
    else begin tb_err_pkg::bump(); $error("AXI: write burst at %0h len %0d crosses a 4 KB boundary",
                awaddr, awlen+1); end
  a_ar_4k : assert property
    (arvalid |-> (((araddr % 4096) + ((arlen + 1) * STRB_WD)) <= 4096))
    else begin tb_err_pkg::bump(); $error("AXI: read burst at %0h len %0d crosses a 4 KB boundary",
                araddr, arlen+1); end

  // ---- single ID -----------------------------------------------------------
  a_awid : assert property (awvalid |-> (awid == '0))
    else begin tb_err_pkg::bump(); $error("AXI: AWID must be 0"); end
  a_arid : assert property (arvalid |-> (arid == '0))
    else begin tb_err_pkg::bump(); $error("AXI: ARID must be 0"); end

  // ---- WLAST lands on the beat AWLEN says --------------------------------
  int unsigned aw_beats;   // beats promised by the outstanding AW
  int unsigned w_count;    // W beats sent so far in this burst

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_beats <= 0;
      w_count  <= 0;
    end else begin
      if (awvalid && awready) aw_beats <= awlen + 1;
      if (wvalid && wready) begin
        if (wlast) w_count <= 0;
        else       w_count <= w_count + 1;
      end
    end
  end

  a_wlast : assert property
    ((wvalid && wready && wlast) |-> ((w_count + 1) == aw_beats))
    else begin tb_err_pkg::bump(); $error("AXI: WLAST on beat %0d but AWLEN promised %0d",
                w_count+1, aw_beats); end

  a_w_count : assert property
    ((wvalid && wready && !wlast) |-> ((w_count + 1) < aw_beats))
    else begin tb_err_pkg::bump(); $error("AXI: more W beats than AWLEN promised"); end

  // ---- no response without a request --------------------------------------
  int unsigned aw_out, b_out, ar_out, r_out;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_out <= 0; b_out <= 0; ar_out <= 0; r_out <= 0;
    end else begin
      if (awvalid && awready) aw_out <= aw_out + 1;
      if (bvalid  && bready)  b_out  <= b_out  + 1;
      if (arvalid && arready) ar_out <= ar_out + 1;
      if (rvalid  && rready && rlast) r_out <= r_out + 1;
    end
  end

  a_b_paired : assert property ((bvalid && bready) |-> (b_out < aw_out))
    else begin tb_err_pkg::bump(); $error("AXI: B response with no matching AW"); end
  a_r_paired : assert property ((rvalid && rready && rlast) |-> (r_out < ar_out))
    else begin tb_err_pkg::bump(); $error("AXI: RLAST with no matching AR"); end

  // ---- reset ---------------------------------------------------------------
  // plain procedural check, so the global "disable iff (!rst_n)" above does
  // not switch it off exactly when it matters
  always @(posedge clk) begin
    if (!rst_n) begin
      assert (!awvalid && !wvalid && !arvalid)
        else begin tb_err_pkg::bump(); $error("AXI: a VALID was asserted during reset"); end
    end
  end

  wire _unused = &{1'b0, rdata, rresp, bresp, wdata};

endmodule

`default_nettype wire
