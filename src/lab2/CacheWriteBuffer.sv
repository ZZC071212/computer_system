`include "core_struct.vh"
module CacheWriteBuffer #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM   = 4
) (
    input                            clk,
    input                            rst,
    input  CorePack::addr_t          addr_wb,
    input  [BANK_NUM*DATA_WIDTH-1:0] data_wb,
    output                           busy_wb,
    input                            need_wb,
    input                            miss_cache,

    output  CorePack::addr_t  addr_mem,
    output  CorePack::data_t  data_mem,

    input [$clog2(BANK_NUM)-1:0] bank_index,
    input                        finish_wb
);
    import CorePack::*;

    logic busy;
    addr_t addr;
    logic [DATA_WIDTH*BANK_NUM-1:0] data;
    
    always @(posedge clk) begin
        if (rst) begin
            addr <= {ADDR_WIDTH{1'b0}};
            data <= {BANK_NUM * DATA_WIDTH{1'b0}};
            busy <= 1'b0;
        end else if (miss_cache & need_wb) begin
            addr <= addr_wb;
            data <= data_wb;
            busy <= 1'b1;
        end else if (finish_wb) begin
            busy <= 1'b0;
        end
    end

    assign busy_wb  = busy;
    assign addr_mem = addr;
    data_t word [BANK_NUM-1:0];
    genvar i;
    generate
        for (i = 0; i < BANK_NUM ; i = i + 1) begin
            assign word[i] = data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
        end
    endgenerate
    assign data_mem = word[bank_index];
endmodule
