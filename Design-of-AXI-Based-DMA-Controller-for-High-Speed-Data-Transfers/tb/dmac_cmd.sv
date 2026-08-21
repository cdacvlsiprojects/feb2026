// ---------------------------------------------------------------------------
// dmac_cmd - the randomised CPU instruction.
//
// Only the shape of the transfer is randomised here (length in beats, source
// and destination byte offsets, which slot of the source region to read). The
// driver turns that into concrete addresses, because it also owns destination
// allocation and has to keep concurrent transfers from overlapping.
//
// Tests steer this class by poking the non-rand knobs before randomize().
// ---------------------------------------------------------------------------

class dmac_cmd;

  // ---- knobs (set by the test, not randomised) ----------------------------
  int unsigned strb      = 4;      // bytes per beat
  int unsigned maxb      = 16;     // MAX_BURST_LEN
  int unsigned maxlen    = 40;     // longest transfer, in beats
  int unsigned slots     = 4096;   // aligned slots in the source region
  int unsigned fixed_len = 0;      // 0 = random length
  bit          align_only = 1'b0;  // force both offsets to zero
  bit          near4k     = 1'b0;  // land the source near a 4 KB boundary

  // ---- randomised ---------------------------------------------------------
  rand int unsigned len;           // beats
  rand int unsigned soff;          // source byte offset within a beat
  rand int unsigned doff;          // destination byte offset within a beat
  rand int unsigned slot;          // source slot
  rand int unsigned lsel;          // length-shape selector

  constraint c_lsel { lsel inside {[0:9]}; }

  constraint c_len {
    len >= 1;
    len <= maxlen;
    if (fixed_len != 0)      len == fixed_len;
    else if (lsel == 0)      len == 1;
    else if (lsel == 1)      len == 2;
    else if (lsel == 2)      len == maxb-1;
    else if (lsel == 3)      len == maxb;
    else if (lsel == 4)      len == maxb+1;
  }

  constraint c_off {
    soff < strb;
    doff < strb;
    if (align_only) { soff == 0; doff == 0; }
  }

  constraint c_slot {
    slot < slots;
    if (near4k) (slot % (4096/strb)) > ((4096/strb) - maxb - 2);
  }

  function string show();
    return $sformatf("len=%0d beats soff=%0d doff=%0d slot=%0d", len, soff, doff, slot);
  endfunction

endclass
