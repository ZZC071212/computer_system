`include"mem_ift.vh"
`include"bus_struct.vh"

module Axi_InterConnect #(
    parameter INPUT_NUM = 2,
    parameter OUTPUT_NUM = 3,
    parameter [OUTPUT_NUM*64-1:0] MEM_BEGIN,
    parameter [OUTPUT_NUM*64-1:0] MEM_END
) (
    input clk,
    input rstn,
    Axi_ift.Slave master_ift [INPUT_NUM-1:0], // master_ift[0] is dummy master
    Axi_ift.Master slave_ift [OUTPUT_NUM:0] // slave_ift[0] is dummy slave
);

    Axi_ift #(
        .ADDR_WIDTH(master_ift[0].ADDR_WIDTH),
        .DATA_WIDTH(master_ift[0].DATA_WIDTH)
    ) arb_ift ();

    Axi_Arb #(
        .INPUT_NUM(INPUT_NUM)
    ) axi_arb (
        .clk(clk),
        .rstn(rstn),
        .master_ift(master_ift),
        .arb_ift(arb_ift.Master)
    );

    Axi_Router #(
        .OUTPUT_NUM(OUTPUT_NUM),
        .MEM_BEGIN(MEM_BEGIN),
        .MEM_END(MEM_END)
    ) axi_router (
        .clk(clk),
        .rstn(rstn),
        .arb_ift(arb_ift.Slave),
        .slave_ift(slave_ift)
    );

endmodule

