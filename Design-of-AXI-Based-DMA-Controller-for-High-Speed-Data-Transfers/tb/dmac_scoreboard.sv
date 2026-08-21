// ---------------------------------------------------------------------------
// dmac_xfer / dmac_scoreboard
//
// One transfer's expected bytes are snapshotted out of the memory model at
// issue time, so the check is independent of anything the DUT does afterwards.
// On the completion interrupt the destination region is read back byte by byte
// and compared.
//
// Commands are matched to channels by order: the command buffer is a FIFO, so
// the k-th allocation belongs to the k-th accepted command.
// ---------------------------------------------------------------------------

class dmac_xfer;
  longint unsigned src;
  longint unsigned dst;
  int unsigned     len;        // beats
  int unsigned     nbytes;
  int unsigned     ch;
  bit              expect_err;
  logic [7:0]      exp [];

  function void snapshot();
    exp = new[nbytes];
    for (int unsigned i = 0; i < nbytes; i++) exp[i] = axi_mem_pkg::rd_byte(src + i);
  endfunction

  function string show();
    return $sformatf("src=%0h dst=%0h len=%0d beats (%0d bytes)", src, dst, len, nbytes);
  endfunction
endclass


class dmac_scoreboard;

  dmac_xfer    pend [$];       // accepted, not yet allocated to a channel
  dmac_xfer    act  [int];     // allocated, in flight

  int unsigned n_checked = 0;
  int unsigned n_errors  = 0;
  bit          verbose   = 1'b0;

  function void issued(dmac_xfer x);
    pend.push_back(x);
  endfunction

  function void allocated(int unsigned ch);
    if (pend.size() == 0) begin
      $error("[SB] channel %0d allocated but no command is pending", ch);
      n_errors++;
      return;
    end
    if (act.exists(ch)) begin
      $error("[SB] channel %0d re-allocated while still in flight", ch);
      n_errors++;
    end
    act[ch]    = pend.pop_front();
    act[ch].ch = ch;
  endfunction

  function void completed(int unsigned ch, bit err);
    dmac_xfer   x;
    logic [7:0] got;
    int unsigned bad;

    if (!act.exists(ch)) begin
      $error("[SB] interrupt from channel %0d which owns no transfer", ch);
      n_errors++;
      return;
    end

    x = act[ch];
    act.delete(ch);
    n_checked++;

    if (x.expect_err) begin
      if (!err) begin
        $error("[SB][FAIL] ch%0d expected an error response, irq_err was clear. %s",
               ch, x.show());
        n_errors++;
      end else if (verbose) begin
        $display("[SB][PASS] ch%0d error reported as expected. %s", ch, x.show());
      end
      return;                      // data is undefined after an error
    end

    if (err) begin
      $error("[SB][FAIL] ch%0d reported an unexpected error. %s", ch, x.show());
      n_errors++;
      return;
    end

    bad = 0;
    for (int unsigned i = 0; i < x.nbytes; i++) begin
      got = axi_mem_pkg::rd_byte(x.dst + i);
      if (got !== x.exp[i]) begin
        if (bad < 4) begin
          $error("[SB][FAIL] ch%0d byte %0d at %0h: got %02h expected %02h. %s",
                 ch, i, x.dst + i, got, x.exp[i], x.show());
        end
        bad++;
      end
    end

    if (bad != 0) begin
      n_errors++;
      $error("[SB][FAIL] ch%0d had %0d mismatching bytes of %0d", ch, bad, x.nbytes);
    end else if (verbose) begin
      $display("[SB][PASS] ch%0d %s", ch, x.show());
    end
  endfunction

  function bit idle();
    return (pend.size() == 0) && (act.num() == 0);
  endfunction

  function void report();
    $display("--------------------------------------------------------------");
    $display("[SB] transfers checked : %0d", n_checked);
    $display("[SB] transfers failed  : %0d", n_errors);
    $display("[SB] still outstanding : %0d pending, %0d in flight",
             pend.size(), act.num());
    $display("--------------------------------------------------------------");
  endfunction

endclass
