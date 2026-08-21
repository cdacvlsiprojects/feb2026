package L1_cache_mem;

typedef enum logic [3:0]{
    INVALID,IS_D,IM_D,SHARED,SM_D,EXCLUSIVE,EI_A,MODIFIED,MI_A
} MESI_STATES_t;

typedef struct packed{
    logic valid;
    MESI_STATES_t C_tag;
    logic [3:0]tag;
    logic [7:0]data;
}l1_cache_line_t;

typedef enum logic [2:0] {
    IDLE,COMPARE,ALLOCATE,DONE,SNOOP,WRITEBACK
} C_STATES_t;

typedef enum logic [3:0] {
    MSG_GETS,
    MSG_GETM,
    MSG_PUTE,
    MSG_PUTM,
    MSG_UNBLOCK,
    MSG_INVACK,
    MSG_DATAFWD,
    MSG_ACK,
    MSG_L1_NONE
} l1_msg_out_t;

typedef enum logic [2:0] {
    MSG_FWD_GETS,
    MSG_FWD_GETM,
    MSG_INV,
    MSG_DATA,
    MSG_NONE
} l1_msg_in_t;


typedef enum logic [2:0] { ACTION_HIT, ACTION_STALL_TRANSIENT, ACTION_MISS, ACTION_UPGRADE ,ACTION_ACK_VACUOUS,ACTION_INVALIDATE,ACTION_FORWARD} l1_action_t;

typedef struct packed {
    l1_action_t   action;
     l1_msg_out_t  msg_to_send;
     l1_msg_out_t msg_to_dir;
    MESI_STATES_t next_state;
} l1_decision_t;
endpackage

package l2_cache_pkg;
import L1_cache_mem::*;

    typedef enum logic [3:0] {
        DIR_I, DIR_S, DIR_E, DIR_M,
        DIR_MEM_WAIT, DIR_FWD_WAIT, DIR_INV_WAIT,
        DIR_EVICT_INV_WAIT, DIR_EVICT_FWD_WAIT, DIR_EVICT_WB,
        PROXY_WAIT
    } dir_state_t;

    typedef struct packed {
        logic        valid;
        dir_state_t  C_tag;
        logic [3:0]  tag;
        logic [3:0]  sharers;   
        logic [1:0]  owner_id;   
        logic [7:0]  data;
    } l2_cache_line_t;

    typedef enum logic [2:0] {
        L2_IDLE, L2_COMPARE, L2_ALLOCATE, L2_DONE, L2_SNOOP
    } L2_STATES_t;

    typedef enum logic [3:0] {
        NMSG_GETS, NMSG_GETM, NMSG_PUTE, NMSG_PUTM,
        NMSG_UNBLOCK, NMSG_INVACK, NMSG_DATAFWD, NMSG_ACK,
        NMSG_FWD_GETS, NMSG_FWD_GETM, NMSG_INV, NMSG_DATA,
        NMSG_MEM_REQ, NMSG_MEM_DATA,
        NMSG_NONE
    } l2_nic_msg_t;


    typedef struct packed {
        l2_nic_msg_t msg;
        logic        we;              
        logic        is_exclusive_in;
        logic [7:0]  addr;
        logic [7:0]  data;
        logic [2:0]  src_id;
        logic [2:0]  dest_id;
    } l2_nic_pkt_t;

   typedef struct packed {
    l1_msg_in_t  msg_in;
    logic is_exclusive_in;
    logic [7:0]addr;
    logic [7:0]data;
    logic [1:0]requester_id;
}l2_li_data_t;

    typedef enum logic [2:0] {
        L2_ACTION_HIT,             
        L2_ACTION_UPGRADE_INV,     // DIR_S + GetM
        L2_ACTION_FORWARD,         // DIR_E/DIR_M
        L2_ACTION_MISS,            // no tag match,
        L2_ACTION_EVICT_INV,       // no tag match, victim is DIR_S: invalidate its sharers first
        L2_ACTION_EVICT_RECALL,    // no tag match, victim is DIR_E/DIR_M: recall from owner first
        L2_ACTION_PUT_ACK,         // PutM/PutE: just ack
        L2_ACTION_NONE
    } l2_action_t;

    typedef struct packed {
        l2_action_t   action;
        l1_msg_in_t   msg_to_send;  
        dir_state_t   next_state;
        logic [1:0]   target_id;     
    } l2_decision_t;

