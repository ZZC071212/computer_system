`timescale 1ns / 1ps
`include"mem_ift.vh"
`include"bus_struct.vh"
`include"misc_struct.vh"

module Axi_MiscUnit (
    input clk,
    input rstn,
    Axi_ift.Slave mem_ift,

    output time_int,
    output MiscPack::MiscInfo cosim_misc_info
);
    import BusPack::*;
    import MiscPack::*;

    localparam AXI_DATA_WIDTH = mem_ift.DATA_WIDTH;
    localparam AXI_BYTE_NUM   = AXI_DATA_WIDTH/8;
    localparam AXI_ADDR_WIDTH = mem_ift.ADDR_WIDTH;
    localparam DATA_WIDTH = MISC_DATA_WIDTH;
    localparam ADDR_WIDTH = MISC_ADDR_WIDTH;

    logic [AXI_BYTE_NUM-1:0] mem_wmask_tmp;
    logic [AXI_DATA_WIDTH-1:0] mem_wdata_tmp;
    logic [AXI_ADDR_WIDTH-1:0] mem_waddr_tmp;

    logic mem_wen;
    logic [ADDR_WIDTH-1:0] mem_waddr;
    logic [DATA_WIDTH-1:0] mem_wdata;
    BusPack::resp_t mem_bresp;

    assign mem_waddr = mem_waddr_tmp[ADDR_WIDTH-1:0];
    assign mem_wdata = mem_wdata_tmp[DATA_WIDTH-1:0];

    logic [AXI_ADDR_WIDTH-1:0] mem_raddr_tmp;
    logic [AXI_DATA_WIDTH-1:0] mem_rdata_tmp;
    
    logic mem_ren;
    logic [ADDR_WIDTH-1:0] mem_raddr;
    logic [DATA_WIDTH-1:0] mem_rdata;
    BusPack::resp_t mem_rresp;

    assign mem_raddr = mem_raddr_tmp[ADDR_WIDTH-1:0];
    assign mem_rdata_tmp = {{(AXI_DATA_WIDTH-DATA_WIDTH){1'b0}}, mem_rdata};
    
    AxiSlavePipeline #(
        .ADDR_WIDTH(mem_ift.ADDR_WIDTH),
        .DATA_WIDTH(mem_ift.DATA_WIDTH)
    )  axi_pipeline (
        .clk(clk),
        .rstn(rstn),
        .mem_ift(mem_ift),

        .mem_wen(mem_wen),
        .mem_wmask(mem_wmask_tmp),
        .mem_wdata(mem_wdata_tmp),
        .mem_waddr(mem_waddr_tmp),
        .mem_bresp(mem_bresp),

        .mem_raddr(mem_raddr_tmp),
        .mem_ren(mem_ren),
        .mem_rdata(mem_rdata_tmp),
        .mem_rresp(mem_rresp)
    );

    logic [DATA_WIDTH-1:0] misc_mtime;
    logic [DATA_WIDTH-1:0] misc_mtimecmp;
    logic [DATA_WIDTH-1:0] misc_display;

    logic w_is_mtimecmp;
    logic w_is_display;
    assign w_is_mtimecmp = mem_waddr == MTIMECMP_REG_OFFSET;
    assign w_is_display = mem_waddr == DISPLAY_REG_OFFSET;

    always_ff@(posedge clk)begin
        if(~rstn)begin
            misc_mtime <= {DATA_WIDTH{1'b0}};
        end else begin
            misc_mtime <= misc_mtime + {{(DATA_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    always_ff@(posedge clk)begin
        if(~rstn)begin
            misc_mtimecmp <= {DATA_WIDTH{1'b0}};
        end else if(mem_wen & w_is_mtimecmp)begin
            misc_mtimecmp <= mem_wdata;
            `ifdef MISC_DEBUG
                $display("write misc_mtiemcmp %x", mem_wdata);
            `endif
        end
    end

    always_ff@(posedge clk)begin
        if(~rstn)begin
            misc_display <= {DATA_WIDTH{1'b0}};
        end else if(mem_wen & w_is_display)begin
            misc_display <= {misc_display[DATA_WIDTH-9:0], mem_wdata[7:0]};
            `ifdef MISC_DEBUG
                $display("write misc_display %c", mem_wdata[7:0]);
            `endif
        end
    end

    always_ff@(posedge clk)begin
        if(~rstn)begin
            mem_bresp <= OKAY;
        end else if(mem_wen)begin
            if(w_is_mtimecmp | w_is_display)begin
                mem_bresp <= OKAY;
            end else begin
                mem_bresp <= SLVERR;
            end
        end
    end

    logic r_is_mtime;
    logic r_is_mtimecmp;
    logic r_is_display;
    assign r_is_mtime = mem_raddr == MTIME_REG_OFFSET;
    assign r_is_mtimecmp = mem_raddr == MTIMECMP_REG_OFFSET;
    assign r_is_display = mem_raddr == DISPLAY_REG_OFFSET;

    always_ff@(posedge clk)begin
        if(~rstn)begin
            mem_rdata <= {DATA_WIDTH{1'b0}};
            mem_rresp <= OKAY;
        end else if(mem_ren)begin
            case({r_is_mtime, r_is_mtimecmp, r_is_display})
                3'b100:begin
                    mem_rdata <= misc_mtime;
                    mem_rresp <= OKAY;
                end
                3'b010:begin
                    mem_rdata <= misc_mtimecmp;
                    mem_rresp <= OKAY;
                end
                3'b001:begin
                    mem_rdata <= misc_display;
                    mem_rresp <= OKAY;
                end
                default:begin
                    mem_rdata <= {DATA_WIDTH{1'b1}};
                    mem_rresp <= SLVERR;
                end
            endcase
        end
    end

    assign time_int = misc_mtimecmp < misc_mtime;
    assign cosim_misc_info.misc_mtime = misc_mtime;
    assign cosim_misc_info.misc_mtimecmp = misc_mtimecmp;
    assign cosim_misc_info.misc_display = misc_display;

endmodule