`include "core_struct.vh"
module Icache #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM   = 4,
    parameter integer CAPACITY   = 1024
) (
    input                   clk,
    input                   rst,
    input  CorePack::addr_t pc,
    input  CorePack::data_t imem_data,
    input                   switch_mode,
    input                   rvalid_in,

    output CorePack::inst_t inst,
    output CorePack::addr_t icache_request_addr,
    output                  hit_icache
);
    import CorePack::*;

    data_t icache_data;

    Cache icache(
        .clk(clk),
        .rst(rst),
        .addr_cpu(pc),
        .wdata_cpu({64{1'b0}}),
        .wen_cpu(1'b0),
        .wmask_cpu({8{1'b0}}),
        .ren_cpu(1'b1),
        .rdata_cpu(icache_data),
        .hit_cpu(hit_icache),
        .ren_mem(),
        .wen_mem(),
        .raddr_out(icache_request_addr),
        .waddr_out(),
        .wdata_out(),
        .wmask_out(),
        .rdata_in(imem_data),
        .wvalid_in(),
        .rvalid_in(rvalid_in),
        .switch_mode(switch_mode)
    );

    assign inst = pc[2] ? icache_data[63:32] : icache_data[31:0];

endmodule
