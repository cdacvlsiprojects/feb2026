// ---------------------------------------------------------------------------
// dmac_monitor - watches the two events the scoreboard needs:
//   alloc handshake  -> which channel took the next queued command
//   irq  handshake   -> which channel finished, and whether it saw an error
// ---------------------------------------------------------------------------

class dmac_monitor;

  virtual dmac_if vif;
  dmac_scoreboard sb;

  int unsigned n_alloc = 0;
  int unsigned n_done  = 0;
  bit          verbose = 1'b0;

  function new(virtual dmac_if vif, dmac_scoreboard sb);
    this.vif = vif;
    this.sb  = sb;
  endfunction

  task run();
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) continue;

      if (vif.alloc_valid === 1'b1) begin
        sb.allocated(vif.alloc_ch);
        n_alloc++;
        if (verbose) $display("[MON] %0t alloc ch%0d", $time, vif.alloc_ch);
      end

      if ((vif.irq_valid === 1'b1) && (vif.irq_ready === 1'b1)) begin
        sb.completed(vif.irq_ch, vif.irq_err);
        n_done++;
        if (verbose) $display("[MON] %0t irq ch%0d err=%0b", $time, vif.irq_ch, vif.irq_err);
      end
    end
  endtask

endclass
