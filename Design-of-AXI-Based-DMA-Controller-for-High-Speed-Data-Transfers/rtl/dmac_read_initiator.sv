// ---------------------------------------------------------------------------
// dmac_read_initiator - registers one burst request and drives the AR channel.
//
// The request is latched before ARVALID rises, so ARADDR/ARLEN are stable for
// as long as ARVALID is held - which is what the AXI handshake rules demand.
// A new request can be latched in the same cycle the previous AR is accepted,
// so sustained throughput is one AR per clock.
// ---------------------------------------------------------------------------
`default_nettype none

module dmac_read_initiator
  import dmac_pkg::*;
#(
  parameter int ADDR_WD = dmac_pkg::ADDR_WD,
  parameter int DATA_WD = dmac_pkg::DATA_WD,
  parameter int ID_WD   = dmac_pkg::ID_WD
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                req_valid,
  output logic               req_ready,
  input  wire  [ADDR_WD-1:0] req_addr,
  input  wire  [7:0]         req_len,

  output logic [ID_WD-1:0]   m_axi_arid,
  output logic [ADDR_WD-1:0] m_axi_araddr,
  output logic [7:0]         m_axi_arlen,
  output logic [2:0]         m_axi_arsize,
  output logic [1:0]         m_axi_arburst,
  output logic               m_axi_arvalid,
  input  wire                m_axi_arready
);

  localparam int STRB_WD = DATA_WD/8;

  logic               busy_q;
  logic [ADDR_WD-1:0] addr_q;
  logic [7:0]         len_q;

  wire accept = req_valid && req_ready;

  assign req_ready     = !busy_q || m_axi_arready;

  assign m_axi_arid    = '0;                       // single ID, see DD-003
  assign m_axi_araddr  = addr_q;
  assign m_axi_arlen   = len_q;
  assign m_axi_arsize  = 3'(dmac_pkg::sh(STRB_WD));
  assign m_axi_arburst = dmac_pkg::BURST_INCR;
  assign m_axi_arvalid = busy_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      addr_q <= '0;
      len_q  <= '0;
    end else begin
      if (!busy_q || m_axi_arready) begin
        busy_q <= req_valid;
        if (req_valid) begin
          addr_q <= req_addr;
          len_q  <= req_len;
        end
      end
    end
  end

  // silence lint on the unused handshake alias
  wire _unused = &{1'b0, accept};

endmodule

`default_nettype wire
