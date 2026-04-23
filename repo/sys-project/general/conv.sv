`timescale 1ns / 1ps
`include"mem_ift.vh"
`include"bus_struct.vh"
`include"conv_struct.vh"

module Axi_ConvUnit #(
    parameter LEN
)(
    input clk,
    input rstn,
    Axi_ift.Slave mem_ift,

    output ConvPack::ConvInfo cosim_conv_info
);
    import BusPack::*;
    import ConvPack::*;

    localparam AXI_DATA_WIDTH = mem_ift.DATA_WIDTH;
    localparam AXI_BYTE_NUM   = AXI_DATA_WIDTH/8;
    localparam AXI_ADDR_WIDTH = mem_ift.ADDR_WIDTH;
    localparam DATA_WIDTH = CONV_DATA_WIDTH;
    localparam ADDR_WIDTH = CONV_ADDR_WIDTH;

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

    logic start;
    logic [DATA_WIDTH-1:0] in_data;
    logic write_kernel;
    logic [DATA_WIDTH-1:0] in_kernel;
    logic [2*DATA_WIDTH-1:0] out_result;
    logic finish;

    logic r_is_result_lo;
    assign r_is_result_lo = mem_raddr == KERNEL_REG_OFFSET;
    logic r_is_result_hi;
    assign r_is_result_hi = mem_raddr == DATA_REG_OFFSET;
    logic r_is_state;
    assign r_is_state = mem_raddr == STATE_REG_OFFSET;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            mem_rdata <= {DATA_WIDTH{1'b0}};
            mem_rresp <= OKAY;
        end else if(mem_ren)begin
            case({r_is_result_lo, r_is_result_hi, r_is_state})
                3'b100:begin
                    mem_rdata <= out_result[DATA_WIDTH-1:0];
                    mem_rresp <= finish?OKAY:SLVERR;
                end
                3'b010:begin
                    mem_rdata <= out_result[DATA_WIDTH*2-1:DATA_WIDTH];
                    mem_rresp <= finish?OKAY:SLVERR;
                end
                3'b001:begin
                    mem_rdata <= {{(DATA_WIDTH-1){1'b0}}, finish};
                    mem_rresp <= OKAY;
                end
                default:begin
                    mem_rdata <= {DATA_WIDTH{1'b1}};
                    mem_rresp <= SLVERR;
                end
            endcase
        end
    end

    logic w_is_data;
    logic w_is_kernel;
    assign w_is_data = mem_waddr == DATA_REG_OFFSET;
    assign w_is_kernel = mem_waddr == KERNEL_REG_OFFSET;
    assign in_data = mem_wdata;
    assign in_kernel = mem_wdata;
    assign start = mem_wen & w_is_data;
    assign write_kernel = mem_wen & w_is_kernel;

    always_ff@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            mem_bresp <= OKAY;
        end else if(mem_wen)begin
            if(w_is_data | w_is_kernel)begin
                mem_bresp <= OKAY;
            end else begin
                mem_bresp <= SLVERR;
            end
        end
    end

    ConvUnit #(
        .DATA_WIDTH(DATA_WIDTH),
        .LEN(LEN)
    ) conv_unit (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .in_data(in_data),
        .write_kernel(write_kernel),
        .in_kernel(in_kernel),
        .out_result(out_result),
        .finish(finish)
    );

    assign cosim_conv_info.conv_result = out_result;
    assign cosim_conv_info.conv_state = {63'b0, finish};

endmodule

module ConvUnit #(
    parameter DATA_WIDTH,
    parameter LEN
)(
    input logic clk,
    input logic rstn,
    input logic start,
    input logic [DATA_WIDTH-1:0] in_data,
    input logic write_kernel,
    input logic [DATA_WIDTH-1:0] in_kernel,
    output logic [2*DATA_WIDTH-1:0] out_result,
    output logic finish
);

    logic [DATA_WIDTH-1:0] kernel_array [LEN-1:0];

    Shift #(
        .LEN(LEN),
        .DATA_WIDTH(DATA_WIDTH)
    ) shifter (
        .clk(clk),
        .rstn(rstn),
        .wen(write_kernel),
        .in_data(in_kernel),
        .out_data(kernel_array) 
    );
    `ifdef CONV_DEBUG
        always_ff@(posedge clk)begin
            if(write_kernel)begin
                $display("conv_unit:write_kernel %x", in_kernel);
            end
        end
    `endif

    logic [2*DATA_WIDTH-1:0] tmp_array [LEN-1:0];
    logic [2*DATA_WIDTH-1:0] product_array [LEN-1:0];
    
    logic finish_array [LEN-1:0];
    generate
        for(genvar i=0;i<LEN;i=i+1)begin
            Multiplier #(
                .DATA_WIDTH(DATA_WIDTH),
                .COMP_CYCLE(32)
            ) multiplier (
                .clk(clk),
                .rstn(rstn),
                .start(start),
                .multiplicand(kernel_array[i]),
                .multiplier(in_data),
                .finish(finish_array[i]),
                .product(product_array[i])
            );
        end
    endgenerate

    integer i;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            for(i=0;i<LEN;i=i+1)begin
                tmp_array[i] <= {DATA_WIDTH*2{1'b0}};
            end
        end else if(finish_array[0])begin
            tmp_array[0] <= product_array[0];
            for(i=1;i<LEN;i=i+1)begin
                tmp_array[i] <= tmp_array[i-1] + product_array[i];
            end
        end
    end

    always_ff@(posedge clk)begin
        if(~rstn)finish<=1'b1;
        else if(start)finish<=1'b0;
        else if(finish_array[0])finish<=1'b1;
    end

    assign out_result = tmp_array[LEN-1];

    `ifdef CONV_DEBUG
        logic record;
        always_ff@(posedge clk)begin
            record <= finish;
            if(~record&finish)begin
                $display("conv_unit:result_ready %x", out_result);
            end
        end
    `endif

endmodule

module Multiplier #(
    parameter DATA_WIDTH,
    parameter COMP_CYCLE
)(
    input logic clk,
    input logic rstn,
    input logic start,
    input logic [DATA_WIDTH-1:0] multiplicand,
    input logic [DATA_WIDTH-1:0] multiplier,
    output logic finish,
    output logic [2*DATA_WIDTH-1:0] product
);

    initial begin
        assert(DATA_WIDTH%COMP_CYCLE==0) 
        else begin
            $display("the stage in multiplier is not balance, stop");
            $finish;
        end
    end

    localparam ITER_NUM = DATA_WIDTH/COMP_CYCLE;
    localparam CNT_LEN = $clog2(COMP_CYCLE);
    localparam CNT_BOUND_FULL = COMP_CYCLE - 1;
    localparam [CNT_LEN-1:0] CNT_BOUND = CNT_BOUND_FULL[CNT_LEN-1:0];
    logic [CNT_LEN-1:0] cnt;
    typedef enum logic [1:0] {IDLE,WORK,FINI} fsm_state_t;
    fsm_state_t fsm_state;
    fsm_state_t next_fsm_state;

    logic [DATA_WIDTH-1:0] product_hi;
    logic [DATA_WIDTH-1:0] product_lo;
    logic [DATA_WIDTH-1:0] multiplicand_reg;
    `ifdef CONV_DEBUG
        logic [DATA_WIDTH-1:0] multiplier_reg;
    `endif

    always_ff@(posedge clk)begin
        if(~rstn)begin
            fsm_state <= IDLE;
        end else begin
            fsm_state <= next_fsm_state;
        end
    end

    always_comb begin
        case(fsm_state)
            IDLE:begin
                if(start)next_fsm_state=WORK;
                else next_fsm_state=IDLE;
            end
            WORK:begin
                if(cnt==CNT_BOUND)next_fsm_state=FINI;
                else next_fsm_state=WORK;
            end
            default:begin
                if(start)next_fsm_state=WORK;
                else next_fsm_state=IDLE;
            end
        endcase
    end

    logic start_comp;
    logic finish_comp;
    assign start_comp = (fsm_state!=WORK)&(next_fsm_state==WORK);
    assign finish = fsm_state == FINI;

    logic [DATA_WIDTH:0] product_tmp [ITER_NUM-1:0] /* verilator split_var */;
    logic [DATA_WIDTH-1+ITER_NUM:0] product_hi_tmp;
    logic [DATA_WIDTH-1-ITER_NUM:0] product_lo_tmp;
    assign product_tmp[0] = {1'b0 , {multiplicand_reg & {DATA_WIDTH{product_lo[0]}}}} + {1'b0, product_hi};
    generate
        for(genvar i=0;i<ITER_NUM-1;i=i+1)begin
            assign product_tmp[i+1] = {1'b0 , {multiplicand_reg & {DATA_WIDTH{product_lo[i+1]}}}} + {1'b0, product_tmp[i][DATA_WIDTH:1]};
        end
        for(genvar i=0;i<ITER_NUM-1;i=i+1)begin
            assign product_hi_tmp[i] = product_tmp[i][0];
        end
        assign product_hi_tmp[DATA_WIDTH+ITER_NUM-1:ITER_NUM-1] = product_tmp[ITER_NUM-1];
        assign product_lo_tmp = product_lo[DATA_WIDTH-1:ITER_NUM];
    endgenerate

    always_ff@(posedge clk)begin
        if(start_comp)begin
            cnt<={CNT_LEN{1'b0}};
            multiplicand_reg <= multiplicand;
            product_hi <= {DATA_WIDTH{1'b0}};
            product_lo <= multiplier;
            `ifdef CONV_DEBUG
                multiplier_reg <= multiplier;
            `endif
        end else if(fsm_state == WORK)begin
            cnt <= cnt+{{(CNT_LEN-1){1'b0}},1'b1};
            {product_hi, product_lo} <= {product_hi_tmp, product_lo_tmp};
        end
    end

    assign product = {product_hi, product_lo};

    `ifdef CONV_DEBUG
        logic [127:0] product_result_tmp; 
        always_ff@(posedge clk)begin
            if(finish)begin
                product_result_tmp = (multiplicand_reg * multiplier_reg);
                assert(product_result_tmp == product)
                else begin
                    $display("the result of multiplicand:%x, multiplier:%x is %x", multiplicand, multiplier, product);
                    $finish;
                end
            end
        end
    `endif

endmodule

module Shift #(
    parameter LEN,
    parameter DATA_WIDTH
)(
    input logic clk,
    input logic rstn,
    input logic wen,
    input logic [DATA_WIDTH-1:0] in_data,
    output logic [DATA_WIDTH-1:0] out_data [LEN-1:0] 
);

    integer i;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            for(i=0;i<LEN;i=i+1)begin
                out_data[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if(wen)begin
            for(i=0;i<LEN-1;i=i+1)begin
                out_data[i] <= out_data[i+1];
            end
            out_data[LEN-1] <= in_data;
        end
    end

endmodule