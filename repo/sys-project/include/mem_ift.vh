`define Mem_Member_Definition(__class, __prefix)\
    __class __prefix``_bits;  \
    ctrl_t __prefix``_valid;      \
    ctrl_t __prefix``_ready;

`define Master_Modport_Declaration(__prefix)\
    output __prefix``_bits,   \
    output __prefix``_valid,  \
    input  __prefix``_ready

`define Slave_Modport_Declaration(__prefix)\
    input __prefix``_bits,   \
    input __prefix``_valid,  \
    output __prefix``_ready

`define Dummy_Mem_ift(__name, __DATA_WIDTH, __ADDR_WIDTH)\
    Mem_ift #(                          \
        .ADDR_WIDTH(``__ADDR_WIDTH``),  \
        .DATA_WIDTH(``__DATA_WIDTH``)   \
    ) ``__name`` ();                    \
    assign ``__name``.r_request_bits='{raddr:{``__ADDR_WIDTH``{1'b0}}};\
    assign ``__name``.r_request_ready=1'b0; \
    assign ``__name``.r_request_valid=1'b0; \
    assign ``__name``.r_reply_bits='{rdata:{``__DATA_WIDTH``{1'b0}},rresp:OKAY};\
    assign ``__name``.r_reply_ready=1'b0;   \
    assign ``__name``.r_reply_valid=1'b0;   \
                                            \
    assign ``__name``.w_request_bits='{waddr:{``__ADDR_WIDTH``{1'b0}},wdata:{``__DATA_WIDTH``{1'b0}},wmask:{(``__DATA_WIDTH``/8){1'b0}}};\
    assign ``__name``.w_request_ready=1'b0; \
    assign ``__name``.w_request_valid=1'b0; \
    assign ``__name``.w_reply_bits='{bresp:OKAY};\
    assign ``__name``.w_reply_ready=1'b0;   \
    assign ``__name``.w_reply_valid=1'b0;

`define MemLink_r_request_M2S(__slave, __master)\
    begin\
        ``__slave``.r_request_valid = ``__master``.r_request_valid; \
        ``__slave``.r_request_bits  = ``__master``.r_request_bits;  \
    end

`define MemLink_r_reply_M2S(__slave, __master)\
    begin\
        ``__slave``.r_reply_ready   = ``__master``.r_reply_ready;\
    end          

`define MemLink_w_request_M2S(__slave, __master)\
    begin\
        ``__slave``.w_request_valid = ``__master``.w_request_valid; \
        ``__slave``.w_request_bits  = ``__master``.w_request_bits;  \
    end

`define MemLink_w_reply_M2S(__slave, __master)\
    begin\
        ``__slave``.w_reply_ready   = ``__master``.w_reply_ready;\
    end

`define MemLink_r_reply_S2M(__master, __slave)\
    begin\
        ``__master``.r_reply_valid  = ``__slave``.r_reply_valid;\
        ``__master``.r_reply_bits   = ``__slave``.r_reply_bits;\
    end

`define MemLink_r_request_S2M(__master, __slave)\
    begin\
        ``__master``.r_request_ready= ``__slave``.r_request_ready;\
    end

`define MemLink_w_reply_S2M(__master, __slave)\
    begin\
        ``__master``.w_reply_valid  = ``__slave``.w_reply_valid;\
        ``__master``.w_reply_bits   = ``__slave``.w_reply_bits;\
    end

`define MemLink_w_request_S2M(__master, __slave)\
    begin\
        ``__master``.w_request_ready= ``__slave``.w_request_ready;\
    end

