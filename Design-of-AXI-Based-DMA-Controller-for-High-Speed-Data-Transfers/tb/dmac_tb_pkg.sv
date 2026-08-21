// ---------------------------------------------------------------------------
// dmac_tb_pkg - collects the testbench classes into one scope so they can see
// each other and the testbench can import them with a single line.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

package dmac_tb_pkg;

  import dmac_pkg::*;
  import axi_mem_pkg::*;

  `include "dmac_cmd.sv"
  `include "dmac_scoreboard.sv"
  `include "dmac_driver.sv"
  `include "dmac_monitor.sv"

endpackage
