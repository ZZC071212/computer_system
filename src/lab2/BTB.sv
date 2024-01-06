module BTB #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 64,
    parameter STATE_NUM = 2
) (
    input clk,
    input rst,
    input [ADDR_WIDTH-1:0] pc_if,
    output jump_if,
    output [ADDR_WIDTH-1:0] pc_target_if,
    
    input [ADDR_WIDTH-1:0] pc_exe,
    input [ADDR_WIDTH-1:0] pc_target_exe,
    input jump_exe,
    input is_jump_exe
);

    localparam INDEX_BEGIN = 1;
    localparam INDEX_LEN = $clog2(DEPTH);
    localparam INDEX_END = INDEX_BEGIN+INDEX_LEN-1;
    localparam TAG_BEGIN = INDEX_END+1;
    localparam TAG_END = ADDR_WIDTH-1;
    localparam TAG_LEN = TAG_END-TAG_BEGIN+1;

    typedef logic [TAG_LEN-1:0] tag_t;
    typedef logic [INDEX_LEN-1:0] index_t;
    typedef logic [STATE_NUM-1:0] state_t;
    typedef logic [ADDR_WIDTH-1:0] addr_t;

    typedef struct{
        tag_t tag;
        addr_t target;
        state_t state;
        logic valid;
    } BTBLine;

    BTBLine btb [DEPTH-1:0];

    tag_t tag_exe;
    index_t index_exe; 
    BTBLine btb_exe; 
    assign tag_exe = pc_exe[TAG_END:TAG_BEGIN];
    assign index_exe = pc_exe[INDEX_END:INDEX_BEGIN];
    assign btb_exe = btb[index_exe];

    integer i;
    always @(posedge clk) begin
        if(rst)begin
            for(i=0;i<DEPTH;i=i+1)begin
                btb[i].tag<={TAG_LEN{1'b0}};
                btb[i].target<={ADDR_WIDTH{1'b0}};
                btb[i].state<={STATE_NUM{1'b0}};
                btb[i].valid<=1'b0;
            end
        end else if(is_jump_exe)begin
            if(btb_exe.tag!=tag_exe|btb_exe.valid==1'b0|btb_exe.target!=pc_target_exe)begin
                btb[index_exe].tag<=tag_exe;
                btb[index_exe].target<=pc_target_exe;
                btb[index_exe].state<={{(STATE_NUM-1){1'b0}},1'b1};
                btb[index_exe].valid<=1'b1;
            end else if(jump_exe&btb_exe.state!={STATE_NUM{1'b1}})begin
                btb[index_exe].state<=btb_exe.state+{{(STATE_NUM-1){1'b0}},1'b1};
            end else if(~jump_exe&btb_exe.state!={STATE_NUM{1'b0}})begin
                btb[index_exe].state<=btb_exe.state-{{(STATE_NUM-1){1'b0}},1'b1};
            end
        end
    end
    
    tag_t tag_if;
    index_t index_if;
    BTBLine btb_if;
    assign tag_if = pc_if[TAG_END:TAG_BEGIN];
    assign index_if = pc_if[INDEX_END:INDEX_BEGIN];
    assign btb_if = btb[index_if];
    assign jump_if = btb_if.tag==tag_if & btb_if.valid ? btb_if.state[STATE_NUM-1] : 1'b0;
    assign pc_target_if = btb_if.target;

endmodule