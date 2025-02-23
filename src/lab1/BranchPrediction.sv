module BranchPrediction #(
    parameter DEPTH      = 32,
    parameter ADDR_WIDTH = 64,
    parameter STATE_NUM  = 2
) (
    input                   clk,
    input                   rst,
    input  [ADDR_WIDTH-1:0] pc_if,          // The current PC，for indexing the table entrance
    output                  jump_pred_if,     // BHT predict to jump or not
    output [ADDR_WIDTH-1:0] pc_target_if,   // BHT gives the predicted target PC

    // The EXE phase carries out the confirmation and correction of jumps, 
    // and the update of BHT and BTB
    input [ADDR_WIDTH-1:0] pc_exe,          
    input [ADDR_WIDTH-1:0] pc_target_exe,   // The true target jump PC, for updating BTB
    input                  is_jump_exe,    // The true jumping result，for updating BHT
    input                  inst_is_jump_exe // The current whether a jump/branch instruction or not
);

    localparam INDEX_BEGIN = 2;
    localparam INDEX_LEN = $clog2(DEPTH);
    localparam INDEX_END = INDEX_BEGIN + INDEX_LEN - 1;
    localparam TAG_BEGIN = INDEX_END + 1;
    localparam TAG_END = ADDR_WIDTH - 1;
    localparam TAG_LEN = TAG_END - TAG_BEGIN + 1;

    typedef logic [TAG_LEN-1:0] tag_t;
    typedef logic [INDEX_LEN-1:0] index_t;
    typedef logic [STATE_NUM-1:0] state_t;
    typedef logic [ADDR_WIDTH-1:0] addr_t;

    typedef struct {
        tag_t   tag;
        addr_t  target;     // BTB: Jump target address
        state_t state;      // BHT: State bits
        logic   valid;
    } BTBLine;              // BHT Line

    BTBLine btb       [DEPTH-1:0];  //BTB with BHT 

    tag_t   tag_exe;
    index_t index_exe;
    BTBLine btb_exe;
    assign tag_exe   = pc_exe[TAG_END:TAG_BEGIN];
    assign index_exe = pc_exe[INDEX_END:INDEX_BEGIN];
    assign btb_exe   = btb[index_exe];


    tag_t   tag_if;
    index_t index_if;
    BTBLine btb_if;
    assign tag_if   = pc_if[TAG_END:TAG_BEGIN];
    assign index_if = pc_if[INDEX_END:INDEX_BEGIN];
    assign btb_if   = btb[index_if];

    //TODO: Fill yuor code here.

endmodule