`define MemLink_Connect(__master, __slave)\
    begin\
        `MemLink_r_request_M2S(``__slave``, ``__master``)\
        `MemLink_r_reply_M2S(``__slave``, ``__master``)\
        `MemLink_w_request_M2S(``__slave``, ``__master``)\
        `MemLink_w_reply_M2S(``__slave``, ``__master``)\
        `MemLink_r_request_S2M(``__master``, ``__slave``)\
        `MemLink_r_reply_S2M(``__master``, ``__slave``)\
        `MemLink_w_request_S2M(``__master``, ``__slave``)\
        `MemLink_w_reply_S2M(``__master``, ``__slave``)\
    end

`define MemLink_r_M2S_choose(__cond_request, __cond_reply, __slave, __master0, __master1)\
    begin\
        if(``__cond_request``)begin                             \
            `MemLink_r_request_M2S(``__slave``, ``__master0``)    \
        end else begin                                          \
            `MemLink_r_request_M2S(``__slave``, ``__master1``)    \
        end                                                     \
                                                                \
        if(``__cond_reply``)begin                               \
            `MemLink_r_reply_M2S(``__slave``, ``__master0``)      \
        end else begin                                          \
            `MemLink_r_reply_M2S(``__slave``, ``__master1``)      \
        end\
    end

`define MemLink_w_M2S_choose(__cond_request, __cond_reply, __slave, __master0, __master1)\
    begin\
        if(``__cond_request``)begin                             \
            `MemLink_w_request_M2S(``__slave``, ``__master0``)    \
        end else begin                                          \
            `MemLink_w_request_M2S(``__slave``, ``__master1``)    \
        end                                                     \
                                                                \
        if(``__cond_reply``)begin                               \
            `MemLink_w_reply_M2S(``__slave``, ``__master0``)      \
        end else begin                                          \
            `MemLink_w_reply_M2S(``__slave``, ``__master1``)      \
        end\
    end

`define MemLink_w_S2M_choose(__cond_request, __cond_reply, __master, __slave0, __slave1)\
    begin\
        if(``__cond_request``)begin                             \
            `MemLink_w_request_S2M(``__master``, ``__slave0``)  \
        end else begin                                          \
            `MemLink_w_request_S2M(``__master``, ``__slave1``)  \
        end                                                     \
        if(``__cond_reply``)begin                               \
            `MemLink_w_reply_S2M(``__master``, ``__slave0``)    \
        end else begin                                          \
            `MemLink_w_reply_S2M(``__master``, ``__slave1``)    \
        end\
    end

`define MemLink_r_S2M_choose(__cond_request, __cond_reply, __master, __slave0, __slave1)\
    begin\
        if(``__cond_request``)begin                             \
            `MemLink_r_request_S2M(``__master``, ``__slave0``)  \
        end else begin                                          \
            `MemLink_r_request_S2M(``__master``, ``__slave1``)  \
        end                                                     \
        if(``__cond_reply``)begin                               \
            `MemLink_r_reply_S2M(``__master``, ``__slave0``)    \
        end else begin                                          \
            `MemLink_r_reply_S2M(``__master``, ``__slave1``)    \
        end\
    end 

`define Mem_Shank_Hand_Fire(__mem_ift, __kind)\
    logic ``__mem_ift``_``__kind``_fire;\
    assign ``__mem_ift``_``__kind``_fire = ``__mem_ift``.``__kind``_ready & ``__mem_ift``.``__kind``_valid;

`define Mem_Slave_Shank_Hand(__mem_ift, __kind, __clk)\
    logic ``__mem_ift``_``__kind``_busy;\
    logic ``__mem_ift``_``__kind``_valid;\
    logic ``__mem_ift``_``__kind``_ready;\
    `Mem_Shank_Hand_Fire(``__mem_ift``, ``__kind``_request)\
    `Mem_Shank_Hand_Fire(``__mem_ift``, ``__kind``_reply)\
    assign ``__mem_ift``.``__kind``_request_ready = ``__mem_ift``_``__kind``_ready;\
    assign ``__mem_ift``.``__kind``_reply_valid = ``__mem_ift``_``__kind``_valid;\
    always@(posedge ``__clk)begin\
        if(~rstn)begin\
            ``__mem_ift``_``__kind``_busy <= 1'b0;\
        end else if(``__mem_ift``_``__kind``_request_fire)begin\
            ``__mem_ift``_``__kind``_busy <= 1'b1;\
        end else if(``__mem_ift``_``__kind``_reply_fire)begin\
            ``__mem_ift``_``__kind``_busy <= 1'b0;\
        end\
    end