endpackage

import L1_cache_mem::*;
import l2_cache_pkg::*;



module tile_tb_stable;

    logic clk, rst;

    logic [7:0] l1_data_out0, l1_data_out1;
    logic [9:0] l1_inst0,     l1_inst1;
    logic [7:0] l1_in_data0,  l1_in_data1;

    logic [31:0] t0_c_out, t0_cc_out, t1_c_out, t1_cc_out;
    logic        t0_c_valid, t0_cc_valid, t1_c_valid, t1_cc_valid;

    tile_top #(.MY_BANK_ID(2'd0)) dut0 (
        .clk(clk), .rst(rst),
        .l1_data_out(l1_data_out0), .l1_inst(l1_inst0), .l1_in_data(l1_in_data0),
        .c_in(t1_c_out),  .c_wr(t1_c_valid),  .c_out(t0_c_out),  .c_out_valid(t0_c_valid),
        .cc_in(t1_cc_out), .cc_wr(t1_cc_valid), .cc_out(t0_cc_out), .cc_out_valid(t0_cc_valid)
    );

    tile_top #(.MY_BANK_ID(2'd1)) dut1 (
        .clk(clk), .rst(rst),
        .l1_data_out(l1_data_out1), .l1_inst(l1_inst1), .l1_in_data(l1_in_data1),
        .c_in(t0_c_out),  .c_wr(t0_c_valid),  .c_out(t1_c_out),  .c_out_valid(t1_c_valid),
        .cc_in(t0_cc_out), .cc_wr(t0_cc_valid), .cc_out(t1_cc_out), .cc_out_valid(t1_cc_valid)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        wait (rst == 1'b0);
        dut0.u_mem_tap.preload(8'h01, 8'd10);
        dut1.u_mem_tap.preload(8'h15, 8'd41);
        dut0.u_mem_tap.preload(8'h40, 8'd99);
        dut0.u_mem_tap.preload(8'h80, 8'd88);  
    end

    initial begin
        $monitor(
            "T=%0t | T0: L1(%s) L2(%s/%s) | T1: L1(%s) L2(%s/%s)",
            $time,
            dut0.u_c1_ctrl.C_PS.name(), dut0.u_c2_ctrl.C_PS.name(), dut0.u_c2_ctrl.pending_state.name(),
            dut1.u_c1_ctrl.C_PS.name(), dut1.u_c2_ctrl.C_PS.name(), dut1.u_c2_ctrl.pending_state.name()
        );
    end

    always @(posedge clk) begin
        if (t0_c_valid || t0_cc_valid)
            $display("T=%0t  T0 -> ring: c_valid=%0b c=%h  cc_valid=%0b cc=%h",
                $time, t0_c_valid, t0_c_out, t0_cc_valid, t0_cc_out);
        if (t1_c_valid || t1_cc_valid)
            $display("T=%0t  T1 -> ring: c_valid=%0b c=%h  cc_valid=%0b cc=%h",
                $time, t1_c_valid, t1_c_out, t1_cc_valid, t1_cc_out);
    end

    task automatic dump_all(input string tag);
        automatic int s, w;
        $display("======== CACHE DUMP [%s] @ T=%0t ========", tag, $time);
        $display("  T0 L1:");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 2; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s",
                    s, w, dut0.c1_inf.cache_mem_out[s][w].valid,
                    dut0.c1_inf.cache_mem_out[s][w].tag, dut0.c1_inf.cache_mem_out[s][w].C_tag.name());
        $display("  T1 L1:");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 2; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s",
                    s, w, dut1.c1_inf.cache_mem_out[s][w].valid,
                    dut1.c1_inf.cache_mem_out[s][w].tag, dut1.c1_inf.cache_mem_out[s][w].C_tag.name());
        $display("  T0 L2 (ALL 4 sets):");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 4; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s owner=%0d sharers=%02b",
                    s, w, dut0.c2_inf.cache_mem_out[s][w].valid, dut0.c2_inf.cache_mem_out[s][w].tag,
                    dut0.c2_inf.cache_mem_out[s][w].C_tag.name(), dut0.c2_inf.cache_mem_out[s][w].owner_id,
                    dut0.c2_inf.cache_mem_out[s][w].sharers);
        $display("  T1 L2 (ALL 4 sets):");
        for (s = 0; s < 4; s++)
            for (w = 0; w < 4; w++)
                $display("    set=%0d way=%0d valid=%0b tag=%0h state=%s owner=%0d sharers=%02b",
                    s, w, dut1.c2_inf.cache_mem_out[s][w].valid, dut1.c2_inf.cache_mem_out[s][w].tag,
                    dut1.c2_inf.cache_mem_out[s][w].C_tag.name(), dut1.c2_inf.cache_mem_out[s][w].owner_id,
                    dut1.c2_inf.cache_mem_out[s][w].sharers);
    endtask

    task do_load0(input [7:0] addr);
        begin
            l1_inst0 <= {2'b01, addr};
            @(posedge clk); @(posedge clk);
            l1_inst0 <= 10'b0;
            wait (dut0.u_c1_ctrl.C_PS == IDLE);
            #10;
        end
    endtask

    task do_load1(input [7:0] addr);
        begin
            l1_inst1 <= {2'b01, addr};
            @(posedge clk); @(posedge clk);
            l1_inst1 <= 10'b0;
            wait (dut1.u_c1_ctrl.C_PS == IDLE);
            #10;
        end
    endtask

    task do_store0(input [7:0] addr, input [7:0] data);
        begin
            l1_in_data0 <= data;
            l1_inst0 <= {2'b10, addr};
            @(posedge clk); @(posedge clk);
            l1_inst0 <= 10'b0;
            wait (dut0.u_c1_ctrl.C_PS == IDLE);
            #10;
        end
    endtask

    initial begin
        rst = 1'b1;
        l1_inst0 = 10'b0; l1_in_data0 = 8'h00;
        l1_inst1 = 10'b0; l1_in_data1 = 8'h00;
        #25;
        rst = 1'b0;
        @(posedge clk);

        dump_all("INITIAL");

        $display("\n>>>>>>>> TEST 1: T0 LOAD 0x01 -- read miss, fetch from memory, EXCLUSIVE <<<<<<<<\n");
        do_load0(8'h01);
        dump_all("AFTER TEST 1");

        $display("\n>>>>>>>> TEST 2: T1 LOAD 0x15 -- independent read miss, own bank <<<<<<<<\n");
        do_load1(8'h15);
        dump_all("AFTER TEST 2");

        $display("\n>>>>>>>> TEST 4: T0 STORE 0x40 -- write miss (GetM), fetch from memory, MODIFIED directly (L2 set1) <<<<<<<<\n");
        do_store0(8'h40, 8'd55);
        dump_all("AFTER TEST 4");

        $display("\n>>>>>>>> TEST 6: T1 LOAD 0x80 -- T1 reads cold from T0's L2 bank (genuine cross-tile MISS fetch, no L1 owner involved) <<<<<<<<\n");
        do_load1(8'h80);
        dump_all("AFTER TEST 6");

        do_store0(8'h01, 8'd77);
        dump_all("AFTER TEST 7");

        $display("\n--- FINAL CHECKS ---");
        if (dut0.c1_inf.cache_mem_out[0][0].valid && dut0.c1_inf.cache_mem_out[0][0].tag == 4'h0 &&
            dut0.c1_inf.cache_mem_out[0][0].C_tag == EXCLUSIVE)
            $display("  PASS: T0 L1 0x01 is EXCLUSIVE");
        else
            $display("  FAIL: T0 L1 0x01 state=%s", dut0.c1_inf.cache_mem_out[0][0].C_tag.name());

        if (dut1.c1_inf.cache_mem_out[1][0].valid && dut1.c1_inf.cache_mem_out[1][0].tag == 4'h1 &&
            dut1.c1_inf.cache_mem_out[1][0].C_tag == EXCLUSIVE)
            $display("  PASS: T1 L1 0x15 is EXCLUSIVE");
        else
            $display("  FAIL: T1 L1 0x15 state=%s", dut1.c1_inf.cache_mem_out[1][0].C_tag.name());

        if (dut0.c1_inf.cache_mem_out[0][1].valid && dut0.c1_inf.cache_mem_out[0][1].tag == 4'h4 &&
            dut0.c1_inf.cache_mem_out[0][1].C_tag == MODIFIED)
            $display("  PASS: T0 L1 0x40 is MODIFIED");
        else
            $display("  FAIL: T0 L1 0x40 state=%s", dut0.c1_inf.cache_mem_out[0][1].C_tag.name());

        if (dut0.c2_inf.cache_mem_out[1][0].valid && dut0.c2_inf.cache_mem_out[1][0].tag == 4'h0 &&
            dut0.c2_inf.cache_mem_out[1][0].C_tag == DIR_M && dut0.c2_inf.cache_mem_out[1][0].owner_id == 2'd0)
            $display("  PASS: T0 L2 SET1 directory for 0x40 is DIR_M owner=0");
        else
            $display("  FAIL: T0 L2 SET1 directory for 0x40 state=%s owner=%0d",
                dut0.c2_inf.cache_mem_out[1][0].C_tag.name(), dut0.c2_inf.cache_mem_out[1][0].owner_id);

        if (dut1.c1_inf.cache_mem_out[0][0].valid && dut1.c1_inf.cache_mem_out[0][0].tag == 4'h8 &&
            dut1.c1_inf.cache_mem_out[0][0].C_tag == EXCLUSIVE)
            $display("  PASS: T1 L1 0x80 is EXCLUSIVE (fetched cold from T0's bank)");
        else
            $display("  FAIL: T1 L1 0x80 state=%s", dut1.c1_inf.cache_mem_out[0][0].C_tag.name());

        if (dut0.c2_inf.cache_mem_out[2][0].valid && dut0.c2_inf.cache_mem_out[2][0].tag == 4'h0 &&
            dut0.c2_inf.cache_mem_out[2][0].C_tag == DIR_E && dut0.c2_inf.cache_mem_out[2][0].owner_id == 2'd1)
            $display("  PASS: T0 L2 SET2 directory for 0x80 is DIR_E owner=1 (T1, the remote requester)");
        else
            $display("  FAIL: T0 L2 SET2 directory for 0x80 state=%s owner=%0d",
                dut0.c2_inf.cache_mem_out[2][0].C_tag.name(), dut0.c2_inf.cache_mem_out[2][0].owner_id);

       
        if (dut0.c1_inf.cache_mem_out[0][0].valid && dut0.c1_inf.cache_mem_out[0][0].tag == 4'h0 &&
            dut0.c1_inf.cache_mem_out[0][0].C_tag == MODIFIED)
            $display("  PASS: T0 L1 0x01 is MODIFIED (silently upgraded from EXCLUSIVE, purely local)");
        else
            $display("  FAIL: T0 L1 0x01 state=%s", dut0.c1_inf.cache_mem_out[0][0].C_tag.name());
        $display("  INFO: T0 L2 set0 directory for 0x01 shows state=%s (either DIR_E or DIR_M can be correct here depending on whether this design notifies L2 of a silent upgrade -- both mean 'single owner, no sharers' to the directory)",
            dut0.c2_inf.cache_mem_out[0][0].C_tag.name());

        $display("\n--- done ---");
        $finish;
    end

endmodule