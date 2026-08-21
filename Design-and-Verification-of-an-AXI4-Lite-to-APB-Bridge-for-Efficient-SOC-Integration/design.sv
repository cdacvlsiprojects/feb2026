`timescale 1ns/1ps

// AXI4_Lite_Slave

module axi4_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                     clk,
    input  logic                     rst_n,
    
    // AXI4-Lite Slave Interface Ports
    input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                s_axi_awprot,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                s_axi_arprot,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // Interlock Link Ports
    output logic [ADDR_WIDTH-1:0]     txn_addr,
    output logic [2:0]                txn_prot,
    output logic [DATA_WIDTH-1:0]     txn_wdata,
    output logic [(DATA_WIDTH/8)-1:0] txn_wstrb,
    output logic                      bridge_write,
    output logic                      bridge_req,   
    input  logic                      bridge_ack,   
    input  logic [DATA_WIDTH-1:0]     txn_rdata,
    input  logic                      bridge_err    
);

    typedef enum logic [1:0] {ST_WR_IDLE, ST_WR_APB_WAIT, ST_WR_AXI_RESP} wr_state_t;
    typedef enum logic [1:0] {ST_RD_IDLE, ST_RD_APB_WAIT, ST_RD_AXI_RESP} rd_state_t;

    wr_state_t wr_state, wr_next;
    rd_state_t rd_state, rd_next;

    logic [ADDR_WIDTH-1:0]     reg_wr_addr, reg_rd_addr;
    logic [2:0]                reg_wr_prot, reg_rd_prot;
    logic [DATA_WIDTH-1:0]     reg_wdata;
    logic [(DATA_WIDTH/8)-1:0] reg_wstrb;

    logic txn_wr_req, txn_rd_req;
    logic txn_wr_gnt, txn_rd_gnt;

    // Write Channel Logic
    always_comb begin
        wr_next       = wr_state;
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        txn_wr_req    = 1'b0;

        case (wr_state)
            ST_WR_IDLE: begin
                if (s_axi_awvalid && s_axi_wvalid) begin
                    s_axi_awready = 1'b1;
                    s_axi_wready  = 1'b1;
                    wr_next       = ST_WR_APB_WAIT;
                end
            end
            ST_WR_APB_WAIT: begin
                txn_wr_req = 1'b1;
                if (txn_wr_gnt && bridge_ack) begin
                    wr_next = ST_WR_AXI_RESP;
                end
            end
            ST_WR_AXI_RESP: begin
                if (s_axi_bready && s_axi_bvalid) begin
                    wr_next = ST_WR_IDLE;
                end
            end
            default: wr_next = ST_WR_IDLE;
        endcase
    end

    // Read Channel Logic
    always_comb begin
        rd_next       = rd_state;
        s_axi_arready = 1'b0;
        txn_rd_req    = 1'b0;

        case (rd_state)
            ST_RD_IDLE: begin
                if (s_axi_arvalid) begin
                    s_axi_arready = 1'b1;
                    rd_next       = ST_RD_APB_WAIT;
                end
            end
            ST_RD_APB_WAIT: begin
                txn_rd_req = 1'b1;
                if (txn_rd_gnt && bridge_ack) begin
                    rd_next = ST_RD_AXI_RESP;
                end
            end
            ST_RD_AXI_RESP: begin
                if (s_axi_rready && s_axi_rvalid) begin
                    rd_next = ST_RD_IDLE;
                end
            end
            default: rd_next = ST_RD_IDLE;
        endcase
    end

    // Read-Priority Arbiter
    logic [ADDR_WIDTH-1:0]     comb_addr;
    logic [2:0]                comb_prot;
    logic [DATA_WIDTH-1:0]     comb_wdata;
    logic [(DATA_WIDTH/8)-1:0] comb_wstrb;
    logic                      comb_write;
    logic                      comb_req;

    always_comb begin
        txn_wr_gnt = 1'b0;
        txn_rd_gnt = 1'b0;
        comb_req   = 1'b0;
        comb_addr  = '0;
        comb_prot  = '0;
        comb_wdata = '0;
        comb_wstrb = '0;
        comb_write = 1'b0;

        if (txn_rd_req) begin
            txn_rd_gnt = 1'b1;
            comb_req   = 1'b1;
            comb_addr  = reg_rd_addr;
            comb_prot  = reg_rd_prot;
            comb_write = 1'b0;
        end else if (txn_wr_req) begin
            txn_wr_gnt = 1'b1;
            comb_req   = 1'b1;
            comb_addr  = reg_wr_addr;
            comb_prot  = reg_wr_prot;
            comb_wdata = reg_wdata;
            comb_wstrb = reg_wstrb;
            comb_write = 1'b1;
        end
    end

    // Sequential Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state     <= ST_WR_IDLE;
            rd_state     <= ST_RD_IDLE;
            reg_wr_addr  <= '0;
            reg_wr_prot  <= '0;
            reg_wdata    <= '0;
            reg_wstrb    <= '0;
            reg_rd_addr  <= '0;
            reg_rd_prot  <= '0;
            bridge_req   <= 1'b0;
            bridge_write <= 1'b0;
            txn_addr     <= '0;
            txn_prot     <= '0;
            txn_wdata    <= '0;
            txn_wstrb    <= '0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
            s_axi_rresp  <= 2'b00;
        end else begin
            wr_state <= wr_next;
            rd_state <= rd_next;

            bridge_req   <= comb_req;
            bridge_write <= comb_write;
            txn_addr     <= comb_addr;
            txn_prot     <= comb_prot;
            txn_wdata    <= comb_wdata;
            txn_wstrb    <= comb_wstrb;

            if (wr_state == ST_WR_IDLE && s_axi_awvalid && s_axi_wvalid) begin
                reg_wr_addr <= s_axi_awaddr;
                reg_wr_prot <= s_axi_awprot;
                reg_wdata   <= s_axi_wdata;
                reg_wstrb   <= s_axi_wstrb;
            end

            if (rd_state == ST_RD_IDLE && s_axi_arvalid) begin
                reg_rd_addr <= s_axi_araddr;
                reg_rd_prot <= s_axi_arprot;
            end

            // Drive AXI Write Response
            if (wr_state == ST_WR_APB_WAIT && txn_wr_gnt && bridge_ack) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= bridge_err ? 2'b11 : 2'b00;
            end else if (wr_state == ST_WR_AXI_RESP && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Drive AXI Read Response & Latch Read Data
            if (rd_state == ST_RD_APB_WAIT && txn_rd_gnt && bridge_ack) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= txn_rdata; 
                s_axi_rresp  <= bridge_err ? 2'b11 : 2'b00;
            end else if (rd_state == ST_RD_AXI_RESP && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule

// APB4_Master

module apb4_master #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter NUM_SLAVES     = 4,
    parameter WATCHDOG_LIMIT = 256
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // Interlock Link Ports
    input  logic [ADDR_WIDTH-1:0]     txn_addr,
    input  logic [2:0]                txn_prot,
    input  logic [DATA_WIDTH-1:0]     txn_wdata,
    input  logic [(DATA_WIDTH/8)-1:0] txn_wstrb,
    input  logic                      bridge_write,
    input  logic                      bridge_req,   
    output logic                      bridge_ack,   
    output logic [DATA_WIDTH-1:0]     txn_rdata,
    output logic                      bridge_err,   

    // External APB4 Interface Ports
    output logic [ADDR_WIDTH-1:0]     m_apb_paddr,
    output logic [2:0]                m_apb_pprot,
    output logic [NUM_SLAVES-1:0]     m_apb_psel,   
    output logic                      m_apb_penable,
    output logic                      m_apb_pwrite,
    output logic [DATA_WIDTH-1:0]     m_apb_pwdata,
    output logic [(DATA_WIDTH/8)-1:0] m_apb_pstrb,
    input  logic [DATA_WIDTH-1:0]     m_apb_prdata,
    input  logic                      m_apb_pready,
    input  logic                      m_apb_pslverr
);

    typedef enum logic [1:0] {ST_IDLE, ST_SETUP, ST_ACCESS, ST_ACK} apb_state_t;
    apb_state_t state, next_state;

    logic [NUM_SLAVES-1:0] decoded_psel;
    logic                  address_fault;
    logic [15:0]           watchdog_cnt;
    logic                  watchdog_timeout;

    // Address Decoder Logic
    always_comb begin
        decoded_psel  = '0;
        address_fault = 1'b0;
        if (bridge_req) begin
            case (txn_addr[31:12])
                20'h10000: decoded_psel = 4'b0001; // Slave 0
                20'h20000: decoded_psel = 4'b0010; // Slave 1
                20'h30000: decoded_psel = 4'b0100; // Slave 2
                20'h40000: decoded_psel = 4'b1000; // Slave 3
                default:   address_fault = 1'b1;   // Unmapped fault
            endcase
        end
    end

    // Timeout Watchdog Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            watchdog_cnt     <= '0;
            watchdog_timeout <= 1'b0;
        end else begin
            if (state == ST_ACCESS && !m_apb_pready) begin
                if (watchdog_cnt >= WATCHDOG_LIMIT) begin
                    watchdog_timeout <= 1'b1;
                end else begin
                    watchdog_cnt <= watchdog_cnt + 1'b1;
                end
            end else begin
                watchdog_cnt     <= '0;
                watchdog_timeout <= 1'b0;
            end
        end
    end

    // APB4 State Machine
    always_comb begin
        next_state    = state;
        m_apb_psel    = '0;
        m_apb_penable = 1'b0;
        bridge_ack    = 1'b0;

        case (state)
            ST_IDLE: begin
                if (bridge_req) begin
                    if (address_fault) next_state = ST_ACK; 
                    else               next_state = ST_SETUP;
                end
            end
            ST_SETUP: begin
                m_apb_psel = decoded_psel;
                next_state = ST_ACCESS;
            end
            ST_ACCESS: begin
                m_apb_psel    = decoded_psel;
                m_apb_penable = 1'b1;
                if (m_apb_pready || watchdog_timeout) next_state = ST_ACK;
            end
            ST_ACK: begin
                bridge_ack = 1'b1;
                if (!bridge_req) next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    // Synchronous Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_apb_paddr  <= '0;
            m_apb_pprot  <= '0;
            m_apb_pwrite <= 1'b0;
            m_apb_pwdata <= '0;
            m_apb_pstrb  <= '0;
            txn_rdata    <= '0;
            bridge_err   <= 1'b0;
            state        <= ST_IDLE;
        end else begin
            state <= next_state;

            if (state == ST_IDLE && bridge_req) begin
                if (address_fault) begin
                    bridge_err <= 1'b1;
                    txn_rdata  <= '0;
                end else begin
                    m_apb_paddr  <= txn_addr;
                    m_apb_pprot  <= txn_prot;
                    m_apb_pwrite <= bridge_write;
                    m_apb_pwdata <= txn_wdata;
                    m_apb_pstrb  <= txn_wstrb;
                    bridge_err   <= 1'b0;
                end
            end else if (state == ST_ACCESS) begin
                if (m_apb_pready) begin
                    txn_rdata  <= m_apb_prdata; // Latch valid read data from APB bus
                    bridge_err <= m_apb_pslverr;
                end else if (watchdog_timeout) begin
                    txn_rdata  <= '0;
                    bridge_err <= 1'b1;
                end
            end
        end
    end

endmodule

// AXI4-Lite_to_APB4_Bridge (Top Level)

module axi4_lite_to_apb4_bridge #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter NUM_SLAVES     = 4,
    parameter WATCHDOG_LIMIT = 256
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // External AXI4-Lite Ports
    input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                s_axi_awprot,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                s_axi_arprot,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // External APB4 Ports
    output logic [ADDR_WIDTH-1:0]     m_apb_paddr,
    output logic [2:0]                m_apb_pprot,
    output logic [NUM_SLAVES-1:0]     m_apb_psel,
    output logic                      m_apb_penable,
    output logic                      m_apb_pwrite,
    output logic [DATA_WIDTH-1:0]     m_apb_pwdata,
    output logic [(DATA_WIDTH/8)-1:0] m_apb_pstrb,
    input  logic [DATA_WIDTH-1:0]     m_apb_prdata,
    input  logic                      m_apb_pready,
    input  logic                      m_apb_pslverr
);

    logic [ADDR_WIDTH-1:0]     int_addr;
    logic [2:0]                int_prot;
    logic [DATA_WIDTH-1:0]     int_wdata;
    logic [(DATA_WIDTH/8)-1:0] int_wstrb;
    logic                      int_write;
    logic                      int_req;
    logic                      int_ack;
    logic [DATA_WIDTH-1:0]     int_rdata;
    logic                      int_err;

    axi4_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_axi_slave (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awprot (s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arprot (s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .txn_addr     (int_addr),
        .txn_prot     (int_prot),
        .txn_wdata    (int_wdata),
        .txn_wstrb    (int_wstrb),
        .bridge_write (int_write),
        .bridge_req   (int_req),
        .bridge_ack   (int_ack),
        .txn_rdata    (int_rdata),
        .bridge_err   (int_err)
    );

    apb4_master #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .NUM_SLAVES    (NUM_SLAVES),
        .WATCHDOG_LIMIT(WATCHDOG_LIMIT)
    ) u_apb4_master (
        .clk          (clk),
        .rst_n        (rst_n),
        .txn_addr     (int_addr),
        .txn_prot     (int_prot),
        .txn_wdata    (int_wdata),
        .txn_wstrb    (int_wstrb),
        .bridge_write (int_write),
        .bridge_req   (int_req),
        .bridge_ack   (int_ack),
        .txn_rdata    (int_rdata),
        .bridge_err   (int_err),
        .m_apb_paddr  (m_apb_paddr),
        .m_apb_pprot  (m_apb_pprot),
        .m_apb_psel   (m_apb_psel),
        .m_apb_penable(m_apb_penable),
        .m_apb_pwrite (m_apb_pwrite),
        .m_apb_pwdata (m_apb_pwdata),
        .m_apb_pstrb  (m_apb_pstrb),
        .m_apb_prdata (m_apb_prdata),
        .m_apb_pready (m_apb_pready),
        .m_apb_pslverr(m_apb_pslverr)
    );

endmodule

// Interface Definition with SystemVerilog Assertions (SVA)

interface axi4_lite_apb4_if #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter NUM_SLAVES     = 4,
    parameter WATCHDOG_LIMIT = 256
)(
    input logic clk,
    input logic rst_n
);

    logic [ADDR_WIDTH-1:0]     s_axi_awaddr;
    logic [2:0]                s_axi_awprot;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;
    logic [DATA_WIDTH-1:0]     s_axi_wdata;
    logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;
    logic [ADDR_WIDTH-1:0]     s_axi_araddr;
    logic [2:0]                s_axi_arprot;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;
    logic [DATA_WIDTH-1:0]     s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    logic [ADDR_WIDTH-1:0]     m_apb_paddr;
    logic [2:0]                m_apb_pprot;
    logic [NUM_SLAVES-1:0]     m_apb_psel;
    logic                      m_apb_penable;
    logic                      m_apb_pwrite;
    logic [DATA_WIDTH-1:0]     m_apb_pwdata;
    logic [(DATA_WIDTH/8)-1:0] m_apb_pstrb;
    logic [DATA_WIDTH-1:0]     m_apb_prdata;
    logic                      m_apb_pready;
    logic                      m_apb_pslverr;

    // CONCURRENT SVA ASSERTIONS
    default clocking def_cb @(posedge clk); endclocking;

    // SVA 1: APB SETUP phase MUST transition to ACCESS phase on next cycle
    property p_apb_setup_to_access;
        disable iff (!rst_n)
        (|m_apb_psel && !m_apb_penable) |=> (|m_apb_psel && m_apb_penable);
    endproperty
    assert_apb_setup_to_access: assert property (p_apb_setup_to_access)
        else $error("[SVA FAIL] APB SETUP phase failed to transition to ACCESS!");

    // SVA 2: At most ONE peripheral select bit can be active (One-hot decoding)
    property p_apb_onehot_psel;
        disable iff (!rst_n)
        $onehot0(m_apb_psel);
    endproperty
    assert_apb_onehot_psel: assert property (p_apb_onehot_psel)
        else $error("[SVA FAIL] APB Bus Collision: Multiple m_apb_psel lines high!");

    // SVA 3: PENABLE must drop back to 0 after PREADY handshake
    property p_apb_enable_deassert;
        disable iff (!rst_n)
        (m_apb_penable && m_apb_pready) |=> (!m_apb_penable);
    endproperty
    assert_apb_enable_deassert: assert property (p_apb_enable_deassert)
        else $error("[SVA FAIL] m_apb_penable remained high after PREADY!");

    logic is_unmapped_write_addr, is_unmapped_read_addr;
    assign is_unmapped_write_addr = s_axi_awvalid && !(s_axi_awaddr[31:12] inside {20'h10000, 20'h20000, 20'h30000, 20'h40000});
    assign is_unmapped_read_addr  = s_axi_arvalid && !(s_axi_araddr[31:12] inside {20'h10000, 20'h20000, 20'h30000, 20'h40000});

    property p_unmapped_addr_bypass;
        disable iff (!rst_n)
        (is_unmapped_write_addr || is_unmapped_read_addr) |=> (m_apb_psel == '0);
    endproperty
    assert_unmapped_addr_bypass: assert property (p_unmapped_addr_bypass)
        else $error("[SVA FAIL] Deadlock Trap Violation: Unmapped address activated PSEL!");

    property p_apb_watchdog_timeout;
        disable iff (!rst_n)
        (m_apb_penable) |-> ##[1:WATCHDOG_LIMIT+3] (!m_apb_penable);
    endproperty
    assert_apb_watchdog_timeout: assert property (p_apb_watchdog_timeout)
        else $fatal(1, "[SVA FATAL] SYSTEM DEADLOCK DETECTED! APB transaction hung beyond Watchdog Limit!");

endinterface
