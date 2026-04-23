`include "core_struct.vh"

module CacheBank #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM   = 4,
    parameter integer CAPACITY   = 1024
) (
    input clk,
    input rst,

    input   CorePack::addr_t  addr_cpu,//cpu传入的数据，读写地址，data,写使能，写掩码，读使能
    input   CorePack::data_t  wdata_cpu,
    input                     wen_cpu,
    input   CorePack::mask_t  wmask_cpu,
    input                     ren_cpu,
    //传回cpu读到的数据和是否hit
    output  CorePack::data_t  rdata_cpu,
    output                    hit_cpu,

//把要传回cpu的数据传给write back buffer和cmu
    output  CorePack::addr_t          addr_wb,
    output  [BANK_NUM*DATA_WIDTH-1:0] data_wb,
    input                             busy_wb,
    output                            need_wb,

    output  CorePack::addr_t  addr_cache,
    output                    miss_cache,
    output                    set_cache,
    input                     busy_rd,
    input   CorePack::addr_t  addr_rd,
    input   CorePack::data_t  data_rd,
    input                     wen_rd,
    input                     set_rd,
    input                     finish_rd,
    input                     switch_mode
);

//用参数定义怎么切分地址
    localparam integer BYTE_NUM = DATA_WIDTH / 8;
    localparam integer LINE_NUM = CAPACITY / 2 / (BANK_NUM * BYTE_NUM);//cacheling行数

    localparam integer GRANU_LEN = $clog2(BYTE_NUM);//=3,最第三位表示字节偏移
    localparam integer GRANU_BEGIN = 0;
    localparam integer GRANU_END = GRANU_BEGIN + GRANU_LEN - 1;

    localparam integer OFFSET_LEN = $clog2(BANK_NUM);
    localparam integer OFFSET_BEGIN = GRANU_END + 1;
    localparam integer OFFSET_END = OFFSET_BEGIN + OFFSET_LEN - 1;

    localparam integer INDEX_LEN = $clog2(LINE_NUM);
    localparam integer INDEX_BEGIN = OFFSET_END + 1;
    localparam integer INDEX_END = INDEX_BEGIN + INDEX_LEN - 1;

    localparam integer TAG_BEGIN = INDEX_END + 1;
    localparam integer TAG_END = ADDR_WIDTH - 1;
    localparam integer TAG_LEN = ADDR_WIDTH - TAG_BEGIN;

    typedef logic [TAG_LEN-1:0] tag_t;
    typedef logic [INDEX_LEN-1:0] index_t;
    typedef logic [OFFSET_LEN-1:0] offset_t;
    typedef logic [BANK_NUM*DATA_WIDTH-1:0] line_data_t;

    logic       valid_arr [1:0][LINE_NUM-1:0];
    logic       dirty_arr [1:0][LINE_NUM-1:0];
    logic       lru_arr   [1:0][LINE_NUM-1:0];
    tag_t       tag_arr   [1:0][LINE_NUM-1:0];
    line_data_t data_arr  [1:0][LINE_NUM-1:0];

    tag_t    tag_cpu;
    index_t  index_cpu;
    offset_t offset_cpu;
    tag_t    tag_rd;
    index_t  index_rd;
    offset_t offset_rd;

    logic [1:0] hit;
    line_data_t way0_line;
    line_data_t way1_line;
    logic [DATA_WIDTH-1:0] way0_word;
    logic [DATA_WIDTH-1:0] way1_word;
    wire [OFFSET_END:0] pad_zero = {(OFFSET_END + 1){1'b0}};
    wire miss_happen;


    //把cpu传进来的地址切开
    assign tag_cpu = addr_cpu[TAG_END:TAG_BEGIN];
    assign index_cpu = addr_cpu[INDEX_END:INDEX_BEGIN];
    assign offset_cpu = addr_cpu[OFFSET_END:OFFSET_BEGIN];

    //把CMU传进来的地址切开
    assign tag_rd = addr_rd[TAG_END:TAG_BEGIN];
    assign index_rd = addr_rd[INDEX_END:INDEX_BEGIN];
    assign offset_rd = addr_rd[OFFSET_END:OFFSET_BEGIN];

    //判断是否命中
    assign hit[0] = (tag_arr[0][index_cpu] == tag_cpu) && valid_arr[0][index_cpu];
    assign hit[1] = (tag_arr[1][index_cpu] == tag_cpu) && valid_arr[1][index_cpu];
    assign hit_cpu = |hit;

    //读数据输出
    assign way0_line = data_arr[0][index_cpu];
    assign way1_line = data_arr[1][index_cpu];
    assign way0_word = way0_line[offset_cpu*DATA_WIDTH +: DATA_WIDTH];
    assign way1_word = way1_line[offset_cpu*DATA_WIDTH +: DATA_WIDTH];
    assign rdata_cpu = hit[0] ? way0_word : way1_word;

    assign set_cache = lru_arr[0][index_cpu];//看替换哪一路
    assign miss_happen = ~hit_cpu && (wen_cpu || ren_cpu);
    assign need_wb = miss_happen && dirty_arr[set_cache][index_cpu];//这次发生了miss,并且被替换掉victim是脏数据，就要写回memmory
    assign miss_cache = miss_happen && ~busy_wb && ~busy_rd && ~switch_mode;//todomiss发生了，且有条件可以处理

    assign addr_cache = {addr_cpu[TAG_END:INDEX_BEGIN], pad_zero};//新来的miss行在内存中的地址
    //把offset+granu(byte）这些低位全清零，取出cacheline首地址
    assign addr_wb = {tag_arr[set_cache][index_cpu], index_cpu, pad_zero};//被替换掉旧行在内存中的地址
    //把offset和byte这些低位全清零，得到cacheline首地址（因为cacheline在内存中是取多个连续的字节的，所以地址的低位要清零）
    assign data_wb = data_arr[set_cache][index_cpu];

    integer i;
    integer j;
    integer k;
    integer l;

    //valid控制
    always_ff @(posedge clk) begin
        if (rst) begin//reset时所有line都无效
            for (i = 0; i < LINE_NUM; i = i + 1) begin
                valid_arr[0][i] <= 1'b0;
                valid_arr[1][i] <= 1'b0;
            end
        end else if (finish_rd) begin
            valid_arr[set_rd][index_rd] <= 1'b1;
        end else if (miss_cache) begin//处理miss时，要把要被替换掉的行的valid位清零（不管它原来是有效还是无效，都要清零，因为它要被新行覆盖了）
            valid_arr[set_cache][index_cpu] <= 1'b0;
        end
    end

    //dirty控制
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < LINE_NUM; i = i + 1) begin
                dirty_arr[0][i] <= 1'b0;
                dirty_arr[1][i] <= 1'b0;
            end
        end else if (hit_cpu && wen_cpu) begin
            if (hit[0]) begin
                dirty_arr[0][index_cpu] <= 1'b1;
            end
            if (hit[1]) begin
                dirty_arr[1][index_cpu] <= 1'b1;
            end
        end else if (miss_cache) begin//开始处理miss时，先把要被替换掉的行的dirty位清零（不管它原来是脏还是干净，都要清零，因为它要被新行覆盖了）
            dirty_arr[set_cache][index_cpu] <= 1'b0;
        end
    end


    //lru控制
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < LINE_NUM; i = i + 1) begin
                lru_arr[0][i] <= 1'b0;
                lru_arr[1][i] <= 1'b0;
            end
        end else if (finish_rd) begin
            lru_arr[0][index_rd] <= ~set_rd;
            lru_arr[1][index_rd] <= set_rd;//新装进来的那一路标记为最近被使用过
        end else if (hit_cpu && (wen_cpu || ren_cpu)) begin
            lru_arr[0][index_cpu] <= hit[0];
            lru_arr[1][index_cpu] <= hit[1];//最近被访问过的那一路标记为最近被使用过
        end
    end

    //tag控制
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < LINE_NUM; i = i + 1) begin
                tag_arr[0][i] <= {TAG_LEN{1'b0}};
                tag_arr[1][i] <= {TAG_LEN{1'b0}};
            end
        end else if (miss_cache) begin
            tag_arr[set_cache][index_cpu] <= tag_cpu;//valid已经被清零，所以不用担心误命中
        end
    end

    //data控制
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 2; i = i + 1) begin
                for (j = 0; j < LINE_NUM; j = j + 1) begin
                    data_arr[i][j] <= {(DATA_WIDTH * BANK_NUM){1'b0}};
                end
            end
        end else begin
            for (i = 0; i < 2; i = i + 1) begin
                for (j = 0; j < LINE_NUM; j = j + 1) begin
                    for (k = 0; k < BANK_NUM; k = k + 1) begin
                        //CMU写回（用i[0],j[index_len-1:0]等与要比较的数据进行位宽匹配，要不会报错）
                        if ((set_rd == i[0]) && wen_rd && (index_rd == j[INDEX_LEN-1:0]) &&
                            (offset_rd == k[OFFSET_LEN-1:0])) begin
                            data_arr[i][j][k*DATA_WIDTH +: DATA_WIDTH] <= data_rd;
                        //CPU写命中（已经hit了，就不用再比较tag了，这里的比较只是用来找位置的）
                        end else if (hit[i] && wen_cpu && (index_cpu == j[INDEX_LEN-1:0]) &&
                                     (offset_cpu == k[OFFSET_LEN-1:0])) begin
                            for (l = 0; l < BYTE_NUM; l = l + 1) begin
                                if (wmask_cpu[l]) begin//根据字节掩码写入数据
                                    data_arr[i][j][k*DATA_WIDTH + 8*l +: 8] <= wdata_cpu[8*l +: 8];
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
