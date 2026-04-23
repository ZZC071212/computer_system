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
    input                   imem_ready,
    input                   switch_mode,
    input                   rvalid_in,

    output CorePack::inst_t inst,
    output CorePack::addr_t icache_request_addr,
    output                  ren_imem,
    output                  hit_icache
);
    import CorePack::*;

    data_t icache_data;

    Cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (BANK_NUM),
        .CAPACITY  (CAPACITY)
    ) icache (
        .clk       (clk),
        .rst       (rst),
        .addr_cpu  (pc),
        .wdata_cpu ('0),
        .wen_cpu   (1'b0),
        .wmask_cpu ('0),
        .ren_cpu   (1'b1),
        .rdata_cpu (icache_data),
        .hit_cpu   (hit_icache),
        .busy_cache(),
        .write_busy_cache(),
        .wb_busy   (),
        .wb_addr   (),
        .ren_mem   (ren_imem),
        .wen_mem   (),
        .raddr_out (icache_request_addr),
        .waddr_out (),
        .wdata_out (),
        .wmask_out (),
        .rready_in (imem_ready),
        .wready_in (1'b0),
        .rdata_in  (imem_data),
        .wvalid_in (1'b0),
        .rvalid_in (rvalid_in),
        .switch_mode(switch_mode)
    );

    assign inst = pc[2] ? icache_data[63:32] : icache_data[31:0];
endmodule
