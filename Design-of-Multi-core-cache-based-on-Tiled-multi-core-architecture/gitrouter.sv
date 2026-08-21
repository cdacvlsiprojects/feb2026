module fifo #(
     parameter width = 18,
    parameter  depth = 16
)(
     input  logic clk,
     input logic  rst,
     input  logic wr_en,
     input logic rd_en,
     input logic [width -1:0]wr_data,
   output  logic [width -1:0]rd_data,
    output logic  full,
    output logic empty
);

logic [width-1:0]mem[depth-1:0];
logic [$clog2(depth)-1:0]wr_ptr;
logic [$clog2(depth)-1:0]rd_ptr;
logic [$clog2(depth+1)-1:0]count;
always_ff @(posedge clk) begin
    if(rst)begin 
        wr_ptr <= 0;
        rd_ptr <= 0;
        count <= 0;
       rd_data <= 0;
end

else begin 
    if(wr_en && !full) begin 
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1;

end

if (rd_en && !empty )begin 
    rd_data <= mem[rd_ptr];
    rd_ptr <= rd_ptr +1;

end

case ({wr_en && !full , rd_en && !empty})
    2'b10: count <= count +1;
    2'b01: count <= count - 1;
    2'b11 : count <= count;
    default :count <= count;
endcase

end
end
assign empty = (count == 0);
assign full = (count == depth);
endmodule 



module routing_logic  (
input logic [7:0]D_data,
input logic [9:0]L1_miss,
output logic [7:0]Data_fetch,
output logic [9:0]Data_addr_fetch,
output logic route_sel


);

 always_comb begin 
    Data_fetch = 0;
    Data_addr_fetch = 0;
    route_sel = 0;

        if (L1_miss >= 10'd0 && L1_miss <= 10'd511)begin //cache2
             Data_fetch = D_data;
             Data_addr_fetch = L1_miss;
             route_sel = 1'b1; 

        end
         else if (L1_miss >= 10'd512 && L1_miss <= 10'd1023) begin 
             Data_fetch = D_data;
             Data_addr_fetch = L1_miss;
             route_sel = 1'b0; // nic
         end
                
     end
        
endmodule
 

module mux (
    input logic [7:0]Data_fetch,
    input logic[9:0] Data_addr_fetch,
    input logic route_sel,
    output logic [7:0]cache2_data,
    output logic [9:0]cache2_addr,

    output logic [7:0]nic_data,
    output logic  [9:0]nic_addr
);

always_comb begin 

    cache2_data=0;
    cache2_addr = 0;
    nic_data= 0;
    nic_addr= 0;

 if (route_sel == 1'b1)begin //cache
     cache2_addr = Data_addr_fetch;
    cache2_data = Data_fetch;
 end
     else begin//nic
    nic_addr = Data_addr_fetch;
     nic_data = Data_fetch;
        
         end 

        end 
    endmodule


    
module top(
    input  logic clk,
    input  logic rst,
    input  logic wr_en,
    input  logic rd_en,

    input  logic [9:0] addr_in,
    input  logic [7:0] data_in,

    output logic full,
    output logic empty,

    output logic [9:0] cache2_addr,
    output logic [7:0] cache2_data,

    output logic [9:0] nic_addr,
    output logic [7:0] nic_data
);


logic [9:0]Data_addr_fetch;
 logic [7:0] Data_fetch;
logic route_sel;
 logic [7:0]D_data;
 logic [9:0]L1_miss;
logic nic_valid;
logic nic_ready;
logic[17:0]nic_packet;
 

logic [17:0]fifo_out_data;
logic [17:0]fifo_wr_data;
//packing signals into one 
 assign fifo_wr_data = {addr_in ,data_in};

fifo #(
    .width(18),
    .depth(16)
)f1 (
   .clk(clk),
  .rst(rst),
  .wr_en(wr_en),
  .rd_en(rd_en),
  .wr_data(fifo_wr_data),
  .rd_data(fifo_out_data),
  .full(full),
  .empty(empty)
    

);

//unpacking signals into 2 
assign L1_miss= fifo_out_data[17:8];
assign D_data = fifo_out_data[7:0];

routing_logic r1(
    .D_data(D_data),
    .L1_miss(L1_miss),
    .Data_fetch(Data_fetch),
    .Data_addr_fetch(Data_addr_fetch),
    .route_sel(route_sel)
    );



    mux m1(
        .Data_fetch(Data_fetch),
    .Data_addr_fetch(Data_addr_fetch),
    .route_sel(route_sel),
    
    .cache2_data(cache2_data),
    .cache2_addr(cache2_addr),
    
    .nic_data(nic_data),
    .nic_addr(nic_addr));




    endmodule



