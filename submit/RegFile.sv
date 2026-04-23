module RegFile (
    input clk,
    input rst,
    input we,
    input CorePack::reg_ind_t read_addr_1,
    input CorePack::reg_ind_t read_addr_2,
    input CorePack::reg_ind_t write_addr,
    input CorePack::data_t write_data,
    output CorePack::data_t read_data_1,
    output CorePack::data_t read_data_2
);
import CorePack::*;

integer i;
logic [63:0] register [1:31]; // 0号寄存器用于x0


// 寄存器初始化与reset
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // 全部清零
            for (i=1; i<32; i=i+1)
                register[i] <= '0;
        end else if (we && (write_addr != 0)) begin
            register[write_addr] <= write_data;
        end

        // 保证 x0 永远为 0
        // register[0] <= '0;
    end

//always @(posedge clk) begin
//    $display("rst=%b, reg1=%h, reg2=%h, rd1=%h, ra1=%d, rd2=%h, ra2=%d",
//        rst, register[1], register[2], read_data_1, read_addr_1, read_data_2, read_addr_2);
//end



// 读操作（组合逻辑）
assign read_data_1 =
    (|read_addr_1) ? register[read_addr_1] : 'b0;
assign read_data_2 =
    register[read_addr_2];


endmodule




