// ---------------------------------------------------------------------------
// tb_err_pkg - one global failure counter.
//
// $error alone is not enough: the transcript would show a failure but the
// testbench would still print TEST PASSED. Every protocol assertion and every
// memory-model check bumps this counter, and the final verdict reads it, so
// the printed result is the whole truth.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

package tb_err_pkg;

  int unsigned n_err = 0;

  function automatic void bump();
    n_err++;
  endfunction

  function automatic void reset();
    n_err = 0;
  endfunction

endpackage
