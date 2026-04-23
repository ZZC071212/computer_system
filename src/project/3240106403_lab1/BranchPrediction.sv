module BranchPrediction #(
    parameter DEPTH      = 32,//表示表有32项
    parameter ADDR_WIDTH = 64,
    parameter STATE_NUM  = 3//默认采用 2-bit 饱和计数器
) (
    input                   clk,
    input                   rst,
    input  [ADDR_WIDTH-1:0] pc_if,
    output                  jump_pred_if,
    output [ADDR_WIDTH-1:0] pc_target_if,

    input [ADDR_WIDTH-1:0]  pc_exe,
    input [ADDR_WIDTH-1:0]  pc_target_exe,
    input                   is_jump_exe,
    input                   inst_is_jump_exe
);

    localparam INDEX_BEGIN = 2;//指令按4字节对齐，最低两位恒为0，不能用来当索引
    localparam INDEX_LEN   = $clog2(DEPTH);
    localparam INDEX_END   = INDEX_BEGIN + INDEX_LEN - 1;
    localparam TAG_BEGIN   = INDEX_END + 1;
    localparam TAG_END     = ADDR_WIDTH - 1;
    localparam TAG_LEN     = TAG_END - TAG_BEGIN + 1;

    typedef logic [TAG_LEN-1:0]      tag_t;
    typedef logic [INDEX_LEN-1:0]    index_t;
    typedef logic [STATE_NUM-1:0]    state_t;
    typedef logic [ADDR_WIDTH-1:0]   addr_t;

    typedef struct packed {
        tag_t   tag;
        addr_t  target;
        state_t state;
        logic   valid;
    } BTBLine;

    BTBLine btb [DEPTH-1:0];//32项的表

    tag_t   tag_exe;
    index_t index_exe;
    BTBLine btb_exe;
    assign tag_exe   = pc_exe[TAG_END:TAG_BEGIN];
    assign index_exe = pc_exe[INDEX_END:INDEX_BEGIN];
    assign btb_exe   = btb[index_exe];//按索引读表
    assign hit_exe  = btb_exe.valid && (btb_exe.tag == tag_exe);

    tag_t   tag_if;
    index_t index_if;
    BTBLine btb_if;
    logic   hit_if;
    logic   hit_exe;
    assign tag_if   = pc_if[TAG_END:TAG_BEGIN];
    assign index_if = pc_if[INDEX_END:INDEX_BEGIN];
    assign btb_if   = btb[index_if];
    assign hit_if   = btb_if.valid && (btb_if.tag == tag_if);//看是否命中表项
//     第 44 行用 pc_exe 的低位算出 index_exe，从 btb 里取出对应表项，给 EXE 阶段用。
//     作用是：当前分支到了 EXE，已经知道真实跳不跳了，就要读出这行旧表项，检查 tag/valid，再决定
//     怎么更新 state 和 target。
//   - 第 53 行用 pc_if 的低位算出 index_if，从 btb 里取出对应表项，给 IF 阶段用。
//     作用是：取指时先查预测表，看这条 PC 有没有命中；如果命中且状态认为“跳”，就用表里的 target
//     作为预测目标

    function automatic state_t next_state(
        input state_t cur_state,
        input logic   taken
    );
        state_t state_next;
        begin
            state_next = cur_state;
            if (taken) begin
                if (state_next != state_t'({STATE_NUM{1'b1}})) begin
                    state_next = state_next + state_t'(1);
                end
            end else if (state_next != state_t'('0)) begin
                state_next = state_next - state_t'(1);
            end
            return state_next;
        end
    endfunction//btb

    assign jump_pred_if = hit_if && btb_if.state[STATE_NUM-1];
    assign pc_target_if = hit_if ? btb_if.target : (pc_if + addr_t'(64'd4));//命中表项时用bht中的目标地址，否则用pc+4

    integer i;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                btb[i].tag    <= '0;
                btb[i].target <= '0;
                btb[i].state  <= '0;
                btb[i].valid  <= 1'b0;
            end//清空表
        end else if (inst_is_jump_exe) begin
            btb[index_exe].tag    <= tag_exe;
            btb[index_exe].target <= pc_target_exe;
            //调用状态转移函数
            btb[index_exe].state  <= next_state(hit_exe ? btb_exe.state : state_t'('0), is_jump_exe);//如果原来命中则在现在状态下更新，如果原来没有命中，则从00开始更新
            btb[index_exe].valid  <= 1'b1;
        end//更新表
    end

endmodule