`define Axi_Connect_M21(__tmp_wire_name, __wire_width, __loop_num, __src_ift, __ift_entry, __dest_ift, __index, __grant)\
    logic [``__wire_width``-1:0] ``__tmp_wire_name`` [``__loop_num``-1:0];\
    generate\
        for(genvar i=0;i<``__loop_num``;i=i+1)begin\
            assign ``__tmp_wire_name``[i] = ``__src_ift``[i].``__ift_entry``;\
        end\
        if(``__wire_width`` == 1)begin\
            assign ``__dest_ift``.``__ift_entry`` = ``__tmp_wire_name``[``__index``] & ``__grant``[``__index``];\
        end else begin\
            assign ``__dest_ift``.``__ift_entry`` = ``__tmp_wire_name``[``__index``];\
        end\
    endgenerate

module Axi_Router #(
    parameter OUTPUT_NUM = 3,
    parameter [OUTPUT_NUM*64-1:0] MEM_BEGIN,
    parameter [OUTPUT_NUM*64-1:0] MEM_END
)(
    input clk,
    input rstn,
    Axi_ift.Slave arb_ift,
    Axi_ift.Master slave_ift [OUTPUT_NUM:0]
);

    logic [OUTPUT_NUM:0] w_bound /* verilator split_var */;
    logic [OUTPUT_NUM:0] w_request;

    /* verilator lint_off UNSIGNED */
    generate 
        for(genvar i=1;i<=OUTPUT_NUM;i=i+1)begin:set_w_bound_outer
            assign w_bound[i] = 
                (arb_ift.w_addr_request_bits.waddr >= MEM_BEGIN[64*(i-1)+:64]) &
                (arb_ift.w_addr_request_bits.waddr < MEM_END[64*(i-1)+:64]);
        end
    endgenerate
    /* verilator lint_on UNSIGNED */
    assign w_bound[0] = ~|w_bound[OUTPUT_NUM:1];
    assign w_request = w_bound & {(OUTPUT_NUM+1){arb_ift.w_addr_request_valid}};
    
    logic w_finish;
    assign w_finish = arb_ift.w_reply_valid & arb_ift.w_reply_ready;
    logic [$clog2(OUTPUT_NUM+1)-1:0] w_arb_sel;
    logic [OUTPUT_NUM:0] w_grant;
    request_arb #(
        .LEN(OUTPUT_NUM+1),
        .ROBIN(1'b0)
    ) w_arb (
        .clk(clk),
        .rstn(rstn),
        .request(w_request),
        .finish(w_finish),
        .arb_sel(w_arb_sel),
        .grant(w_grant)
    );

    `define Router_W_Connect(__tmp_wire_name, __wire_width, __ift_entry)\
        `Axi_Connect_M21(``__tmp_wire_name``, ``__wire_width``, OUTPUT_NUM+1, slave_ift, ``__ift_entry``, arb_ift, w_arb_sel, w_grant)

    `Router_W_Connect(waddr_ready_tmp, 1, w_addr_request_ready);
    `Router_W_Connect(wdata_ready_tmp, 1, w_data_request_ready);
    `Router_W_Connect(w_bresp_tmp, 2, w_reply_bits.bresp);
    `Router_W_Connect(w_resp_valid_tmp, 1, w_reply_valid);

    generate
        for(genvar i=0;i<=OUTPUT_NUM;i=i+1)begin
            assign slave_ift[i].w_addr_request_bits = arb_ift.w_addr_request_bits;
            assign slave_ift[i].w_addr_request_valid = arb_ift.w_addr_request_valid & w_grant[i];
            assign slave_ift[i].w_data_request_bits = arb_ift.w_data_request_bits;
            assign slave_ift[i].w_data_request_valid = arb_ift.w_data_request_valid & w_grant[i];
            assign slave_ift[i].w_reply_ready = arb_ift.w_reply_ready & w_grant[i];
        end
    endgenerate

    //===============================================================================

    logic [OUTPUT_NUM:0] r_bound /* verilator split_var */;
    logic [OUTPUT_NUM:0] r_request;

    /* verilator lint_off UNSIGNED */
    generate 
        for(genvar i=1;i<=OUTPUT_NUM;i=i+1)begin:set_r_bound_outer
            assign r_bound[i] = 
                (arb_ift.r_request_bits.raddr >= MEM_BEGIN[64*(i-1)+:64]) &
                (arb_ift.r_request_bits.raddr < MEM_END[64*(i-1)+:64]);
        end
    endgenerate
    /* verilator lint_on UNSIGNED */
    assign r_bound[0] = ~|r_bound[OUTPUT_NUM:1];
    assign r_request = r_bound & {(OUTPUT_NUM+1){arb_ift.r_request_valid}};
    
    logic r_finish;
    assign r_finish = arb_ift.r_reply_valid & arb_ift.r_reply_ready;
    logic [$clog2(OUTPUT_NUM+1)-1:0] r_arb_sel;
    logic [OUTPUT_NUM:0] r_grant;
    request_arb #(
        .LEN(OUTPUT_NUM+1),
        .ROBIN(1'b0)
    ) r_arb (
        .clk(clk),
        .rstn(rstn),
        .request(r_request),
        .finish(r_finish),
        .arb_sel(r_arb_sel),
        .grant(r_grant)
    );

    `define Router_R_Connect(__tmp_wire_name, __wire_width, __ift_entry)\
        `Axi_Connect_M21(``__tmp_wire_name``, ``__wire_width``, OUTPUT_NUM+1, slave_ift, ``__ift_entry``, arb_ift, r_arb_sel, r_grant)

    
    `Router_R_Connect(r_request_ready_tmp, 1, r_request_ready);
    `Router_R_Connect(r_rdata_tmp, arb_ift.DATA_WIDTH, r_reply_bits.rdata);
    `Router_R_Connect(r_rresp_tmp, 2, r_reply_bits.rresp);
    `Router_R_Connect(r_reply_valid, 1, r_reply_valid);

    generate
        for(genvar i=0;i<=OUTPUT_NUM;i=i+1)begin
            assign slave_ift[i].r_request_bits = arb_ift.r_request_bits;
            assign slave_ift[i].r_request_valid = arb_ift.r_request_valid & r_grant[i];
            assign slave_ift[i].r_reply_ready = arb_ift.r_reply_ready & r_grant[i];
        end
    endgenerate

endmodule

module Axi_Arb #(
    parameter INPUT_NUM = 2
)(
    input clk,
    input rstn,
    Axi_ift.Slave master_ift [INPUT_NUM-1:0],
    Axi_ift.Master arb_ift
);

    logic [INPUT_NUM-1:0] w_request;
    generate
        for(genvar i=0;i<INPUT_NUM;i=i+1)begin
            assign w_request[i] = master_ift[i].w_addr_request_valid;
        end
    endgenerate

    logic w_finish;
    assign w_finish = arb_ift.w_reply_valid & arb_ift.w_reply_ready;
    logic [$clog2(INPUT_NUM)-1:0] w_arb_sel;
    logic [INPUT_NUM-1:0] w_grant;
    request_arb #(
        .LEN(INPUT_NUM),
        .ROBIN(1'b1)
    ) w_arb (
        .clk(clk),
        .rstn(rstn),
        .request(w_request),
        .finish(w_finish),
        .arb_sel(w_arb_sel),
        .grant(w_grant)
    );

    `define Arb_W_Connect(__tmp_wire_name, __wire_width, __ift_entry)\
        `Axi_Connect_M21(``__tmp_wire_name``, ``__wire_width``, INPUT_NUM, master_ift, ``__ift_entry``, arb_ift, w_arb_sel, w_grant)

    `Arb_W_Connect(w_waddr_tmp, arb_ift.ADDR_WIDTH, w_addr_request_bits.waddr);
    `Arb_W_Connect(w_waddr_valid_tmp, 1, w_addr_request_valid);
    `Arb_W_Connect(w_wdata_tmp, arb_ift.DATA_WIDTH, w_data_request_bits.wdata);
    `Arb_W_Connect(w_wstrb_tmp, arb_ift.DATA_WIDTH/8, w_data_request_bits.wstrb);
    `Arb_W_Connect(w_wdata_valid_tmp, 1, w_data_request_valid);
    `Arb_W_Connect(w_reply_ready_tmp, 1, w_reply_ready);

    generate
        for(genvar i=0;i<INPUT_NUM;i=i+1)begin
            assign master_ift[i].w_addr_request_ready = arb_ift.w_addr_request_ready & w_grant[i];
            assign master_ift[i].w_data_request_ready = arb_ift.w_data_request_ready & w_grant[i];
            assign master_ift[i].w_reply_bits = arb_ift.w_reply_bits;
            assign master_ift[i].w_reply_valid = arb_ift.w_reply_valid & w_grant[i];
        end
    endgenerate

    //========================================================================

    logic [INPUT_NUM-1:0] r_request;
    generate
        for(genvar i=0;i<INPUT_NUM;i=i+1)begin
            assign r_request[i] = master_ift[i].r_request_valid;
        end
    endgenerate

    logic r_finish;
    assign r_finish = arb_ift.r_reply_valid & arb_ift.r_reply_ready;
    logic [$clog2(INPUT_NUM)-1:0] r_arb_sel;
    logic [INPUT_NUM-1:0] r_grant;
    request_arb #(
        .LEN(INPUT_NUM),
        .ROBIN(1'b1)
    ) r_arb (
        .clk(clk),
        .rstn(rstn),
        .request(r_request),
        .finish(r_finish),
        .arb_sel(r_arb_sel),
        .grant(r_grant)
    );

    `define Arb_R_Connect(__tmp_wire_name, __wire_width, __ift_entry)\
        `Axi_Connect_M21(``__tmp_wire_name``, ``__wire_width``, INPUT_NUM, master_ift, ``__ift_entry``, arb_ift, r_arb_sel, r_grant)

    `Arb_R_Connect(r_raddr_tmp, arb_ift.ADDR_WIDTH, r_request_bits.raddr);
    `Arb_R_Connect(r_request_valid_tmp, 1, r_request_valid);
    `Arb_R_Connect(r_reply_ready_tmp, 1, r_reply_ready);

    generate
        for(genvar i=0;i<INPUT_NUM;i=i+1)begin
            assign master_ift[i].r_request_ready = arb_ift.r_request_ready & r_grant[i];
            assign master_ift[i].r_reply_bits = arb_ift.r_reply_bits;
            assign master_ift[i].r_reply_valid = arb_ift.r_reply_valid & r_grant[i];
        end
    endgenerate


