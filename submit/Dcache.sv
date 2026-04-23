`include "core_struct.vh"
`include "mem_struct.vh"

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
    output                    is_mmio_addr,//访问mmio地址

    output  CorePack::addr_t  raddr_out,
    output  CorePack::addr_t  waddr_out,
    output  CorePack::data_t  wdata_out,
    output  CorePack::mask_t  wmask_out,
    input                     rready_in,
    input                     wready_in,
    input   CorePack::data_t  rdata_in,
    input                     wvalid_in,
    input                     rvalid_in,
    input                     switch_mode
);
    import CorePack::*;
    import MemPack::*;
    localparam integer BYTE_NUM = DATA_WIDTH / 8;
    localparam integer GRANU_LEN = $clog2(BYTE_NUM);
    localparam integer OFFSET_LEN = $clog2(BANK_NUM);
    localparam integer LINE_OFFSET_LEN = GRANU_LEN + OFFSET_LEN;

    logic mem_rom;
    logic mem_buffer;
    logic mem_ddr;
    logic is_mem;
    logic mmio_misc;
    logic mmio_uart;
    logic mmio_conv;
    logic is_mmio;
    logic mmio_pending;
    logic mmio_read_pending;
    logic mmio_write_pending;
    logic mmio_selected;
    logic mmio_read_req_fire;
    logic mmio_write_req_fire;
    logic mmio_read_resp_now;
    logic mmio_write_resp_now;
    logic mmio_read_resp_wait;
    logic mmio_write_resp_wait;
    logic mmio_resp_fire;
    logic store_miss_pending;
    logic store_miss_selected;
    logic store_miss_req_fire;
    logic store_miss_resp_now;
    logic store_miss_resp_wait;
    logic store_miss_resp_fire;
    addr_t mmio_addr_q;
    data_t mmio_wdata_q;
    mask_t mmio_wmask_q;
    addr_t mmio_addr_active;
    data_t mmio_wdata_active;
    mask_t mmio_wmask_active;
    addr_t store_miss_addr_q;
    data_t store_miss_wdata_q;
    mask_t store_miss_wmask_q;
    addr_t store_miss_addr_active;
    data_t store_miss_wdata_active;
    mask_t store_miss_wmask_active;
    typedef enum logic [1:0] {
        WRITE_OWNER_NONE,
        WRITE_OWNER_CACHE,
        WRITE_OWNER_STORE_MISS,
        WRITE_OWNER_MMIO
    } write_owner_e;
    write_owner_e write_owner_q;

    //地址分类
    //正常内存
    assign mem_rom = addr_cpu < addr_t'(boot_end);
    assign mem_buffer = (addr_cpu >= addr_t'(buffer_start)) && (addr_cpu < addr_t'(buffer_end));
    assign mem_ddr = (addr_cpu >= addr_t'(ddr_start)) && (addr_cpu < addr_t'(ddr_end));
    assign is_mem = mem_rom || mem_buffer || mem_ddr;

    //MMIO
    assign mmio_uart = (addr_cpu >= addr_t'(uart_start)) && (addr_cpu < addr_t'(uart_end));
    assign mmio_conv = (addr_cpu >= addr_t'(cov_start)) && (addr_cpu < addr_t'(cov_end));
    assign mmio_misc = (addr_cpu >= addr_t'(misc_start)) && (addr_cpu < addr_t'(misc_end));
    assign is_mmio = mmio_uart || mmio_conv || mmio_misc;
    assign mmio_selected = is_mmio || mmio_pending;//当前地址本来就是mmio或者如果一笔 MMIO 请求发出后没有同拍完成，就把它锁存下来，直到它真正收到响应为止
    assign mmio_addr_active = mmio_pending ? mmio_addr_q : addr_cpu;
    assign mmio_wdata_active = mmio_pending ? mmio_wdata_q : wdata_cpu;
    assign mmio_wmask_active = mmio_pending ? mmio_wmask_q : wmask_cpu;
    logic mmio_write_req_valid;
    logic store_miss_req_valid;
    logic cache_write_req_fire;
    logic cache_write_channel_grant;
    logic cache_write_resp_wait;

    assign mmio_read_req_fire = is_mmio && !mmio_pending && ren_cpu && rready_in;
    assign mmio_write_req_valid = is_mmio && !mmio_pending && wen_cpu;
    assign mmio_write_req_fire = mmio_write_req_valid &&
                                 (write_owner_q == WRITE_OWNER_NONE) &&
                                 wready_in;
    assign mmio_read_resp_now = mmio_read_req_fire && rvalid_in;
    assign mmio_write_resp_now = mmio_write_req_fire && wvalid_in;
    assign mmio_read_resp_wait = mmio_pending && mmio_read_pending && rvalid_in;
    assign mmio_write_resp_wait = mmio_pending && mmio_write_pending &&
                                  (write_owner_q == WRITE_OWNER_MMIO) && wvalid_in;
    assign mmio_resp_fire = mmio_read_resp_now || mmio_write_resp_now ||
                            mmio_read_resp_wait || mmio_write_resp_wait;
    assign store_miss_req_valid = cacheable_store_miss && !store_miss_pending;
    assign store_miss_selected = store_miss_req_valid || store_miss_pending;
    assign store_miss_addr_active = store_miss_pending ? store_miss_addr_q : addr_cpu;
    assign store_miss_wdata_active = store_miss_pending ? store_miss_wdata_q : wdata_cpu;
    assign store_miss_wmask_active = store_miss_pending ? store_miss_wmask_q : wmask_cpu;
    assign store_miss_req_fire = store_miss_req_valid &&
                                 !mmio_write_req_valid &&
                                 (write_owner_q == WRITE_OWNER_NONE) &&
                                 wready_in;
    assign store_miss_resp_now = store_miss_req_fire && wvalid_in;
    assign store_miss_resp_wait = store_miss_pending &&
                                  (write_owner_q == WRITE_OWNER_STORE_MISS) && wvalid_in;
    assign store_miss_resp_fire = store_miss_resp_now || store_miss_resp_wait;

    logic ren_dcache;
    logic wen_dcache;
    logic hit_dcache;
    addr_t addr_cpu_cache;
    data_t wdata_cpu_cache;
    mask_t wmask_cpu_cache;
    logic ren_cpu_cache;
    logic wen_cpu_cache;
    logic busy_cache;
    logic write_busy_cache;
    logic wb_busy_cache;
    data_t rdata_mem;
    addr_t addr_cpu_line;
    addr_t wb_addr_cache;
    logic rvalid_cache;
    logic wvalid_cache;
    logic rready_cache;
    logic wready_cache;
    logic cacheable_store_miss;
    logic store_miss_wb_conflict;
    addr_t dcache_read_addr_mem;
    addr_t dcache_write_addr_mem;
    data_t dcache_data_mem;
    data_t read_dcache_data;
    mask_t dcache_data_mem_mask;
    // Debug tracing disabled for normal kernel-output inspection.
    // logic dbg_watch_task_addr;

    assign addr_cpu_cache = is_mem ? addr_cpu : '0;
    assign addr_cpu_line = {addr_cpu[ADDR_WIDTH-1:LINE_OFFSET_LEN], {LINE_OFFSET_LEN{1'b0}}};
    assign wdata_cpu_cache = is_mem ? wdata_cpu : '0;
    assign wmask_cpu_cache = is_mem ? wmask_cpu : '0;
    assign ren_cpu_cache = is_mem && !is_mmio && !store_miss_pending && ren_cpu;
    assign store_miss_wb_conflict = wb_busy_cache && (addr_cpu_line == wb_addr_cache);
    assign cacheable_store_miss = is_mem && !is_mmio && !store_miss_pending &&
                                  !store_miss_wb_conflict &&
                                  wen_cpu && !ren_cpu && !hit_dcache;
    assign wen_cpu_cache = is_mem && !is_mmio && !store_miss_pending &&
                           wen_cpu && !cacheable_store_miss;
    assign rdata_mem = is_mem ? rdata_in : '0;
    assign rready_cache = is_mem && !is_mmio && rready_in;
    assign cache_write_channel_grant = (write_owner_q == WRITE_OWNER_NONE) &&
                                       !mmio_write_req_valid && !store_miss_req_valid;
    assign wready_cache = cache_write_channel_grant && wready_in;
    assign rvalid_cache = is_mem && !is_mmio && rvalid_in;
    assign cache_write_req_fire = wen_dcache && wready_cache;
    assign cache_write_resp_wait = (write_owner_q == WRITE_OWNER_CACHE) && wvalid_in;
    assign wvalid_cache = (cache_write_req_fire || (write_owner_q == WRITE_OWNER_CACHE)) && wvalid_in;

    assign rdata_cpu = mmio_selected ? rdata_in : (is_mem ? read_dcache_data : '0);
    assign hit_cpu = mmio_selected ? mmio_resp_fire :
                     store_miss_selected ? store_miss_resp_fire :
                     (is_mem ? hit_dcache : 1'b0);
    assign ren_mem = (is_mmio && !mmio_pending) ? ren_cpu :
                     (is_mem ? ren_dcache : 1'b0);
    assign wen_mem = mmio_write_req_fire || store_miss_req_fire || cache_write_req_fire;
    assign raddr_out = mmio_selected ? mmio_addr_active : (is_mem ? dcache_read_addr_mem : '0);
    assign waddr_out = mmio_write_req_fire || (write_owner_q == WRITE_OWNER_MMIO) ? mmio_addr_active :
                       store_miss_req_fire || (write_owner_q == WRITE_OWNER_STORE_MISS) ? store_miss_addr_active :
                       dcache_write_addr_mem;
    assign wdata_out = mmio_write_req_fire || (write_owner_q == WRITE_OWNER_MMIO) ? mmio_wdata_active :
                       store_miss_req_fire || (write_owner_q == WRITE_OWNER_STORE_MISS) ? store_miss_wdata_active :
                       dcache_data_mem;
    assign wmask_out = mmio_write_req_fire || (write_owner_q == WRITE_OWNER_MMIO) ? mmio_wmask_active :
                       store_miss_req_fire || (write_owner_q == WRITE_OWNER_STORE_MISS) ? store_miss_wmask_active :
                       dcache_data_mem_mask;
    assign is_mmio_addr = mmio_selected;

    // assign dbg_watch_task_addr =
    //     ((addr_cpu >= 64'h0000_0000_8020_4020) && (addr_cpu <= 64'h0000_0000_8020_4040)) ||
    //     ((addr_cpu >= 64'h0000_0000_803f_b000) && (addr_cpu <= 64'h0000_0000_803f_f01f));
    //
    // always_ff @(posedge clk) begin
    //     if (!rst && dbg_watch_task_addr) begin
    //         if (cacheable_store_miss) begin
    //             $display("[DCACHE-SM] t=%0t addr=%h data=%h mask=%h pending=%0d req=%0d resp=%0d",
    //                      $time, addr_cpu, wdata_cpu, wmask_cpu,
    //                      store_miss_pending, store_miss_req_fire, store_miss_resp_fire);
    //         end
    //         if (store_miss_pending || store_miss_resp_fire) begin
    //             $display("[DCACHE-SM-ACT] t=%0t addr=%h data=%h mask=%h pending=%0d req=%0d resp=%0d wready=%0d wvalid=%0d",
    //                      $time, store_miss_addr_active, store_miss_wdata_active, store_miss_wmask_active,
    //                      store_miss_pending, store_miss_req_fire, store_miss_resp_fire, wready_in, wvalid_in);
    //         end
    //         if (wen_cpu_cache && hit_dcache) begin
    //             $display("[DCACHE-HIT-ST] t=%0t addr=%h data=%h mask=%h",
    //                      $time, addr_cpu, wdata_cpu, wmask_cpu);
    //         end
    //         if (ren_cpu_cache && hit_dcache) begin
    //             $display("[DCACHE-HIT-LD] t=%0t addr=%h data=%h",
    //                      $time, addr_cpu, read_dcache_data);
    //         end
    //     end
    // end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || switch_mode) begin
            write_owner_q <= WRITE_OWNER_NONE;
        end else begin
            unique case (write_owner_q)
                WRITE_OWNER_NONE: begin
                    if (mmio_write_req_fire && !mmio_write_resp_now) begin
                        write_owner_q <= WRITE_OWNER_MMIO;
                    end else if (store_miss_req_fire && !store_miss_resp_now) begin
                        write_owner_q <= WRITE_OWNER_STORE_MISS;
                    end else if (cache_write_req_fire && !wvalid_in) begin
                        write_owner_q <= WRITE_OWNER_CACHE;
                    end
                end

                WRITE_OWNER_CACHE: begin
                    if (cache_write_resp_wait) begin
                        write_owner_q <= WRITE_OWNER_NONE;
                    end
                end

                WRITE_OWNER_STORE_MISS: begin
                    if (store_miss_resp_wait) begin
                        write_owner_q <= WRITE_OWNER_NONE;
                    end
                end

                WRITE_OWNER_MMIO: begin
                    if (mmio_write_resp_wait) begin
                        write_owner_q <= WRITE_OWNER_NONE;
                    end
                end

                default: begin
                    write_owner_q <= WRITE_OWNER_NONE;
                end
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || switch_mode) begin
            mmio_pending <= 1'b0;
            mmio_read_pending <= 1'b0;
            mmio_write_pending <= 1'b0;
            mmio_addr_q <= '0;
            mmio_wdata_q <= '0;
            mmio_wmask_q <= '0;
        end else if (mmio_pending) begin
            if (mmio_read_resp_wait || mmio_write_resp_wait) begin
                mmio_pending <= 1'b0;
                mmio_read_pending <= 1'b0;
                mmio_write_pending <= 1'b0;
            end
        end else if ((mmio_read_req_fire || mmio_write_req_fire) && !mmio_resp_fire) begin
            mmio_pending <= 1'b1;
            mmio_read_pending <= mmio_read_req_fire;
            mmio_write_pending <= mmio_write_req_fire;
            mmio_addr_q <= addr_cpu;
            mmio_wdata_q <= wdata_cpu;
            mmio_wmask_q <= wmask_cpu;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || switch_mode) begin
            store_miss_pending <= 1'b0;
            store_miss_addr_q <= '0;
            store_miss_wdata_q <= '0;
            store_miss_wmask_q <= '0;
        end else if (store_miss_pending) begin
            if (store_miss_resp_wait) begin
                store_miss_pending <= 1'b0;
            end
        end else if (store_miss_req_fire && !store_miss_resp_fire) begin
            store_miss_pending <= 1'b1;
            store_miss_addr_q <= addr_cpu;
            store_miss_wdata_q <= wdata_cpu;
            store_miss_wmask_q <= wmask_cpu;
        end
    end

    Cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (BANK_NUM),
        .CAPACITY  (CAPACITY)
    ) cache (
        .clk        (clk),
        .rst        (rst),
        .addr_cpu   (addr_cpu_cache),
        .wdata_cpu  (wdata_cpu_cache),
        .wen_cpu    (wen_cpu_cache),
        .wmask_cpu  (wmask_cpu_cache),
        .ren_cpu    (ren_cpu_cache),
        .rdata_cpu  (read_dcache_data),
        .hit_cpu    (hit_dcache),
        .busy_cache (busy_cache),
        .write_busy_cache(write_busy_cache),
        .wb_busy    (wb_busy_cache),
        .wb_addr    (wb_addr_cache),
        .ren_mem    (ren_dcache),
        .wen_mem    (wen_dcache),
        .raddr_out  (dcache_read_addr_mem),
        .waddr_out  (dcache_write_addr_mem),
        .wdata_out  (dcache_data_mem),
        .wmask_out  (dcache_data_mem_mask),
        .rready_in  (rready_cache),
        .wready_in  (wready_cache),
        .rdata_in   (rdata_mem),
        .wvalid_in  (wvalid_cache),
        .rvalid_in  (rvalid_cache),
        .switch_mode(switch_mode)
    );
endmodule
