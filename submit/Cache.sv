`include "core_struct.vh"

module Cache #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM   = 4,
    parameter integer CAPACITY   = 1024
) (
    //向上，接cpu/Dcache/Icache
    input                     clk,
    input                     rst,
    input   CorePack::addr_t  addr_cpu,
    input   CorePack::data_t  wdata_cpu,
    input                     wen_cpu,
    input   CorePack::mask_t  wmask_cpu,
    input                     ren_cpu,
    output  CorePack::data_t  rdata_cpu,
    output                    hit_cpu,

    
    output                    busy_cache,
    output                    write_busy_cache,
    output                    wb_busy,
    output  CorePack::addr_t  wb_addr,

    //向下，接memory
    output                    ren_mem,
    output                    wen_mem,

    output  CorePack::addr_t  raddr_out,
    output  CorePack::addr_t  waddr_out,
    output  CorePack::data_t  wdata_out,
    output  CorePack::mask_t  wmask_out,

    //对方回来的握手信号
    input                     rready_in,
    input                     wready_in,
    input   CorePack::data_t  rdata_in,
    input                     wvalid_in,
    input                     rvalid_in,
    input                     switch_mode
);
    import CorePack::*;

    localparam integer BYTE_NUM = DATA_WIDTH / 8;
    localparam integer LINE_NUM = CAPACITY / 2 / (BANK_NUM * BYTE_NUM);
    localparam integer GRANU_LEN = $clog2(BYTE_NUM);
    localparam integer OFFSET_LEN = $clog2(BANK_NUM);
    localparam integer INDEX_LEN = $clog2(LINE_NUM);

    typedef logic [OFFSET_LEN-1:0] offset_t;
    //状态
    typedef enum logic [1:0] {
        CMU_IDLE,
        CMU_READ,
        CMU_WRITE
    } cmu_state_e;

    addr_t addr_wb;
    addr_t addr_cache;
    addr_t addr_rd;
    data_t data_rd;
    logic busy_wb;
    logic need_wb;
    logic miss_cache;
    logic set_cache;
    logic busy_rd;
    logic wen_rd;
    logic set_rd;
    logic finish_rd;
    logic [BANK_NUM*DATA_WIDTH-1:0] data_wb;

    addr_t addr_mem;
    data_t data_mem;
    offset_t bank_index;
    logic finish_wb;

    CacheBank #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (BANK_NUM),
        .CAPACITY  (CAPACITY)
    ) cache_bank (
        .clk        (clk),
        .rst        (rst),
        .addr_cpu   (addr_cpu),
        .wdata_cpu  (wdata_cpu),
        .wen_cpu    (wen_cpu),
        .wmask_cpu  (wmask_cpu),
        .ren_cpu    (ren_cpu),
        .rdata_cpu  (rdata_cpu),
        .hit_cpu    (hit_cpu),

        .addr_wb    (addr_wb),
        .data_wb    (data_wb),
        .busy_wb    (busy_wb),
        .need_wb    (need_wb),
        .addr_cache (addr_cache),
        .miss_cache (miss_cache),
        .set_cache  (set_cache),

        .busy_rd    (busy_rd),
        .addr_rd    (addr_rd),
        .data_rd    (data_rd),
        .wen_rd     (wen_rd),
        .set_rd     (set_rd),
        .finish_rd  (finish_rd),
        .switch_mode(switch_mode)
    );

    CacheWriteBuffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (BANK_NUM)
    ) cache_write_buffer (
        .clk       (clk),
        .rst       (rst),
        .addr_wb   (addr_wb),
        .data_wb   (data_wb),
        .busy_wb   (busy_wb),
        .need_wb   (need_wb),
        .miss_cache(miss_cache),
        .addr_mem  (addr_mem),
        .data_mem  (data_mem),
        .bank_index(bank_index),
        .finish_wb (finish_wb)
    );

    cmu_state_e cmu_state;
    addr_t      refill_base_addr;
    logic       refill_way;
    offset_t    beat_count;

    localparam integer LAST_BANK = BANK_NUM - 1;

    logic       read_last;
    logic       write_last;
    addr_t      beat_offset;
    logic       read_wait_resp;//表示请求已经发出但还没有相应
    logic       write_wait_resp;
    logic       read_req_fire;
    logic       read_resp_fire;
    logic       write_req_fire;
    logic       write_resp_fire;
    logic       read_resp_now;
    logic       write_resp_now;

    assign read_last = (beat_count == LAST_BANK[OFFSET_LEN-1:0]);//标志完成最后一个beat的数据传输
    assign write_last = (beat_count == LAST_BANK[OFFSET_LEN-1:0]);
    assign beat_offset = {{(ADDR_WIDTH - OFFSET_LEN - GRANU_LEN){1'b0}}, beat_count, {GRANU_LEN{1'b0}}};//todo

    assign read_req_fire = (cmu_state == CMU_READ) && !read_wait_resp && rready_in;
    assign read_resp_now = read_req_fire && rvalid_in;
    assign read_resp_fire = (cmu_state == CMU_READ) &&
                            ((read_wait_resp && rvalid_in) || read_resp_now);//同拍返回和跨拍返回

    assign write_req_fire = (cmu_state == CMU_WRITE) && !write_wait_resp && wready_in;
    assign write_resp_now = write_req_fire && wvalid_in;
    assign write_resp_fire = (cmu_state == CMU_WRITE) &&
                             ((write_wait_resp && wvalid_in) || write_resp_now);

    //给cachebank的refill信号
    assign busy_rd = (cmu_state == CMU_READ);//READ状态就表示CMU正在忙着refill
    assign data_rd = rdata_in;
    assign set_rd = refill_way;//新line应该写入的set
    assign addr_rd = refill_base_addr + beat_offset;
    assign wen_rd = read_resp_fire;
    assign finish_rd = read_resp_fire && read_last;//最后一个beat的数据被接收时，refill完成

    //给write back buffer的信号
    assign bank_index = beat_count;
    assign finish_wb = write_resp_fire && write_last;//最后一个beat的数据被接收时，write back buffer完成

    //对整个cache外部的信号
    assign busy_cache = (cmu_state != CMU_IDLE) || busy_wb;//即使 cmu_state == IDLE，只要 busy_wb=1，说明系统里还有待写回工作
    assign write_busy_cache = (cmu_state == CMU_WRITE);
    assign wb_busy = busy_wb;
    assign wb_addr = addr_mem;
    assign ren_mem = (cmu_state == CMU_READ) && !read_wait_resp;
    assign wen_mem = (cmu_state == CMU_WRITE) && !write_wait_resp;
    assign raddr_out = refill_base_addr + beat_offset;//line base + 0/8/16/24
    assign waddr_out = addr_mem + beat_offset;//+ 0/8/16/24
    assign wdata_out = data_mem;
    assign wmask_out = {BYTE_NUM{1'b1}};//todo，当前设计是每次写一个完整的cache line，所以wmask全1，如果改成分块写，就要根据beat_count来设置wmask



    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmu_state <= CMU_IDLE;
            refill_base_addr <= '0;
            refill_way <= 1'b0;
            beat_count <= '0;
            read_wait_resp <= 1'b0;
            write_wait_resp <= 1'b0;
        end else begin
            unique case (cmu_state)

                CMU_IDLE: begin
                    beat_count <= '0;
                    read_wait_resp <= 1'b0;
                    write_wait_resp <= 1'b0;
                    if (miss_cache) begin
                        cmu_state <= CMU_READ;
                        refill_base_addr <= addr_cache;
                        refill_way <= set_cache;
                    end
                end

                CMU_READ: begin
                    if (!read_wait_resp) begin//如果当前没有挂起的等响应的读请求，说明a.同拍返回，b.请求发出但没回来，c.下层不ready,请求本拍根本没发出去
                        if (read_req_fire) begin//如果下层ready
                            if (read_resp_now) begin//同拍相应
                                if (read_last) begin//当前是最后一个beat
                                    beat_count <= '0;
                                    read_wait_resp <= 1'b0;
                                    if (busy_wb) begin
                                        cmu_state <= CMU_WRITE;
                                    end else begin
                                        cmu_state <= CMU_IDLE;
                                    end
                                end else begin//如果当前不是最后一个beat
                                    beat_count <= beat_count + 1'b1;
                                    read_wait_resp <= 1'b0;
                                end
                            end else begin//还没有响应，挂起请求
                                read_wait_resp <= 1'b1;
                            end
                        end
                    end

                    else if (read_resp_fire) begin// 当前有一个已发出但尚未返回的读请求；本拍它的响应终于回来了（跨拍返回）
                        if (read_last) begin
                            beat_count <= '0;
                            read_wait_resp <= 1'b0;
                            if (busy_wb) begin
                                cmu_state <= CMU_WRITE;
                            end else begin
                                cmu_state <= CMU_IDLE;
                            end
                        end else begin
                            beat_count <= beat_count + 1'b1;
                            read_wait_resp <= 1'b0;//当前 beat 的响应已经收到了，所以下一拍不再等待旧响应，可以尝试发下一个 beat 的请求
                        end
                    end
                end

                CMU_WRITE: begin
                    if (!write_wait_resp) begin//当前没有挂起的待响应的请求
                        if (write_req_fire) begin//如果下层ready
                            if (write_resp_now) begin//同拍返回
                                if (write_last) begin
                                    beat_count <= '0;
                                    write_wait_resp <= 1'b0;
                                    cmu_state <= CMU_IDLE;
                                end else begin
                                    beat_count <= beat_count + 1'b1;
                                    write_wait_resp <= 1'b0;
                                end
                            end else begin
                                write_wait_resp <= 1'b1;
                            end
                        end
                    end else if (write_resp_fire) begin
                        if (write_last) begin
                            beat_count <= '0;
                            write_wait_resp <= 1'b0;
                            cmu_state <= CMU_IDLE;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                            write_wait_resp <= 1'b0;
                        end
                    end
                end

                default: begin
                    cmu_state <= CMU_IDLE;
                    beat_count <= '0;
                    read_wait_resp <= 1'b0;
                    write_wait_resp <= 1'b0;
                end
            endcase
        end
    end

endmodule
