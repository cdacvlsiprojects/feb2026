module tb;

 logic clk;
    logic rst;
    logic wr_en;
    logic rd_en;
    logic [9:0] addr_in;
    logic [7:0]data_in; 

    // Outputs from DUT
    logic full;
    logic empty;
    logic [9:0] cache2_addr;
    logic [7:0] cache2_data;
    logic [9:0] nic_addr;
    logic [7:0] nic_data;
initial  clk = 0;

always #5 clk = ~clk;

top dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        
        .addr_in(addr_in),
        .data_in(data_in),
        .full(full),
        .empty(empty),
        .cache2_addr(cache2_addr),
        .cache2_data(cache2_data),
        .nic_addr(nic_addr),
        .nic_data(nic_data)
    );
  


initial begin
    rst     = 1;
    wr_en   = 0;
    rd_en   = 0;
    addr_in = 0;
    data_in = 0;

    #10;
    rst = 0;

    #5;
    addr_in = 10'd533;
    data_in = 8'd600;
    wr_en   = 1;

    #12;
    wr_en = 0;

    #10;
    rd_en = 1;

    #10;
    rd_en = 0;

    #20;
    $finish;
end
initial begin 

     $monitor("Time=%0t | Addr=%0d Data=%0d | Cache2 Addr=%0d Cache2 Data=%0d | NIC Addr=%0d NIC Data=%0d ",
                  $time,
                addr_in,
                data_in,
                  cache2_addr,
                  cache2_data,
                  nic_addr,
                  nic_data,
                  full,
                  empty
                  );
    end

endmodule 