endmodule

module request_arb #(
    parameter LEN,
    parameter ROBIN
)(
    input clk,
    input rstn,
    input [LEN-1:0] request,
    input finish,
    output logic [$clog2(LEN)-1:0] arb_sel,
    output logic [LEN-1:0] grant
);

    logic [LEN-1:0] grant_tmp;
    generate
        if(ROBIN)begin
            RobinArb #(
                .LEN(LEN)
            ) w_robin (
                .clk(clk),
                .rstn(rstn),
                .req(request),
                .grant(grant_tmp)
            );
        end else begin
            assign grant_tmp = request;
        end
    endgenerate

    localparam BIN_LEN = $clog2(LEN);
    logic [BIN_LEN-1:0] arb_sel_tmp;
    onehot2bin #(
        .LEN(LEN)
    ) w_o2b (
        .onehot(grant_tmp),
        .bin(arb_sel_tmp)
    );

    logic task_work;
    assign task_work = |grant;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            grant <= {LEN{1'b0}};
            arb_sel <= {BIN_LEN{1'b0}};
        end else if(~task_work|finish|(arb_sel==arb_sel_tmp))begin
            grant <= grant_tmp;
            arb_sel <= arb_sel_tmp;
        end
    end

endmodule

module onehot2bin #(
    parameter LEN
)(
    input [LEN-1:0] onehot,
    output [$clog2(LEN)-1:0] bin
);

    localparam BIN_LEN = $clog2(LEN);

    logic [BIN_LEN-1:0] temp1 [LEN-1:0];
    logic [LEN-1:0] temp2 [BIN_LEN-1:0];

    generate
        for(genvar i=0;i<LEN;i=i+1)begin
            assign temp1[i] = onehot[i] ? i[BIN_LEN-1:0] : {BIN_LEN{1'b0}};
        end
        for(genvar i=0;i<BIN_LEN;i=i+1)begin
            for(genvar j=0;j<LEN;j=j+1)begin
                assign temp2[i][j] = temp1[j][i];
            end
            assign bin[i] = |temp2[i];
        end
    endgenerate

endmodule

`define SlaveConnect_M2N(__temp_name, __wire_len, __wire_name, __work_type)\
    for(i=0;i<=OUTPUT_NUM;i=i+1)begin\
        logic [((``__wire_len``))-1:0] ``__temp_name`` [INPUT_NUM:0] /* verilator split_var */;\
        assign ``__temp_name``[0] = {(``__wire_len``){1'b0}};\
        for(j=0;j<INPUT_NUM;j=j+1)begin\
            assign ``__temp_name``[j+1] = ``__temp_name``[j] | {(``__wire_len``){``__work_type``_index[i][j]}} & master_ift[j].``__wire_name``;\
        end\
        assign slave_ift[i].``__wire_name`` = ``__temp_name``[INPUT_NUM];\
    end

`define MasterConnect_M2N(__temp_name, __wire_len, __wire_name, __work_type)\
    for(i=0;i<INPUT_NUM;i=i+1)begin\
        logic [((``__wire_len``))-1:0] ``__temp_name`` [OUTPUT_NUM+1:0] /* verilator split_var */;\
        assign ``__temp_name``[0] = {(``__wire_len``){1'b0}};\
        for(j=0;j<=OUTPUT_NUM;j=j+1)begin\
            assign ``__temp_name``[j+1] = ``__temp_name``[j] | {(``__wire_len``){``__work_type``_index[j][i]}} & slave_ift[j].``__wire_name``;\
        end\
        assign master_ift[i].``__wire_name`` = ``__temp_name``[OUTPUT_NUM+1];\
    end

module Axi_InterConnect_M2N #(
    parameter INPUT_NUM = 2,
    parameter OUTPUT_NUM = 3,
    parameter [OUTPUT_NUM*64-1:0] MEM_BEGIN,
    parameter [OUTPUT_NUM*64-1:0] MEM_END
) (
    input clk,
    input rstn,
    Axi_ift.Slave master_ift [INPUT_NUM-1:0], // master_ift[INPUT_NUM] is dummy master
    Axi_ift.Master slave_ift [OUTPUT_NUM:0] // slave_ift[OUTPUT_NUM] is dummy slave
);

    localparam DATA_WIDTH = slave_ift[0].DATA_WIDTH;
    localparam ADDR_WIDTH = slave_ift[0].ADDR_WIDTH;

    logic [OUTPUT_NUM:0] w_bound [INPUT_NUM-1:0] /* verilator split_var */;
    logic [OUTPUT_NUM:0] w_request [INPUT_NUM-1:0];
    logic [INPUT_NUM-1:0] w_request_tmp [OUTPUT_NUM:0];
    logic [INPUT_NUM-1:0] w_grant [OUTPUT_NUM:0];

    /* verilator lint_off UNSIGNED */
    genvar i;
    genvar j;
    generate 
        for(i=0;i<INPUT_NUM;i=i+1)begin:set_w_bound_outer
            for(j=0;j<OUTPUT_NUM;j=j+1)begin:set_w_bound_inner
                assign w_bound[i][j] = 
                    (master_ift[i].w_addr_request_bits.waddr >= MEM_BEGIN[64*j+:64]) &
                    (master_ift[i].w_addr_request_bits.waddr < MEM_END[64*j+:64]);
            end
            assign w_bound[i][OUTPUT_NUM] = ~|(w_bound[i][OUTPUT_NUM-1:0]);
            assign w_request[i] = w_bound[i] & {(OUTPUT_NUM+1){master_ift[i].w_addr_request_valid}};
        end
    endgenerate
    /* verilator lint_on UNSIGNED */

    generate
        for(i=0;i<=OUTPUT_NUM;i=i+1)begin:set_write_robin_outer
            for(j=0;j<INPUT_NUM;j=j+1)begin:set_write_robin_inner
                assign w_request_tmp[i][j] = w_request[j][i];
            end
            RobinArb #(
                .LEN(INPUT_NUM)
            ) robin (
                .clk(clk),
                .rstn(rstn),
                .req(w_request_tmp[i]),
                .grant(w_grant[i])
            );
        end
    endgenerate

    logic [INPUT_NUM-1:0] w_task_index [OUTPUT_NUM:0];
    logic w_task_work [OUTPUT_NUM:0];
    logic w_task_finish [OUTPUT_NUM:0];

    generate
        for(i=0;i<=OUTPUT_NUM;i=i+1)begin:set_w_task_loop
            assign w_task_finish[i] = slave_ift[i].w_reply_valid & slave_ift[i].w_reply_ready;
            assign w_task_work[i] = |w_task_index[i];
            always_ff@(posedge clk)begin
                if(~rstn)begin
                    w_task_index[i] <= {INPUT_NUM{1'b0}};
                end else if(~w_task_work[i]|w_task_finish[i]|(w_task_index[i]==w_grant[i]))begin
                    w_task_index[i] <= w_grant[i];
                end
            end
        end
    endgenerate
    
    generate
        `SlaveConnect_M2N(temp_waddr,ADDR_WIDTH,w_addr_request_bits.waddr, w_task);
        `SlaveConnect_M2N(temp_waddr_valid,1,w_addr_request_valid, w_task);
        `MasterConnect_M2N(temp_waddr_ready,1,w_addr_request_ready,w_task);

        `SlaveConnect_M2N(temp_wdata,DATA_WIDTH,w_data_request_bits.wdata, w_task);
        `SlaveConnect_M2N(temp_wstrb,DATA_WIDTH/8,w_data_request_bits.wstrb, w_task);
        `SlaveConnect_M2N(temp_wdata_valid,1,w_data_request_valid, w_task);
        `MasterConnect_M2N(temp_wdata_ready,1,w_data_request_ready,w_task);

        `SlaveConnect_M2N(temp_bresp_ready,1,w_reply_ready, w_task);
        `MasterConnect_M2N(temp_bresp,2,w_reply_bits.bresp,w_task);
        `MasterConnect_M2N(temp_bresp_valid,1,w_reply_valid,w_task);
    endgenerate

    // // r begin

    logic [OUTPUT_NUM:0] r_bound [INPUT_NUM-1:0] /* verilator split_var */;
    logic [OUTPUT_NUM:0] r_request [INPUT_NUM-1:0]; 
    logic [INPUT_NUM-1:0] r_request_tmp [OUTPUT_NUM:0];
    logic [INPUT_NUM-1:0] r_grant [OUTPUT_NUM:0];

    /* verilator lint_off UNSIGNED */
    generate 
        for(i=0;i<INPUT_NUM;i=i+1)begin:set_r_bound_outer
            for(j=0;j<OUTPUT_NUM;j=j+1)begin:set_r_bound_inner
                assign r_bound[i][j] = 
                    (master_ift[i].r_request_bits.raddr >= MEM_BEGIN[64*j+63:64*j]) &
                    (master_ift[i].r_request_bits.raddr < MEM_END[64*j+63:64*j]);
            end
            assign r_bound[i][OUTPUT_NUM] = ~|(r_bound[i][OUTPUT_NUM-1:0]);
            assign r_request[i] = r_bound[i] & {(OUTPUT_NUM+1){master_ift[i].r_request_valid}};
        end
    endgenerate
    /* verilator lint_on UNSIGNED */

    generate
        for(i=0;i<=OUTPUT_NUM;i=i+1)begin:set_read_robin_outer
            for(j=0;j<INPUT_NUM;j=j+1)begin:set_read_robin_inner
                assign r_request_tmp[i][j] = r_request[j][i];
            end
            RobinArb #(
                .LEN(INPUT_NUM)
            ) robin (
                .clk(clk),
                .rstn(rstn),
                .req(r_request_tmp[i]),
                .grant(r_grant[i])
            );
        end
    endgenerate

    logic [INPUT_NUM-1:0] r_task_index [OUTPUT_NUM:0];
    logic r_task_work [OUTPUT_NUM:0];
    logic r_task_finish [OUTPUT_NUM:0];

    generate
        for(i=0;i<=OUTPUT_NUM;i=i+1)begin:set_r_task_loop
            assign r_task_finish[i] = slave_ift[i].r_reply_valid & slave_ift[i].r_reply_ready;
            assign r_task_work[i] = |r_task_index[i];
            always_ff@(posedge clk)begin
                if(~rstn)begin
                    r_task_index[i] <= {INPUT_NUM{1'b0}};
                end else if(~r_task_work[i]|r_task_finish[i]|(r_task_index[i]==r_grant[i]))begin
                    r_task_index[i] <= r_grant[i];
                end
            end
        end
    endgenerate
    
    generate
        `SlaveConnect_M2N(temp_raddr,ADDR_WIDTH,r_request_bits.raddr,r_task);
        `SlaveConnect_M2N(temp_raddr_valid,1,r_request_valid,r_task);
        `MasterConnect_M2N(temp_raddr_ready,1,r_request_ready,r_task);

        `MasterConnect_M2N(temp_rresp,2,r_reply_bits.rresp,r_task);
        `MasterConnect_M2N(temp_rdata,DATA_WIDTH,r_reply_bits.rdata,r_task);
        `MasterConnect_M2N(temp_rresp_valid,1,r_reply_valid,r_task);
        `SlaveConnect_M2N(temp_rresp_ready,1,r_reply_ready,r_task);
    endgenerate

endmodule

module RobinArb #(
    parameter LEN
) (
    input clk,
    input rstn,
    input [LEN-1:0] req,
    output [LEN-1:0] grant
);

    logic [LEN-1:0] base;
    logic [2*LEN-1:0] double_req;
    assign double_req = {req, req};
    logic [2*LEN-1:0] double_grant;
    assign double_grant = double_req & ~(double_req - {{LEN{1'b0}}, base});
    // base is used for rotate shift

    always_ff@(posedge clk)begin
        if(~rstn) 
            base <= {{(LEN-1){1'b0}}, 1'b1};
        else
            base <= {base[LEN-2:0], base[LEN-1]};
    end

    assign grant =  (double_grant[LEN-1:0] | double_grant[2*LEN-1:LEN]);


endmodule

module Axi_DummyMaster(
    Axi_ift.Master master_ift
);

    assign master_ift.r_request_bits.raddr = {master_ift.ADDR_WIDTH{1'b0}};
    assign master_ift.r_request_valid = 1'b0;

    assign master_ift.r_reply_ready = 1'b0;

    assign master_ift.w_addr_request_bits.waddr = {master_ift.ADDR_WIDTH{1'b0}};
    assign master_ift.w_addr_request_valid = 1'b0;

    assign master_ift.w_data_request_bits.wdata = {master_ift.DATA_WIDTH{1'b0}};
    assign master_ift.w_data_request_bits.wstrb = {master_ift.DATA_WIDTH/8{1'b0}};
    assign master_ift.w_data_request_valid = 1'b0;

    assign master_ift.w_reply_ready = 1'b0;

endmodule

module Axi_DummySlave(
    input clk,
    input rstn,
    Axi_ift.Slave slave_ift
);

    import BusPack::*;

    assign slave_ift.w_addr_request_ready = 1'b1;
    assign slave_ift.w_data_request_ready = 1'b1;
    logic w_addr_done;
    logic w_data_done;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            w_addr_done <= 1'b0;
        end else if(slave_ift.w_addr_request_ready & slave_ift.w_addr_request_valid)begin
            w_addr_done <= 1'b1;
            $display("trap except write operation, write addr is %x", slave_ift.w_addr_request_bits.waddr);
        end else if(slave_ift.w_reply_ready & slave_ift.w_reply_valid)begin
            w_addr_done <= 1'b0;
        end
    end
    always_ff@(posedge clk)begin
        if(~rstn)begin
            w_data_done <= 1'b0;
        end else if(slave_ift.w_data_request_ready & slave_ift.w_data_request_valid)begin
            w_data_done <= 1'b1;
        end else if(slave_ift.w_reply_ready & slave_ift.w_reply_valid)begin
            w_data_done <= 1'b0;
        end
    end
    assign slave_ift.w_reply_valid = w_data_done & w_addr_done;
    assign slave_ift.w_reply_bits.bresp = SLVERR;

    assign slave_ift.r_request_ready = 1'b1;
    logic r_addr_done;
    always_ff@(posedge clk)begin
        if(~rstn)begin
            r_addr_done <= 1'b0;
        end else if(slave_ift.r_request_ready & slave_ift.r_request_valid)begin
            r_addr_done <= 1'b1;
            $display("trap except read operation, read addr is %x", slave_ift.r_request_bits.raddr);
        end else if(slave_ift.r_reply_ready & slave_ift.r_reply_valid)begin
            r_addr_done <= 1'b0;
        end
    end
    assign slave_ift.r_reply_valid = r_addr_done;
    assign slave_ift.r_reply_bits.rdata = {slave_ift.DATA_WIDTH{1'b1}};
    assign slave_ift.r_reply_bits.rresp = SLVERR;

endmodule