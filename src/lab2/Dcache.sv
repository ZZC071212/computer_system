`include "Define.vh"
`include "mem_ift.vh"

module Dcache #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM   = 4,
    parameter integer CAPACITY   = 1024
) (
    input                     clk,
    input                     rst,
    input   CorePack::addr_t  addr_cpu,
    input   CorePack::data_t  wdata_cpu,
    input                     wen_cpu,
    input   CorePack::mask_t  wmask_cpu,
    input                     ren_cpu,

    output  CorePack::data_t  rdata_cpu,
    output                    hit_cpu,
    output                    ren_mem,
    output                    wen_mem,
    output                    is_mmio_addr,

    output  CorePack::addr_t  raddr_out,
    output  CorePack::addr_t  waddr_out,
    output  CorePack::data_t  wdata_out,
    output  CorePack::mask_t  wmask_out,
    input   CorePack::data_t  rdata_in,
    input                     wvalid_in,
    input                     rvalid_in,
    input                     switch_mode
);
    import CorePack::*;

    logic mem_rom, mem_buffer, mem_ddr, is_mem;
    logic mmio_mtime, mmio_mtimcmp, mmio_uart, is_mmio;

    assign mem_rom = addr_cpu < (`ROM_BASE + `ROM_LEN);
    assign mem_buffer = (`BUFFER_BASE <= addr_cpu) & (addr_cpu < (`BUFFER_BASE + `BUFFER_LEN));
    assign mem_ddr = (`DDR_BASE <= addr_cpu) & (addr_cpu < (`DDR_BASE + `DDR_LEN));
    assign is_mem = mem_rom | mem_buffer | mem_ddr;

    assign mmio_mtime = (`MTIME_BASE <= addr_cpu) & ((`MTIME_BASE + `MTIME_LEN) > addr_cpu);
    assign mmio_mtimcmp = (`MTIMECMP_BASE <= addr_cpu) & ((`MTIMECMP_BASE + `MTIMECMP_LEN) > addr_cpu);
    assign mmio_uart = (`UART_BASE <= addr_cpu) & ((`UART_BASE + `UART_LEN) > addr_cpu);
    assign is_mmio = mmio_mtime | mmio_mtimcmp | mmio_uart;

    logic ren_dcache, wen_dcache, hit_dcache, ren_cpu_cache, wen_cpu_cache, rvalid, wvalid, mmio_finish;
    addr_t dcache_read_addr_mem, dcache_write_addr_mem, addr_cpu_cache;
    data_t dcache_data_mem, read_dcache_data, wdata_cpu_cache, rdata_mem;
    mask_t dcache_data_mem_mask, wmask_cpu_cache;

    assign addr_cpu_cache = is_mmio ? 0 : (is_mem ? addr_cpu : 0) ;
    assign wdata_cpu_cache = is_mmio ? 0 : (is_mem ? wdata_cpu : 0);
    assign wmask_cpu_cache = is_mmio ? 0 : (is_mem ? wmask_cpu : 0);
    assign ren_cpu_cache = is_mmio ? 0 : (is_mem ? ren_cpu : 0);
    assign wen_cpu_cache = is_mmio ? 0 : (is_mem ? wen_cpu : 0);
    assign rdata_mem = is_mmio ? 0 : (is_mem ? rdata_in : 0);
    assign rvalid = is_mmio ? 0 : (is_mem ? rvalid_in : 0);

    assign rdata_cpu = is_mmio ? rdata_in : (is_mem ? read_dcache_data : 0);
    assign hit_cpu = is_mmio ? ((ren_cpu & rvalid_in) | (wen_cpu & wvalid_in)) : (is_mem ? hit_dcache : 0);
    assign ren_mem = is_mmio ? ren_cpu : (is_mem ? ren_dcache : 0);
    assign raddr_out = is_mmio ? addr_cpu : (is_mem ? dcache_read_addr_mem : 0);

    assign wen_mem = is_mmio ? wen_cpu : wen_dcache;
    assign waddr_out = is_mmio ? addr_cpu : dcache_write_addr_mem;
    assign wdata_out = is_mmio ? wdata_cpu : dcache_data_mem;
    assign wmask_out = is_mmio ? wmask_cpu : dcache_data_mem_mask;
    assign wvalid = is_mmio ? 0 : wvalid_in;

    assign is_mmio_addr = is_mmio;

    Cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (BANK_NUM),
        .CAPACITY  (CAPACITY)
    ) cache (
        .clk(clk),
        .rst(rst),
        .addr_cpu(addr_cpu_cache),
        .wdata_cpu(wdata_cpu_cache),
        .wen_cpu(wen_cpu_cache),
        .wmask_cpu(wmask_cpu_cache),
        .ren_cpu(ren_cpu_cache),
        .rdata_cpu(read_dcache_data),
        .hit_cpu(hit_dcache),
        .ren_mem(ren_dcache),
        .wen_mem(wen_dcache),
        .raddr_out(dcache_read_addr_mem),
        .waddr_out(dcache_write_addr_mem),
        .wdata_out(dcache_data_mem),
        .wmask_out(dcache_data_mem_mask),
        .rdata_in(rdata_mem),
        .rvalid_in(rvalid),
        .wvalid_in(wvalid),
        .switch_mode(switch_mode)
    );

endmodule
