
// UVM Verification Package

`timescale 1ns/1ps
package bridge_pkg;
  import uvm_pkg::*;
`include "uvm_macros.svh"

  // Sequence Items
  
  class axi_transaction extends uvm_sequence_item;
    rand bit         is_write;
    rand logic [31:0] addr;
    rand logic [2:0]  prot;
    rand logic [31:0] data;
    rand logic [3:0]  strb;
    logic [31:0]      rdata;
    logic [1:0]       resp;

    constraint c_addr_align { addr[1:0] == 2'b00; }
    constraint c_default_strb { soft strb == 4'hF; }

    `uvm_object_utils_begin(axi_transaction)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(prot,     UVM_ALL_ON)
      `uvm_field_int(data,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(strb,     UVM_ALL_ON)
      `uvm_field_int(rdata,    UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(resp,     UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_transaction"); super.new(name); endfunction

    virtual function string convert2string();
      if (is_write)
        return $sformatf("AXI WRITE -> Addr: 0x%08h | Data: 0x%08h | Strb: 0x%1h | Resp: 2'b%02b", addr, data, strb, resp);
      else
        return $sformatf("AXI READ  -> Addr: 0x%08h | RData: 0x%08h | Resp: 2'b%02b", addr, rdata, resp);
    endfunction
  endclass

  class apb_transaction extends uvm_sequence_item;
    rand bit         is_write;
    rand logic [31:0] addr;
    rand logic [2:0]  prot;
    rand logic [3:0]  strb;
    rand logic [31:0] data;
    logic             slverr;

    constraint c_apb_addr_align { addr[1:0] == 2'b00; }

    `uvm_object_utils_begin(apb_transaction)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(prot,     UVM_ALL_ON)
      `uvm_field_int(strb,     UVM_ALL_ON)
      `uvm_field_int(data,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(slverr,   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_transaction"); super.new(name); endfunction

    virtual function string convert2string();
      if (is_write)
        return $sformatf("APB WRITE -> Addr: 0x%08h | Data: 0x%08h | Strb: 0x%1h | Err: %0b", addr, data, strb, slverr);
      else
        return $sformatf("APB READ  -> Addr: 0x%08h | Data: 0x%08h | Err: %0b", addr, data, slverr);
    endfunction
  endclass

  // Sequencers
  class axi_sequencer extends uvm_sequencer #(axi_transaction);
    `uvm_component_utils(axi_sequencer)
    function new(string name = "axi_sequencer", uvm_component parent = null); super.new(name, parent); endfunction
  endclass

  class apb_sequencer extends uvm_sequencer #(apb_transaction);
    `uvm_component_utils(apb_sequencer)
    function new(string name = "apb_sequencer", uvm_component parent = null); super.new(name, parent); endfunction
  endclass

  // Sequences
  class axi_base_sequence extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_base_sequence)
    function new(string name = "axi_base_sequence"); super.new(name); endfunction
  endclass

  class axi_write_read_seq extends axi_base_sequence;
    `uvm_object_utils(axi_write_read_seq)
    rand logic [31:0] target_addr;
    rand logic [31:0] write_data;

    function new(string name = "axi_write_read_seq"); super.new(name); endfunction

    virtual task body();
      req = axi_transaction::type_id::create("req_wr");
      start_item(req);
      if (!req.randomize() with { is_write == 1'b1; addr == target_addr; data == write_data; })
        `uvm_fatal("RAW_SEQ", "Randomization failed for Write!")
      finish_item(req);

      req = axi_transaction::type_id::create("req_rd");
      start_item(req);
      if (!req.randomize() with { is_write == 1'b0; addr == target_addr; })
        `uvm_fatal("RAW_SEQ", "Randomization failed for Read!")
      finish_item(req);
    endtask
  endclass

  class axi_rand_stress_sequence extends axi_base_sequence;
    `uvm_object_utils(axi_rand_stress_sequence)
    rand int unsigned num_trans;
    constraint c_trans_cnt { soft num_trans inside {[20 : 50]}; }

    function new(string name = "axi_rand_stress_sequence"); super.new(name); endfunction

    virtual task body();
      `uvm_info(get_type_name(), $sformatf("Starting stress sequence: %0d transfers", num_trans), UVM_LOW)
      for (int i = 0; i < num_trans; i++) begin
        req = axi_transaction::type_id::create("req");
        start_item(req);
        if (!req.randomize() with {
            addr[31:12] dist {
                20'h10000 := 20, 20'h20000 := 20, 
                20'h30000 := 20, 20'h40000 := 20, 
                20'h90000 := 20  
            };
        }) `uvm_fatal("STRESS_SEQ", "Randomization failed!")
        finish_item(req);
      end
    endtask
  endclass

  // NEW SEQUENCES FOR THE 5 TEST CASES
  class axi_single_write_seq extends axi_base_sequence;
    `uvm_object_utils(axi_single_write_seq)
    function new(string name = "axi_single_write_seq"); super.new(name); endfunction
    virtual task body();
      req = axi_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { is_write == 1'b1; addr inside {32'h1000_0000, 32'h2000_0000}; })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(req);
    endtask
  endclass

  class axi_single_read_seq extends axi_base_sequence;
    `uvm_object_utils(axi_single_read_seq)
    function new(string name = "axi_single_read_seq"); super.new(name); endfunction
    virtual task body();
      req = axi_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { is_write == 1'b0; addr inside {32'h1000_0000, 32'h2000_0000}; })
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(req);
    endtask
  endclass

  class axi_unmapped_seq extends axi_base_sequence;
    `uvm_object_utils(axi_unmapped_seq)
    function new(string name = "axi_unmapped_seq"); super.new(name); endfunction
    virtual task body();
      req = axi_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { addr[31:12] == 20'h50000; }) 
        `uvm_fatal("SEQ", "Randomization failed")
      finish_item(req);
    endtask
  endclass

  class axi_multi_slave_seq extends axi_base_sequence;
    `uvm_object_utils(axi_multi_slave_seq)
    function new(string name = "axi_multi_slave_seq"); super.new(name); endfunction
    virtual task body();
      logic [31:0] addrs[4] = '{32'h1000_0000, 32'h2000_0004, 32'h3000_0008, 32'h4000_000C};
      for (int i=0; i<4; i++) begin
        req = axi_transaction::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { is_write == 1'b1; addr == addrs[i]; }) `uvm_fatal("SEQ", "Randomization failed")
        finish_item(req);
      end
    endtask
  endclass

  class axi_b2b_seq extends axi_base_sequence;
    `uvm_object_utils(axi_b2b_seq)
    function new(string name = "axi_b2b_seq"); super.new(name); endfunction
    virtual task body();
      for (int i=0; i<10; i++) begin
        req = axi_transaction::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { 
            addr[31:12] inside {20'h10000, 20'h20000, 20'h30000, 20'h40000}; 
        }) `uvm_fatal("SEQ", "Randomization failed")
        finish_item(req);
      end
    endtask
  endclass

  // Drivers
  class axi_driver extends uvm_driver #(axi_transaction);
    `uvm_component_utils(axi_driver)
    virtual axi4_lite_apb4_if #(32, 32, 4) vif;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "Virtual interface 'vif' not set!")
    endfunction

    virtual task run_phase(uvm_phase phase);
      reset_signals();
      forever begin
        wait (vif.rst_n == 1'b1);
        seq_item_port.get_next_item(req);
        if (req.is_write) drive_write(req);
        else              drive_read(req);
        seq_item_port.item_done();
      end
    endtask

    virtual task reset_signals();
      wait (vif.rst_n == 1'b0);
      vif.s_axi_awvalid <= 1'b0; vif.s_axi_wvalid <= 1'b0; vif.s_axi_bready <= 1'b0;
      vif.s_axi_arvalid <= 1'b0; vif.s_axi_rready <= 1'b0;
    endtask

    virtual task drive_write(axi_transaction tr);
      @(posedge vif.clk);
      vif.s_axi_awaddr  <= tr.addr; vif.s_axi_awprot <= tr.prot; vif.s_axi_awvalid <= 1'b1;
      vif.s_axi_wdata   <= tr.data; vif.s_axi_wstrb  <= tr.strb; vif.s_axi_wvalid  <= 1'b1;

      fork
        begin do @(posedge vif.clk); while (!vif.s_axi_awready); vif.s_axi_awvalid <= 1'b0; end
        begin do @(posedge vif.clk); while (!vif.s_axi_wready);  vif.s_axi_wvalid  <= 1'b0; end
      join

      vif.s_axi_bready <= 1'b1;
      do @(posedge vif.clk); while (!vif.s_axi_bvalid);
      tr.resp          = vif.s_axi_bresp;
      vif.s_axi_bready <= 1'b0;
    endtask

    virtual task drive_read(axi_transaction tr);
      @(posedge vif.clk);
      vif.s_axi_araddr  <= tr.addr; vif.s_axi_arprot <= tr.prot; vif.s_axi_arvalid <= 1'b1;
      do @(posedge vif.clk); while (!vif.s_axi_arready);
      vif.s_axi_arvalid <= 1'b0; 

      vif.s_axi_rready <= 1'b1;
      do @(posedge vif.clk); while (!vif.s_axi_rvalid);
      tr.rdata         = vif.s_axi_rdata; 
      tr.resp          = vif.s_axi_rresp;
      vif.s_axi_rready <= 1'b0;
    endtask
  endclass

  // APB Slave Driver
  class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils(apb_driver)
    virtual axi4_lite_apb4_if #(32, 32, 4) vif;

    logic [31:0] apb_mem [4][1024];

    function new(string name, uvm_component parent = null);
      super.new(name, parent);
      for (int i = 0; i < 4; i++) begin
        for (int j = 0; j < 1024; j++) begin
          apb_mem[i][j] = 32'h1000_0000 | (i << 16) | (j << 2);
        end
      end
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "Virtual interface 'vif' not set!")
    endfunction

    virtual task run_phase(uvm_phase phase);
      vif.m_apb_pready  <= 1'b0; 
      vif.m_apb_prdata  <= '0; 
      vif.m_apb_pslverr <= 1'b0;

      forever begin
        @(posedge vif.clk);
        if (!vif.rst_n) begin
          vif.m_apb_pready  <= 1'b0; 
          vif.m_apb_prdata  <= '0;
          vif.m_apb_pslverr <= 1'b0;
        end 
        else if (|vif.m_apb_psel) begin
          if (vif.m_apb_penable) begin
            vif.m_apb_pready <= 1'b1;

            if (vif.m_apb_pwrite) begin
              apb_mem[get_slave_idx(vif.m_apb_psel)][vif.m_apb_paddr[11:2]] <= vif.m_apb_pwdata;
            end else begin
              vif.m_apb_prdata <= apb_mem[get_slave_idx(vif.m_apb_psel)][vif.m_apb_paddr[11:2]];
            end
          end else begin
            if (!vif.m_apb_pwrite) begin
              vif.m_apb_prdata <= apb_mem[get_slave_idx(vif.m_apb_psel)][vif.m_apb_paddr[11:2]];
            end
            vif.m_apb_pready <= 1'b0;
          end
        end else begin
          vif.m_apb_pready <= 1'b0;
        end
      end
    endtask

    function int get_slave_idx(logic [3:0] psel);
      case (psel)
        4'b0001: return 0;
        4'b0010: return 1;
        4'b0100: return 2;
        4'b1000: return 3;
        default: return 0;
      endcase
    endfunction
  endclass

  // Monitors
  class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi4_lite_apb4_if #(32, 32, 4) vif;
    uvm_analysis_port #(axi_transaction) ap;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::get(this, "", "vif", vif))
        `uvm_fatal("MON", "Virtual interface 'vif' not set!")
    endfunction

    virtual task run_phase(uvm_phase phase);
      forever begin
        wait (vif.rst_n == 1'b1);
        fork
          sample_write_tx();
          sample_read_tx();
        join_none
        wait (vif.rst_n == 1'b0);
        disable fork;
      end
    endtask

    virtual task sample_write_tx();
      axi_transaction tr;
      bit aw_done, w_done;
      logic [31:0] addr, data;
      logic [2:0]  prot;
      logic [3:0]  strb;
      logic [1:0]  resp;

      forever begin
        aw_done = 1'b0; w_done = 1'b0;
        while (!(aw_done && w_done)) begin
          @(posedge vif.clk);
          if (!aw_done && vif.s_axi_awvalid && vif.s_axi_awready && vif.rst_n) begin
            addr = vif.s_axi_awaddr; prot = vif.s_axi_awprot; aw_done = 1'b1;
          end
          if (!w_done && vif.s_axi_wvalid && vif.s_axi_wready && vif.rst_n) begin
            data = vif.s_axi_wdata; strb = vif.s_axi_wstrb; w_done = 1'b1;
          end
        end

        do @(posedge vif.clk); while (!(vif.s_axi_bvalid && vif.s_axi_bready && vif.rst_n));
        resp = vif.s_axi_bresp;

        tr          = axi_transaction::type_id::create("tr_mon_write");
        tr.is_write = 1'b1; tr.addr = addr; tr.prot = prot;
        tr.data     = data; tr.strb = strb; tr.resp = resp;
        ap.write(tr);
      end
    endtask

    virtual task sample_read_tx();
      axi_transaction tr;
      forever begin
        do @(posedge vif.clk); while (!(vif.s_axi_arvalid && vif.s_axi_arready && vif.rst_n));
        tr          = axi_transaction::type_id::create("tr_mon_read");
        tr.is_write = 1'b0; tr.addr = vif.s_axi_araddr; tr.prot = vif.s_axi_arprot;

        do @(posedge vif.clk); while (!(vif.s_axi_rvalid && vif.s_axi_rready && vif.rst_n));
        tr.rdata = vif.s_axi_rdata; tr.resp = vif.s_axi_rresp;
        ap.write(tr);
      end
    endtask
  endclass

  class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)
    virtual axi4_lite_apb4_if #(32, 32, 4) vif;
    uvm_analysis_port #(apb_transaction) ap;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::get(this, "", "vif", vif))
        `uvm_fatal("MON", "Virtual interface 'vif' not set!")
    endfunction

    virtual task run_phase(uvm_phase phase);
      apb_transaction tr;
      forever begin
        @(posedge vif.clk);
        if (|vif.m_apb_psel && vif.m_apb_penable && vif.m_apb_pready && vif.rst_n) begin
          tr          = apb_transaction::type_id::create("tr_apb_mon");
          tr.is_write = vif.m_apb_pwrite;
          tr.addr     = vif.m_apb_paddr;
          tr.prot     = vif.m_apb_pprot;
          tr.strb     = vif.m_apb_pstrb;
          tr.data     = vif.m_apb_pwrite ? vif.m_apb_pwdata : vif.m_apb_prdata;
          tr.slverr   = vif.m_apb_pslverr;
          ap.write(tr);
        end
      end
    endtask
  endclass

  // Agents
  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_driver                            drv;
    axi_sequencer                         sqr;
    axi_monitor                           mon;
    uvm_analysis_port #(axi_transaction)  ap;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap  = new("ap", this);
      mon = axi_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
        drv = axi_driver::type_id::create("drv", this);
        sqr = axi_sequencer::type_id::create("sqr", this);
      end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      mon.ap.connect(ap);
      if (get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)
    apb_driver                            drv;
    apb_sequencer                         sqr;
    apb_monitor                           mon;
    uvm_analysis_port #(apb_transaction)  ap;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap  = new("ap", this);
      mon = apb_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
        drv = apb_driver::type_id::create("drv", this);
        sqr = apb_sequencer::type_id::create("sqr", this);
      end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      mon.ap.connect(ap);
      if (get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // Scoreboard
  class bridge_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(bridge_scoreboard)

    uvm_analysis_export #(axi_transaction) axi_export;
    uvm_analysis_export #(apb_transaction) apb_export;
    uvm_tlm_analysis_fifo #(axi_transaction) axi_fifo;
    uvm_tlm_analysis_fifo #(apb_transaction) apb_fifo;

    int match_count = 0, mismatch_count = 0;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      axi_export = new("axi_export", this);
      apb_export = new("apb_export", this);
      axi_fifo   = new("axi_fifo", this);
      apb_fifo   = new("apb_fifo", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      axi_export.connect(axi_fifo.analysis_export);
      apb_export.connect(apb_fifo.analysis_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
      axi_transaction axi_tr; 
      apb_transaction apb_tr;
      forever begin
        axi_fifo.get(axi_tr); 
        
        if (axi_tr.addr[31:12] != 20'h10000 && 
            axi_tr.addr[31:12] != 20'h20000 && 
            axi_tr.addr[31:12] != 20'h30000 && 
            axi_tr.addr[31:12] != 20'h40000) begin
            
            if (axi_tr.resp != 2'b11) begin
                mismatch_count++;
                `uvm_error("SCB_FAIL", $sformatf("Expected SLVERR (2'b11) for unmapped Addr 0x%08h, got 2'b%02b", axi_tr.addr, axi_tr.resp))
            end else begin
                match_count++;
                `uvm_info("SCB_PASS", $sformatf("MATCH -> Unmapped Addr 0x%08h cleanly errored", axi_tr.addr), UVM_MEDIUM)
            end
        end else begin
            apb_fifo.get(apb_tr);
            compare(axi_tr, apb_tr);
        end
      end
    endtask

    virtual function void compare(axi_transaction axi, apb_transaction apb);
      bit err = 1'b0;
      if (axi.is_write != apb.is_write) err = 1'b1;
      if (axi.addr     != apb.addr)     err = 1'b1;
      if (axi.is_write && (axi.data != apb.data)) err = 1'b1;
      if (!axi.is_write && (axi.rdata != apb.data)) err = 1'b1;

      if (apb.slverr && (axi.resp != 2'b11)) err = 1'b1;

      if (err) begin
        mismatch_count++;
        `uvm_error("SCB_FAIL", $sformatf("MISMATCH -> AXI: %s || APB: %s", axi.convert2string(), apb.convert2string()))
      end else begin
        match_count++;
        `uvm_info("SCB_PASS", $sformatf("MATCH -> Addr: 0x%08h Data: 0x%08h", axi.addr, apb.data), UVM_MEDIUM)
      end
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SCB_SUMMARY", $sformatf("FINAL RESULT: Matches=%0d Mismatches=%0d", match_count, mismatch_count), UVM_LOW)
    endfunction
  endclass

  // Environment
  class bridge_env extends uvm_env;
    `uvm_component_utils(bridge_env)

    axi_agent         axi_agtn;
    apb_agent         apb_agtn;
    bridge_scoreboard scb;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      axi_agtn = axi_agent::type_id::create("axi_agtn", this);
      apb_agtn = apb_agent::type_id::create("apb_agtn", this);
      scb      = bridge_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      axi_agtn.ap.connect(scb.axi_export);
      apb_agtn.ap.connect(scb.apb_export);
    endfunction
  endclass

  // Base Test
  class bridge_base_test extends uvm_test;
    `uvm_component_utils(bridge_base_test)
    bridge_env env;

    function new(string name, uvm_component parent = null); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      uvm_top.set_report_verbosity_level(UVM_MEDIUM);
      env = bridge_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      uvm_top.print_topology();
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
      super.start_of_simulation_phase(phase);
      uvm_top.set_timeout(1ms, 0);
    endfunction
  endclass

  // Original Tests
  class bridge_random_test extends bridge_base_test;
    `uvm_component_utils(bridge_random_test)
    function new(string name = "bridge_random_test", uvm_component parent = null); super.new(name, parent); endfunction

    virtual task run_phase(uvm_phase phase);
      axi_rand_stress_sequence stress_seq;
      phase.raise_objection(this, "Starting Random Stress Test");
      `uvm_info("RAND_TEST", "--- RUNNING RANDOM STRESS TEST ---", UVM_LOW)
      
      stress_seq = axi_rand_stress_sequence::type_id::create("stress_seq");
      if (!stress_seq.randomize() with { num_trans == 50; }) 
        `uvm_fatal("RAND_TEST", "Randomization failed for stress_seq!")
      
      stress_seq.start(env.axi_agtn.sqr);
      #200ns;
      `uvm_info("RAND_TEST", "--- COMPLETED STRESS TEST ---", UVM_LOW)
      phase.drop_objection(this, "Finished Random Stress Test");
    endtask
  endclass

  class bridge_raw_test extends bridge_base_test;
    `uvm_component_utils(bridge_raw_test)
    function new(string name = "bridge_raw_test", uvm_component parent = null); super.new(name, parent); endfunction

    virtual task run_phase(uvm_phase phase);
      axi_write_read_seq raw_seq;
      phase.raise_objection(this, "Starting Read-After-Write Test");
      `uvm_info("RAW_TEST", "--- RUNNING WRITE-FOLLOWED-BY-READ TEST ---", UVM_LOW)
      
      raw_seq = axi_write_read_seq::type_id::create("raw_seq");
      if (!raw_seq.randomize() with { target_addr == 32'h1000_0004; write_data == 32'hA5A5_1234; }) 
        `uvm_fatal("RAW_TEST", "Randomization failed for raw_seq!")
      
      raw_seq.start(env.axi_agtn.sqr);
      #100ns;
      `uvm_info("RAW_TEST", "--- COMPLETED RAW TEST ---", UVM_LOW)
      phase.drop_objection(this, "Finished Read-After-Write Test");
    endtask
  endclass

  // NEW TESTS
  // Test 1: Single Write Scenario
  class bridge_single_write_test extends bridge_base_test;
    `uvm_component_utils(bridge_single_write_test)
    function new(string name = "bridge_single_write_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual task run_phase(uvm_phase phase);
      axi_single_write_seq seq = axi_single_write_seq::type_id::create("seq");
      phase.raise_objection(this);
      `uvm_info("TEST", "--- RUNNING SINGLE WRITE TEST ---", UVM_LOW)
      seq.start(env.axi_agtn.sqr);
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

  // Test 2: Single Read Scenario
  class bridge_single_read_test extends bridge_base_test;
    `uvm_component_utils(bridge_single_read_test)
    function new(string name = "bridge_single_read_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual task run_phase(uvm_phase phase);
      axi_single_read_seq seq = axi_single_read_seq::type_id::create("seq");
      phase.raise_objection(this);
      `uvm_info("TEST", "--- RUNNING SINGLE READ TEST ---", UVM_LOW)
      seq.start(env.axi_agtn.sqr);
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

  // Test 3: Unmapped Address Error Checking
  class bridge_unmapped_test extends bridge_base_test;
    `uvm_component_utils(bridge_unmapped_test)
    function new(string name = "bridge_unmapped_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual task run_phase(uvm_phase phase);
      axi_unmapped_seq seq = axi_unmapped_seq::type_id::create("seq");
      phase.raise_objection(this);
      `uvm_info("TEST", "--- RUNNING UNMAPPED ADDRESS TEST ---", UVM_LOW)
      seq.start(env.axi_agtn.sqr);
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

  // Test 4: Hit all Slaves Verification
  class bridge_multi_slave_test extends bridge_base_test;
    `uvm_component_utils(bridge_multi_slave_test)
    function new(string name = "bridge_multi_slave_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual task run_phase(uvm_phase phase);
      axi_multi_slave_seq seq = axi_multi_slave_seq::type_id::create("seq");
      phase.raise_objection(this);
      `uvm_info("TEST", "--- RUNNING MULTI-SLAVE TEST ---", UVM_LOW)
      seq.start(env.axi_agtn.sqr);
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

  // Test 5: Back-to-Back Fast Tracking
  class bridge_b2b_test extends bridge_base_test;
    `uvm_component_utils(bridge_b2b_test)
    function new(string name = "bridge_b2b_test", uvm_component parent = null); super.new(name, parent); endfunction
    virtual task run_phase(uvm_phase phase);
      axi_b2b_seq seq = axi_b2b_seq::type_id::create("seq");
      phase.raise_objection(this);
      `uvm_info("TEST", "--- RUNNING BACK TO BACK TEST ---", UVM_LOW)
      seq.start(env.axi_agtn.sqr);
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

endpackage

// TOP-LEVEL TESTBENCH HARNESS

module tb_top;
  import uvm_pkg::*;
  import bridge_pkg::*;

  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #25 rst_n = 1'b1;
  end

  axi4_lite_apb4_if #(32, 32, 4) bus_if (.clk(clk), .rst_n(rst_n));

  axi4_lite_to_apb4_bridge #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .NUM_SLAVES(4)
  ) dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .s_axi_awaddr (bus_if.s_axi_awaddr),
      .s_axi_awprot (bus_if.s_axi_awprot),
      .s_axi_awvalid(bus_if.s_axi_awvalid),
      .s_axi_awready(bus_if.s_axi_awready),
      .s_axi_wdata  (bus_if.s_axi_wdata),
      .s_axi_wstrb  (bus_if.s_axi_wstrb),
      .s_axi_wvalid (bus_if.s_axi_wvalid),
      .s_axi_wready (bus_if.s_axi_wready),
      .s_axi_bresp  (bus_if.s_axi_bresp),
      .s_axi_bvalid (bus_if.s_axi_bvalid),
      .s_axi_bready (bus_if.s_axi_bready),
      .s_axi_araddr (bus_if.s_axi_araddr),
      .s_axi_arprot (bus_if.s_axi_arprot),
      .s_axi_arvalid(bus_if.s_axi_arvalid),
      .s_axi_arready(bus_if.s_axi_arready),
      .s_axi_rdata  (bus_if.s_axi_rdata),
      .s_axi_rresp  (bus_if.s_axi_rresp),
      .s_axi_rvalid (bus_if.s_axi_rvalid),
      .s_axi_rready (bus_if.s_axi_rready),
      .m_apb_paddr  (bus_if.m_apb_paddr),
      .m_apb_pprot  (bus_if.m_apb_pprot),
      .m_apb_psel   (bus_if.m_apb_psel),
      .m_apb_penable(bus_if.m_apb_penable),
      .m_apb_pwrite (bus_if.m_apb_pwrite),
      .m_apb_pwdata (bus_if.m_apb_pwdata),
      .m_apb_pstrb  (bus_if.m_apb_pstrb),
      .m_apb_prdata (bus_if.m_apb_prdata),
      .m_apb_pready (bus_if.m_apb_pready),
      .m_apb_pslverr(bus_if.m_apb_pslverr)
  );

  initial begin
    uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::set(null, "*.axi_agtn.*", "vif", bus_if);
    uvm_config_db#(virtual axi4_lite_apb4_if #(32, 32, 4))::set(null, "*.apb_agtn.*", "vif", bus_if);

    // Call run_test() with no arguments to allow override from CLI (e.g., +UVM_TESTNAME=bridge_multi_slave_test)
    // Or keep the hardcoded string to execute a specific test by default.
    run_test("bridge_random_test");
  end

  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end
endmodule
