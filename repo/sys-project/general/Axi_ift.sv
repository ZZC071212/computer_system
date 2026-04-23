`include"bus_struct.vh"
`include"mem_ift.vh"

interface Axi_ift #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64
);

    import BusPack::*;

    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [DATA_WIDTH/8-1:0] mask_t;
    typedef logic ctrl_t;

    typedef struct {
        addr_t waddr;
    } WaddrRequestBits;

    typedef struct {
        data_t wdata;
        mask_t wstrb;
    } WdataRequestBits;

    typedef struct {
        resp_t bresp;
    } WreplyBits;

    typedef struct {
        addr_t raddr;
    } RrequestBits;

    typedef struct {
        data_t rdata;
        resp_t rresp;
    } RreplyBits;

    `Mem_Member_Definition(RrequestBits, r_request);
    `Mem_Member_Definition(RreplyBits, r_reply);
    `Mem_Member_Definition(WaddrRequestBits, w_addr_request);
    `Mem_Member_Definition(WdataRequestBits, w_data_request);
    `Mem_Member_Definition(WreplyBits, w_reply);

    modport Master(
        `Master_Modport_Declaration(r_request),
        `Slave_Modport_Declaration(r_reply),
        `Master_Modport_Declaration(w_addr_request),
        `Master_Modport_Declaration(w_data_request),
        `Slave_Modport_Declaration(w_reply)
    );

    modport Slave(
        `Slave_Modport_Declaration(r_request),
        `Master_Modport_Declaration(r_reply),
        `Slave_Modport_Declaration(w_addr_request),
        `Slave_Modport_Declaration(w_data_request),
        `Master_Modport_Declaration(w_reply)
    );

endinterface

module AxiSlavePipeline #(
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH
) (
    input clk,
    input rstn,
    Axi_ift.Slave mem_ift,

    output logic mem_wen,
    output logic [DATA_WIDTH/8-1:0] mem_wmask,
    output logic [DATA_WIDTH-1:0] mem_wdata,
    output logic [ADDR_WIDTH-1:0] mem_waddr,
    input BusPack::resp_t mem_bresp,

    output logic [ADDR_WIDTH-1:0] mem_raddr,
    output logic mem_ren,
    input logic [DATA_WIDTH-1:0] mem_rdata,
    input BusPack::resp_t mem_rresp
);

    initial begin
        assert (mem_ift.ADDR_WIDTH == ADDR_WIDTH) 
        else begin
            $display("the addr_width of axi_pipeline and mem_ift are different");
            $finish;
        end
        assert (mem_ift.DATA_WIDTH == DATA_WIDTH) 
        else begin
            $display("the data_width of axi_pipeline and mem_ift are different");
            $finish;
        end
    end

    // fire sign for 5 channel
    logic w_addr_fire;
    assign w_addr_fire = mem_ift.w_addr_request_ready & mem_ift.w_addr_request_valid;
    logic w_data_fire;
    assign w_data_fire = mem_ift.w_data_request_ready & mem_ift.w_data_request_valid;
    logic w_reply_fire;
    assign w_reply_fire = mem_ift.w_reply_ready & mem_ift.w_reply_valid;
    logic r_request_fire;
    assign r_request_fire = mem_ift.r_request_ready & mem_ift.r_request_valid;
    logic r_reply_fire;
    assign r_reply_fire = mem_ift.r_reply_ready & mem_ift.r_reply_valid;

    // write pipeline, three stage
    // stage begin shake when valid reg from last stage is set
    // stage not shake when next stage is stall
    // if next stage is stall or this stage is waiting, the formal last need to stall

    // waddr stage
    logic [mem_ift.ADDR_WIDTH-1:0] waddr_reg;
    logic w_addr_valid; // next stage can work
    logic waddr_stall;  // last stage stall

    assign mem_ift.w_addr_request_ready = ~waddr_stall;
    assign waddr_stall = w_addr_valid & ~w_data_fire;

    always_ff@(posedge clk)begin
        if(~rstn)begin
            w_addr_valid <= 1'b0;
            waddr_reg <= {ADDR_WIDTH{1'b0}};
        end else if(w_addr_fire)begin
            w_addr_valid <= 1'b1;
            waddr_reg <= mem_ift.w_addr_request_bits.waddr;
        end else if(w_data_fire)begin
            w_addr_valid <= 1'b0;
        end
    end

    // wdata stage
    logic wdata_stall;
    logic w_data_valid;

    assign mem_ift.w_data_request_ready = w_addr_valid & ~wdata_stall;
    assign wdata_stall = w_data_valid & ~w_reply_fire;

    always_ff@(posedge clk)begin
        if(~rstn)begin
            w_data_valid <= 1'b0;
        end else if(w_data_fire)begin
            w_data_valid <= 1'b1;
        end else if(w_reply_fire)begin
            w_data_valid <= 1'b0;
        end
    end

    // wresp stall
    assign mem_ift.w_reply_bits.bresp = mem_bresp;
    assign mem_ift.w_reply_valid = w_data_valid;

    // encode sign to slave module
    assign mem_wen = w_data_fire;
    assign mem_wmask = mem_ift.w_data_request_bits.wstrb;
    assign mem_wdata = mem_ift.w_data_request_bits.wdata;
    assign mem_waddr = waddr_reg;
    //-----------------------------------------------------------------
    //-----------------------------------------------------------------

    // read pipeline, two stage

    // request stage
    logic r_request_valid;
    logic r_request_stall;
    
    assign mem_ift.r_request_ready = ~r_request_stall;
    assign r_request_stall = r_request_valid & ~r_reply_fire;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            r_request_valid <= 1'b0;
        end else if(r_request_fire)begin
            r_request_valid <= 1'b1;
        end else if(r_reply_fire)begin
            r_request_valid <= 1'b0;
        end
    end

    // reply stage
    assign mem_ift.r_reply_valid = r_request_valid;
    assign mem_ift.r_reply_bits.rresp = mem_rresp;
    assign mem_ift.r_reply_bits.rdata = mem_rdata;

    // encode for read sign
    assign mem_ren = r_request_fire;
    assign mem_raddr = mem_ift.r_request_bits.raddr;

endmodule