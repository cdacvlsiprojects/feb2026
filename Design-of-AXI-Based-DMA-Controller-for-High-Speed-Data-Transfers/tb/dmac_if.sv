// ---------------------------------------------------------------------------
// dmac_if - every DUT signal in one place, so the driver, monitor, coverage
// and assertion blocks can all reach them through one handle.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

interface dmac_if #(
  parameter int ADDR_WD = dmac_pkg::ADDR_WD,
  parameter int DATA_WD = dmac_pkg::DATA_WD,
  parameter int LEN_WD  = dmac_pkg::LEN_WD,
  parameter int ID_WD   = dmac_pkg::ID_WD,
  parameter int CH_WD   = dmac_pkg::cw(dmac_pkg::CHANNEL_COUNT),
  parameter int STRB_WD = DATA_WD/8
) (
  input logic clk,
  input logic rst_n
);

  // ---- CPU command --------------------------------------------------------
  logic               cmd_valid;
  logic               cmd_ready;
  logic [ADDR_WD-1:0] cmd_src;
  logic [ADDR_WD-1:0] cmd_dst;
  logic [LEN_WD-1:0]  cmd_len;

  // ---- allocation observability -------------------------------------------
  logic               alloc_valid;
  logic [CH_WD-1:0]   alloc_ch;

  // ---- interrupt ----------------------------------------------------------
  logic               irq_valid;
  logic               irq_ready;
  logic [CH_WD-1:0]   irq_ch;
  logic               irq_err;

  // ---- AXI write address --------------------------------------------------
  logic [ID_WD-1:0]   awid;
  logic [ADDR_WD-1:0] awaddr;
  logic [7:0]         awlen;
  logic [2:0]         awsize;
  logic [1:0]         awburst;
  logic               awvalid;
  logic               awready;

  // ---- AXI write data -----------------------------------------------------
  logic [DATA_WD-1:0] wdata;
  logic [STRB_WD-1:0] wstrb;
  logic               wlast;
  logic               wvalid;
  logic               wready;

  // ---- AXI write response -------------------------------------------------
  logic [ID_WD-1:0]   bid;
  logic [1:0]         bresp;
  logic               bvalid;
  logic               bready;

  // ---- AXI read address ---------------------------------------------------
  logic [ID_WD-1:0]   arid;
  logic [ADDR_WD-1:0] araddr;
  logic [7:0]         arlen;
  logic [2:0]         arsize;
  logic [1:0]         arburst;
  logic               arvalid;
  logic               arready;

  // ---- AXI read data ------------------------------------------------------
  logic [ID_WD-1:0]   rid;
  logic [DATA_WD-1:0] rdata;
  logic [1:0]         rresp;
  logic               rlast;
  logic               rvalid;
  logic               rready;

endinterface
