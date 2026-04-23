`timescale 1ns / 1ps
`include"mem_ift.vh"
`include"bus_struct.vh"

module Axi_Bram #(
    parameter FILE_PATH = "",
    parameter DATA_WIDTH = 64,
    parameter CAPACITY = 4096
)(
    input clk,
    input rstn,
    Axi_ift.Slave mem_ift
);
    import BusPack::*;

    localparam BYTE_NUM = DATA_WIDTH/8;
    localparam MEM_LINE = CAPACITY/BYTE_NUM;
    localparam ADDR_WIDTH = $clog2(MEM_LINE);
    localparam ADDR_BEGIN = $clog2(BYTE_NUM);
    localparam ADDR_END = ADDR_BEGIN + ADDR_WIDTH - 1;

    // initial begin
    // $display("%s",FILE_PATH);
    // end

    logic mem_wen;
    logic [BYTE_NUM-1:0] mem_wmask;
    logic [DATA_WIDTH-1:0] mem_wdata;
    logic [mem_ift.ADDR_WIDTH-1:0] mem_waddr_temp;
    logic [ADDR_WIDTH-1:0] mem_waddr;
    BusPack::resp_t mem_bresp;
    logic [mem_ift.ADDR_WIDTH-1:0] mem_raddr_temp;
    logic [ADDR_WIDTH-1:0] mem_raddr;
    logic mem_ren;
    logic [DATA_WIDTH-1:0] mem_rdata;
    BusPack::resp_t mem_rresp;
    assign mem_waddr = mem_waddr_temp[ADDR_END:ADDR_BEGIN];
    assign mem_raddr = mem_raddr_temp[ADDR_END:ADDR_BEGIN];

    AxiSlavePipeline #(
        .ADDR_WIDTH(mem_ift.ADDR_WIDTH),
        .DATA_WIDTH(mem_ift.DATA_WIDTH)
    )  axi_pipeline (
        .clk(clk),
        .rstn(rstn),
        .mem_ift(mem_ift),

        .mem_wen(mem_wen),
        .mem_wmask(mem_wmask),
        .mem_wdata(mem_wdata),
        .mem_waddr(mem_waddr_temp),
        .mem_bresp(mem_bresp),

        .mem_raddr(mem_raddr_temp),
        .mem_ren(mem_ren),
        .mem_rdata(mem_rdata),
        .mem_rresp(mem_rresp)
    );

    BRAM #(
        .FILE_PATH(FILE_PATH),
        .DATA_WIDTH(DATA_WIDTH),
        .CAPACITY(CAPACITY)
    ) bram (
        .clk(clk),
        .rstn(rstn),
        .mem_wen(mem_wen),
        .mem_waddr(mem_waddr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_ren(mem_ren),
        .mem_raddr(mem_raddr),
        .mem_rdata(mem_rdata)
    );

    assign mem_bresp = OKAY;
    assign mem_rresp = OKAY;

endmodule

module BRAM #(
    parameter FILE_PATH = "",
    parameter DATA_WIDTH = 64,
    parameter CAPACITY = 4096
) (
    input  logic clk,
    input  logic rstn,
    input  logic mem_wen,
    input  logic [$clog2(CAPACITY/(DATA_WIDTH/8))-1:0] mem_waddr,
    input  logic [DATA_WIDTH-1:0] mem_wdata,
    input  logic [DATA_WIDTH/8-1:0] mem_wmask,
    input  logic mem_ren,
    input  logic [$clog2(CAPACITY/(DATA_WIDTH/8))-1:0] mem_raddr,
    output logic [DATA_WIDTH-1:0] mem_rdata
);
    localparam BYTE_NUM = DATA_WIDTH/8;
    localparam MEM_LINE = CAPACITY/BYTE_NUM;
    localparam ADDR_WIDTH = $clog2(MEM_LINE);

    integer i;
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] block_mem [0:MEM_LINE-1];
    initial begin
        $readmemh(FILE_PATH, block_mem);
    end

    logic [ADDR_WIDTH-1:0] mem_raddr_reg;
    always@(posedge clk)begin
        if(mem_ren)begin
            mem_raddr_reg <= mem_raddr;
        end
        if(rstn)begin
            if(mem_wen)begin
                for(i=0;i<BYTE_NUM;i=i+1)begin
                    if(mem_wmask[i])begin
                        block_mem[mem_waddr][i*8+:8] <= mem_wdata[i*8+:8];
                    end
                end
            end
        end
    end

    assign mem_rdata = block_mem[mem_raddr_reg];
    
endmodule

module MEM_Single_Dram #(
    parameter FILE_PATH = "",
    parameter DATA_WIDTH = 64,
    parameter CAPACITY = 4096
) (
    input clk,
    input rstn,
    Mem_ift.Slave imem_ift,
    Mem_ift.Slave dmem_ift
);
    import BusPack::*;

    localparam BYTE_NUM = DATA_WIDTH / 8;
    localparam DEPTH = CAPACITY / BYTE_NUM;
    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam ADDR_OFFSET = $clog2(BYTE_NUM); 

    DRAM #(
        .FILE_PATH(FILE_PATH),
        .DATA_WIDTH(DATA_WIDTH),
        .CAPACITY(CAPACITY)
    ) dram (
        .clk(clk),
        .wen(dmem_ift.w_request_valid & dmem_ift.w_request_ready),
        .waddr(dmem_ift.w_request_bits.waddr[ADDR_WIDTH+ADDR_OFFSET-1:ADDR_OFFSET]),
        .wdata(dmem_ift.w_request_bits.wdata),
        .wmask(dmem_ift.w_request_bits.wmask),

        .raddr0(imem_ift.r_request_bits.raddr[ADDR_WIDTH+ADDR_OFFSET-1:ADDR_OFFSET]),
        .rdata0(imem_ift.r_reply_bits.rdata),

        .raddr1(dmem_ift.r_request_bits.raddr[ADDR_WIDTH+ADDR_OFFSET-1:ADDR_OFFSET]),
        .rdata1(dmem_ift.r_reply_bits.rdata)
    );

    assign dmem_ift.w_request_ready = 1'b1;
    assign dmem_ift.w_reply_valid = 1'b1;
    assign dmem_ift.w_reply_bits = '{bresp:OKAY};

    assign dmem_ift.r_request_ready = 1'b1;
    assign dmem_ift.r_reply_bits.rresp = OKAY;
    assign dmem_ift.r_reply_valid = 1'b1;

    assign imem_ift.w_request_ready = 1'b0;
    assign imem_ift.w_reply_valid = 1'b0;
    assign imem_ift.w_reply_bits = '{bresp:OKAY};

    assign imem_ift.r_request_ready = 1'b1;
    assign imem_ift.r_reply_bits.rresp = OKAY;
    assign imem_ift.r_reply_valid = 1'b1;

endmodule

module DRAM #(
    parameter FILE_PATH = "",
    parameter DATA_WIDTH = 64,
    parameter CAPACITY = 4096
) (
    input  clk,
    input  wen,
    input  [$clog2(CAPACITY/(DATA_WIDTH/8))-1:0] waddr,
    input  [DATA_WIDTH-1:0] wdata,
    input  [DATA_WIDTH/8-1:0] wmask,
    input  [$clog2(CAPACITY/(DATA_WIDTH/8))-1:0] raddr0,
    output [DATA_WIDTH-1:0] rdata0,
    input  [$clog2(CAPACITY/(DATA_WIDTH/8))-1:0] raddr1,
    output [DATA_WIDTH-1:0] rdata1
);

    localparam BYTE_NUM = DATA_WIDTH / 8;
    localparam DEPTH = CAPACITY / BYTE_NUM;
    integer i;
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    initial begin
        $readmemh(FILE_PATH, mem);
    end

    always @(posedge clk) begin
        if (wen) begin
            for(i = 0; i < BYTE_NUM; i = i+1) begin
                if(wmask[i]) begin
                    mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
                end
            end
        end
    end

    assign rdata0 = mem[raddr0];
    assign rdata1 = mem[raddr1];
endmodule
