`include "core_struct.vh"
`include "csr_struct.vh"
`include "mem_ift.vh"
import PipelinePack::*;

module Core (
    input clk,
    input rst,
    input time_int,


    Mem_ift.Master imem_ift,
    Mem_ift.Master dmem_ift,

    output cosim_valid,
    output CorePack::CoreInfo cosim_core_info,
    output CsrPack::CSRPack cosim_csr_info,
    output cosim_interrupt,
    output cosim_switch_mode,
    output CorePack::data_t cosim_cause
);
    import CorePack::*;
    import CsrPack::*;


    // CSR and exception state shared across ID/EX/WB.
logic [63:0] csr_val_id;
logic [11:0] csr_addr_id;
logic [1:0]  priv;
logic        switch_mode;
logic [63:0] pc_csr;
logic except_happen_id;


logic [63:0] alu_op1_muxed; 
logic [63:0] alu_op2_muxed; 


    // Final WB data after selecting ALU/load/PC/CSR result.
logic [63:0] final_wdata_for_regfile; 
CsrPack::ExceptPack except_info_id;
CsrPack::ExceptPack except_info_ex3;
CsrPack::ExceptPack except_info_ex4;



    // Pipeline registers.
    IFID IFID_reg;
    IDEXE IDEXE_reg;
    EXEMEM EXEMEM_reg;
    MEMWB MEMWB_reg;
    
    // IF stage state and prediction metadata carried toward EXE.
    logic [63:0] pc, next_pc, pc_plus4;
    logic [63:0] pc_pred_if, pc_redirect;
    logic [63:0] if_req_pc;
    logic if_valid;
    logic jump_pred_if;
    logic [63:0] pc_target_if;
    logic if_req_pred_taken, if_drop_reply;
    logic [63:0] if_req_pred_target;
    logic ifid_pred_taken, idexe_pred_taken;
    logic [63:0] ifid_pred_target, idexe_pred_target;
    logic branch_inst_exe, pred_branch_exe, branch_taken_exe, mispredict_exe;
    assign pc_plus4 = pc + 4;
    
typedef enum logic [2:0] {
    IF_IDLE    = 3'd0,
    IF_IF1     = 3'd1,
    IF_IF2     = 3'd2,
    IF_WAIT1   = 3'd3,
    IF_WAIT2   = 3'd4,
    IF_MEM1    = 3'd5,
    IF_MEM2    = 3'd6
} ifsm_e;

ifsm_e if_state,if_state_n;

wire do_mem = EXEMEM_reg.valid && (EXEMEM_reg.re_mem || EXEMEM_reg.we_mem);


// Handshake helpers for the simple IF/MEM access FSM.
wire i_req_fire = imem_ift.r_request_valid & imem_ift.r_request_ready;
wire i_rep_fire = imem_ift.r_reply_valid   & imem_ift.r_reply_ready;
wire wait_for_i_rep = (if_state == IF_IF2) || (if_state == IF_WAIT2);

wire d_req_fire = (dmem_ift.r_request_valid & dmem_ift.r_request_ready)||(dmem_ift.w_request_valid & dmem_ift.w_request_ready);
wire d_rep_fire = (dmem_ift.r_reply_valid & dmem_ift.r_reply_ready)||(dmem_ift.w_reply_valid & dmem_ift.w_reply_ready);



logic flush;
logic stall;
logic if_stall;
// BTB/BHT lookup chooses the speculative next PC in IF.
assign pc_pred_if = jump_pred_if ? pc_target_if : pc_plus4;

    // EXE redirection wins over the normal predicted next PC.
    always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pc <= 64'h0000_0000;
    end else if(switch_mode) begin
        pc <= pc_csr;
    end
     else if (flush) begin
        pc <= pc_redirect;
    end else if (stall||mem_stall||csr_raw_hazard) begin
        pc <= pc;
    end else begin
        pc <= pc_pred_if;
    end
end
    // IF FSM serializes instruction fetch and data-memory traffic.
    always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        if_state <= IF_IF1;
    end else begin
        if_state <= if_state_n;
    end
end

    always_comb begin
    unique case (if_state)
        IF_IDLE:   if_state_n = IF_IF1; 
        IF_IF1: begin
            if (do_mem)                    if_state_n = IF_WAIT1;   
            else if (i_req_fire)           if_state_n = IF_IF2;     
            else                           if_state_n = IF_IF1;     
        end

        IF_IF2: begin
            if (i_rep_fire)                if_state_n = IF_IDLE;
            else                           if_state_n = IF_IF2;
        end

        IF_WAIT1: begin
            if (i_req_fire)                if_state_n = IF_WAIT2;
            else                           if_state_n = IF_WAIT1;
        end

        IF_WAIT2: begin
            if (i_rep_fire)                if_state_n = IF_MEM1;
            else                           if_state_n = IF_WAIT2;
        end

        IF_MEM1: begin
            if (d_req_fire)                if_state_n = IF_MEM2;    
            else                           if_state_n = IF_MEM1;
        end

        IF_MEM2: begin
            if (d_rep_fire)                if_state_n = IF_IDLE;    
            else                           if_state_n = IF_MEM2;
        end

        default:                            if_state_n = IF_IDLE;
    endcase
end

logic mem_stall;
logic mem_req_pending;
wire mem_req_start = IDEXE_reg.re_mem||IDEXE_reg.we_mem;
wire mem_req_done = (dmem_ift.r_request_valid && dmem_ift.r_request_ready) || (dmem_ift.w_request_valid && dmem_ift.w_request_ready);


always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mem_req_pending <= 1'b0;
    end else begin
        if (mem_req_start)           mem_req_pending <= 1'b1;
        else if (mem_req_done)       mem_req_pending <= 1'b0;
    end
end

assign mem_stall = mem_req_pending;

always_comb begin
    if_stall=~imem_ift.r_reply_valid;
end



assign imem_ift.r_request_bits.raddr  = pc;
assign imem_ift.r_request_valid       = (if_state==IF_IF1) || (if_state==IF_WAIT1);
assign imem_ift.r_reply_ready         = wait_for_i_rep;

    CorePack::inst_t inst_from_imem;
    assign inst_from_imem = if_req_pc[2] ? imem_ift.r_reply_bits.rdata[63:32] : imem_ift.r_reply_bits.rdata[31:0];

// Latch the prediction used for the fetch request so EXE can validate it later.
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        if_req_pc          <= 64'h0;
        if_req_pred_taken  <= 1'b0;
        if_req_pred_target <= 64'h0;
        if_drop_reply      <= 1'b0;
    end else begin          // 锁存住流数据（因为并不在下一拍就取指令）所以要在请求握手成功的那一刻把这次请求的是谁，当时怎么预测的保存下来，数据与信号对应
        if (flush || switch_mode) begin
            IFID_reg.valid <= 1'b0;
        end
        if (i_req_fire) begin
            if_req_pc          <= pc;
            if_req_pred_taken  <= jump_pred_if;
            if_req_pred_target <= pc_target_if;
        end

        if (i_rep_fire) begin
            if_drop_reply <= 1'b0;
        end else if ((flush || switch_mode) && wait_for_i_rep) begin
            if_drop_reply <= 1'b1;
        end
    end
end

// Flush drops any younger wrong-path instruction already fetched.
always_ff @(posedge clk or posedge rst) begin
    if (rst || flush ||switch_mode) begin
        IFID_reg.valid <= 1'b0;
        IFID_reg.pc    <= 64'h0;
        IFID_reg.inst  <= 32'h0;
        IFID_reg.pc_4  <= '0;
    end else if (stall||mem_stall||csr_raw_hazard) begin
        IFID_reg <= IFID_reg; 
    end else if (i_rep_fire && !if_drop_reply) begin
        IFID_reg.valid <= 1'b1;
        IFID_reg.pc    <= if_req_pc;
        IFID_reg.inst  <= inst_from_imem;
        IFID_reg.pc_4  <= if_req_pc + 4;
    end else begin
        IFID_reg.valid <=1'b0;
    end
end

// Carry predicted direction/target beside the instruction into ID and EXE.
always_ff @(posedge clk or posedge rst) begin
    if (rst || flush || switch_mode) begin
        ifid_pred_taken  <= 1'b0;
        ifid_pred_target <= 64'h0;
    end else if (stall||mem_stall||csr_raw_hazard) begin
        ifid_pred_taken  <= ifid_pred_taken;
        ifid_pred_target <= ifid_pred_target;
    end else if (i_rep_fire && !if_drop_reply) begin
        ifid_pred_taken  <= if_req_pred_taken;
        ifid_pred_target <= if_req_pred_target;
    end else begin
        ifid_pred_taken  <= 1'b0;
        ifid_pred_target <= 64'h0;
    end
end

    // ID stage decode and register read.
    logic [63:0] read_data_1, read_data_2;
    logic we_reg_id, we_mem_id, re_mem_id, npc_sel_id;
    logic id_valid;
    logic csr_ren_id, csr_wen_id, is_csr_op_id;
    logic [1:0] csr_ret_id;
    CsrPack::csr_alu_op_enmu csr_cmd_id;
    
    alu_op_enum alu_op_id;
    cmp_op_enum cmp_op_id;
    alu_asel_op_enum alu_asel_id;
    alu_bsel_op_enum alu_bsel_id;
    csr_alu_bsel_op_enum  csr_alu_bsel_id;
    wb_sel_op_enum wb_sel_id;
    mem_op_enum mem_op_id;
    imm_op_enum immgen_op_id;
    
    logic [63:0] imm_id;
    logic [4:0] rs1_id, rs2_id, rd_id;

    
    wire [31:0] inst = IFID_reg.inst;
    assign rs1_id = inst[19:15];
    assign rs2_id = inst[24:20];
    assign rd_id  = inst[11:7];
    
    assign csr_addr_id = inst[31:20];

    CsrPack::ExceptPack except_id_default;
    assign except_id_default = '{default:'0};

   IDExceptExamine except_examine (
    .clk(clk),
    .rst(rst),
    .stall(mem_stall),
    .flush(rst||flush||stall||switch_mode||csr_raw_hazard),
    .pc_id(IFID_reg.pc),
    .priv(priv),
    .inst_id(IFID_reg.inst),
    .valid_id(IFID_reg.valid),
    .except_id(except_id_default),  
    .except_exe(except_info_id),
    .except_happen_id(except_happen_id)
);
    RegFile regfile (
        .clk(clk),
        .rst(rst),
        .we(MEMWB_reg.we_reg && MEMWB_reg.valid),
        .read_addr_1(rs1_id),
        .read_addr_2(rs2_id),
        .write_addr(MEMWB_reg.rd),
        .write_data(final_wdata_for_regfile),
        .read_data_1(read_data_1),
        .read_data_2(read_data_2)
    );
    
    
    Controller ctrl (
        .inst(inst),
        .we_reg(we_reg_id),
        .we_mem(we_mem_id),
        .re_mem(re_mem_id),
        .npc_sel(npc_sel_id),
        .immgen_op(immgen_op_id),
        .alu_op(alu_op_id),
        .cmp_op(cmp_op_id),
        .alu_asel(alu_asel_id),
        .alu_bsel(alu_bsel_id),
        .wb_sel(wb_sel_id),
        .mem_op(mem_op_id),
        .csr_ren(csr_ren_id),
        .csr_wen(csr_wen_id),
        .csr_bsel(csr_alu_bsel_id),
        .csr_cmd(csr_cmd_id),
        .is_csr_op(is_csr_op_id),
        .csr_ret(csr_ret_id)
    );

ExceptReg u_except_reg_ex3 (
    .clk(clk),
    .rst(rst),
    .stall(mem_stall), 
    .flush(switch_mode),     
    
    .except_i(except_info_id),  
    .except_o(except_info_ex3) 
);
ExceptReg u_except_reg_ex4 (
    .clk(clk),
    .rst(rst),
    .stall(1'b0),      
    .flush(rst||mem_stall||switch_mode),     

    .except_i(except_info_ex3),   
    .except_o(except_info_ex4)  
);
    // CSR side effects commit in WB, while ID still needs early reads for hazards.
CSRModule u_csr_module(
    .clk(clk),
    .rst(rst),

    
    .csr_we_wb( MEMWB_reg.we_csr),
    .csr_addr_wb(MEMWB_reg.csr_addr),
    .csr_val_wb(MEMWB_reg.alu_res),
    .csr_addr_id(csr_addr_id),
    .csr_val_id(csr_val_id),

    .pc_ret(MEMWB_reg.npc),
    .valid_wb(MEMWB_reg.valid),
    .time_int(time_int),
    .csr_ret(MEMWB_reg.csr_ret),
    .except_commit(except_info_ex4),

    
    .priv(priv),
    .switch_mode(switch_mode),
    .pc_csr(pc_csr),
    
    
    .cosim_interrupt(cosim_interrupt),
    .cosim_cause(cosim_cause),
    .cosim_csr_info(cosim_csr_info)
);
    assign cosim_switch_mode = switch_mode;
    always_comb begin
        case (immgen_op_id)
            I_IMM: imm_id = {{53{inst[31]}}, inst[30:25], inst[24:21], inst[20]};
            S_IMM: imm_id = {{53{inst[31]}}, inst[30:25], inst[11:8], inst[7]};
            B_IMM: imm_id = {{52{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            U_IMM: imm_id = {{33{inst[31]}}, inst[30:20], inst[19:12], 12'b0};
            UJ_IMM: imm_id = {{44{inst[31]}}, inst[19:12], inst[20], inst[30:25], inst[24:21], 1'b0};
            CSR_IMM: imm_id = {{59{1'b0}}, inst[19:15]};
            default: imm_id = 64'b0;
        endcase
    end
    // Forward EX/MEM/WB results to resolve common RAW hazards.
    logic [63:0] id_ex_rs1_data; 
    logic [63:0] id_ex_rs2_data; 

    logic [63:0] fwd_data_ex_alu_res; 
    logic [63:0] fwd_data_mem_alu_res; 
    logic [63:0] fwd_data_mem_mem_read; 
    logic [63:0] fwd_data_mem_pc_plus_4; 

    assign fwd_data_ex_alu_res = EXEMEM_reg.alu_res;
    assign fwd_data_mem_alu_res = MEMWB_reg.alu_res;
    assign fwd_data_mem_mem_read = MEMWB_reg.data_trunc;
    assign fwd_data_mem_pc_plus_4 = MEMWB_reg.pc_4;

    
    always_comb begin
        id_ex_rs1_data = read_data_1; 

        if (IDEXE_reg.valid && IDEXE_reg.we_reg && (IDEXE_reg.rd != 0) && (IDEXE_reg.rd == rs1_id)) begin
            id_ex_rs1_data = alu_res; 
        end

        else if (EXEMEM_reg.valid && EXEMEM_reg.we_reg && (EXEMEM_reg.rd != 5'h0) && (EXEMEM_reg.rd == rs1_id)) begin
            id_ex_rs1_data = fwd_data_ex_alu_res;
        end

        else if (MEMWB_reg.valid && MEMWB_reg.we_reg && (MEMWB_reg.rd != 5'h0) && (MEMWB_reg.rd == rs1_id)) begin
            case (MEMWB_reg.wb_sel)
                WB_SEL_ALU: id_ex_rs1_data = fwd_data_mem_alu_res;
                WB_SEL_MEM: id_ex_rs1_data = fwd_data_mem_mem_read;
                WB_SEL_PC: id_ex_rs1_data = fwd_data_mem_pc_plus_4;
                default: ; 
            endcase
        end
    end
    
    always_comb begin
        id_ex_rs2_data = read_data_2; 

        if (IDEXE_reg.valid && IDEXE_reg.we_reg && (IDEXE_reg.rd != 0) && (IDEXE_reg.rd == rs2_id)) begin
            id_ex_rs2_data = alu_res; 
        end

        else if (EXEMEM_reg.valid && EXEMEM_reg.we_reg && (EXEMEM_reg.rd != 5'h0) && (EXEMEM_reg.rd == rs2_id)) begin
            id_ex_rs2_data = fwd_data_ex_alu_res;
        end

        else if (MEMWB_reg.valid && MEMWB_reg.we_reg && (MEMWB_reg.rd != 5'h0) && (MEMWB_reg.rd == rs2_id)) begin
            case (MEMWB_reg.wb_sel)
                WB_SEL_ALU: id_ex_rs2_data = fwd_data_mem_alu_res;
                WB_SEL_MEM: id_ex_rs2_data = fwd_data_mem_mem_read;
                WB_SEL_PC: id_ex_rs2_data = fwd_data_mem_pc_plus_4;
                default: ; 
            endcase
        end
      
       
    end


    

wire csr_raw_hazard =MEMWB_reg.valid && MEMWB_reg.we_csr && csr_ren_id && (MEMWB_reg.csr_addr == csr_addr_id);

    // Stall on load-use hazards, IF wait states, and CSR RAW hazards.
    always_comb begin
        stall = 1'b0;
        if (EXEMEM_reg.valid && EXEMEM_reg.re_mem && EXEMEM_reg.we_reg && (EXEMEM_reg.rd != 5'h0)) begin
        
            if ( (EXEMEM_reg.rd == rs1_id) || (EXEMEM_reg.rd == rs2_id) ) begin
                stall = 1'b1;
            end
        end

        if (if_stall) begin
        stall = 1'b1;
    end
end

// Advance decoded instruction and control into EXE, clearing the stage on flush.
always_ff @(posedge clk or posedge rst) begin
        if (rst || flush ||stall |switch_mode||csr_raw_hazard) begin
            IDEXE_reg.valid <= 1'b0;
            IDEXE_reg.we_reg <= 1'b0;
            IDEXE_reg.we_mem <= 1'b0;
            IDEXE_reg.re_mem <= 1'b0;
            IDEXE_reg.npc_sel <= 1'b0;
            IDEXE_reg.imm <= 64'h0;
            IDEXE_reg.alu_op <= ALU_ADD;
            IDEXE_reg.cmp_op <= CMP_NO;
            IDEXE_reg.alu_a_sel <= ASEL0;
            IDEXE_reg.alu_b_sel <= BSEL0;
            IDEXE_reg.csr_alu_bsel <= BSEL_CSR0;
            IDEXE_reg.reg_data_1 <= 64'h0;
            IDEXE_reg.reg_data_2 <= 64'h0;
            IDEXE_reg.wb_sel <= WB_SEL0;
            IDEXE_reg.mem_op <= MEM_NO;
            IDEXE_reg.rd <= 5'h0;
            IDEXE_reg.rs1 <= 5'h0;
            IDEXE_reg.rs2 <= 5'h0;
            IDEXE_reg.pc <= 64'h0;
            IDEXE_reg.pc_4 <= 64'h0;
            IDEXE_reg.inst <= 32'h0;
            
            IDEXE_reg.we_csr      <=  1'b0;
            IDEXE_reg.csr_alu_op  <=  CsrPack::CSR_ALU_ADD;
            IDEXE_reg.csr_addr    <=  12'b0;
            IDEXE_reg.csr_val     <=  64'b0;
            IDEXE_reg.csr_ret     <=  2'b0;
        end  else if(mem_stall)begin
            IDEXE_reg <=IDEXE_reg;
        end else begin
            IDEXE_reg.valid <=IFID_reg.valid;
            IDEXE_reg.we_reg <= we_reg_id;
            IDEXE_reg.we_mem <= we_mem_id;
            IDEXE_reg.re_mem <= re_mem_id;
            IDEXE_reg.npc_sel <= npc_sel_id;
            IDEXE_reg.imm <= imm_id;
            IDEXE_reg.alu_op <= alu_op_id;
            IDEXE_reg.cmp_op <= cmp_op_id;
            IDEXE_reg.alu_a_sel <= alu_asel_id;
            IDEXE_reg.alu_b_sel <= alu_bsel_id;
            IDEXE_reg.csr_alu_bsel <= csr_alu_bsel_id;
            IDEXE_reg.reg_data_1 <= id_ex_rs1_data;
            IDEXE_reg.reg_data_2 <= id_ex_rs2_data;
            IDEXE_reg.wb_sel <= wb_sel_id;
            IDEXE_reg.mem_op <= mem_op_id;
            IDEXE_reg.rd <= rd_id;
            IDEXE_reg.rs1 <= rs1_id;
            IDEXE_reg.rs2 <= rs2_id;
            IDEXE_reg.pc <=IFID_reg.pc; 
            IDEXE_reg.pc_4 <= IFID_reg.pc_4;
            IDEXE_reg.inst <= inst;
            
            IDEXE_reg.we_csr      <= csr_wen_id;
            IDEXE_reg.csr_alu_op  <= csr_cmd_id;
            IDEXE_reg.csr_addr    <= csr_addr_id;
            IDEXE_reg.csr_val     <= csr_val_id;
            IDEXE_reg.csr_ret     <= csr_ret_id;
    end
end

// Prediction metadata travels with the instruction into EXE for validation.
always_ff @(posedge clk or posedge rst) begin
    if (rst || flush || stall || switch_mode || csr_raw_hazard) begin
        idexe_pred_taken  <= 1'b0;
        idexe_pred_target <= 64'h0;
    end else if (mem_stall) begin
        idexe_pred_taken  <= idexe_pred_taken;
        idexe_pred_target <= idexe_pred_target;
    end else begin
        idexe_pred_taken  <= ifid_pred_taken;
        idexe_pred_target <= ifid_pred_target;
    end
end

    // EXE resolves the real branch outcome and trains the BTB/BHT.
    logic [63:0] alu_a, alu_b, alu_res,csr_alu_res;
    logic cmp_res;
    
    always_comb begin
        case (IDEXE_reg.alu_a_sel)
            ASEL_REG: alu_a = IDEXE_reg.reg_data_1;
            ASEL_PC:  alu_a = IDEXE_reg.pc;
            default:  alu_a = 64'b0;
        endcase

        case (IDEXE_reg.alu_b_sel)
            BSEL_REG: alu_b = IDEXE_reg.reg_data_2;
            BSEL_IMM: alu_b = IDEXE_reg.imm;
            default:  alu_b = 64'b0;
        endcase
    end
    
    ALU alu (
        .a(alu_a),
        .b(alu_b),
        .alu_op(IDEXE_reg.alu_op),
        .res(alu_res)
    );

logic [63:0] csr_alu_op2;

always_comb begin
    unique case (IDEXE_reg.csr_alu_bsel)
        BSEL_CSRIMM: csr_alu_op2 = IDEXE_reg.imm;
        default:     csr_alu_op2 = IDEXE_reg.reg_data_1;
    endcase
end

    CSR_ALU u_csr_alu (
        .op1(IDEXE_reg.csr_val),       
        .op2(csr_alu_op2),   
        .op(IDEXE_reg.csr_alu_op),    
        .result(csr_alu_res)
    );


    
    Cmp cmp (
        .a(IDEXE_reg.reg_data_1),
        .b(IDEXE_reg.reg_data_2),
        .cmp_op(IDEXE_reg.cmp_op),
        .cmp_res(cmp_res)
    );

    // IF uses this instance for lookup; EXE reuses the same table for updates.
    BranchPrediction u_branch_prediction (
        .clk(clk),
        .rst(rst),
        .pc_if(pc),
        .jump_pred_if(jump_pred_if),
        .pc_target_if(pc_target_if),
        .pc_exe(IDEXE_reg.pc),
        .pc_target_exe(alu_res),
        .is_jump_exe(branch_taken_exe),
        .inst_is_jump_exe(pred_branch_exe)
    );

    // Only BRANCH instructions train the table in this implementation.
    assign branch_inst_exe = IDEXE_reg.valid && IDEXE_reg.npc_sel;
    assign pred_branch_exe = IDEXE_reg.valid && (IDEXE_reg.inst[6:0] == BRANCH_OPCODE);
    assign branch_taken_exe = branch_inst_exe && (cmp_res || (IDEXE_reg.cmp_op == CMP_NO));
    assign next_pc = branch_taken_exe ? alu_res : IDEXE_reg.pc_4;
    assign pc_redirect = next_pc;
    // A mispredict is either a wrong direction or a wrong target.
    assign mispredict_exe = branch_inst_exe &&
                            ((idexe_pred_taken != branch_taken_exe) ||
                             (branch_taken_exe && (idexe_pred_target != alu_res)));

    always_comb begin
        flush = mispredict_exe;
    end


    



    always_ff @(posedge clk or posedge rst) begin
        if (rst ||switch_mode) begin
            EXEMEM_reg.valid <= 1'b0;
            EXEMEM_reg.we_reg <= 1'b0;
            EXEMEM_reg.we_mem <= 1'b0;
            EXEMEM_reg.re_mem <= 1'b0;
            EXEMEM_reg.br_taken <= 1'b0;
            EXEMEM_reg.alu_res <= 64'h0;
            EXEMEM_reg.reg_data_1 <= 64'h0;
            EXEMEM_reg.reg_data_2 <= 64'h0;
            EXEMEM_reg.csr_alu_res <= 64'h0;
            EXEMEM_reg.mem_wdata <= 64'h0;
            EXEMEM_reg.wb_sel <= WB_SEL0;
            EXEMEM_reg.mem_op <= MEM_NO;
            EXEMEM_reg.rd <= 5'h0;
            EXEMEM_reg.rs1 <= 5'h0;
            EXEMEM_reg.rs2 <= 5'h0;
            EXEMEM_reg.pc <= 64'h0;
            EXEMEM_reg.pc_4 <= 64'h0;
            EXEMEM_reg.npc <= 64'h0;
            EXEMEM_reg.inst <= 32'h0;
            EXEMEM_reg.we_csr     <= 1'b0;
            EXEMEM_reg.csr_addr   <= 12'b0;
            EXEMEM_reg.csr_ret    <= 2'b0;
        end else if(mem_stall)begin
            EXEMEM_reg <=EXEMEM_reg;
           
        end else begin
            EXEMEM_reg.valid <= IDEXE_reg.valid;
            EXEMEM_reg.we_reg <= IDEXE_reg.we_reg;
            EXEMEM_reg.we_mem <= IDEXE_reg.we_mem;
            EXEMEM_reg.re_mem <= IDEXE_reg.re_mem;
            EXEMEM_reg.br_taken <= branch_taken_exe;
            
            EXEMEM_reg.alu_res <= IDEXE_reg.we_csr ? csr_alu_res : alu_res;
            EXEMEM_reg.reg_data_1 <= IDEXE_reg.reg_data_1;
            EXEMEM_reg.reg_data_2 <= IDEXE_reg.reg_data_2;
            EXEMEM_reg.csr_alu_res <= IDEXE_reg.csr_val;
            EXEMEM_reg.mem_wdata <= wdata_mem;
            EXEMEM_reg.wb_sel <= IDEXE_reg.wb_sel;
            EXEMEM_reg.mem_op <= IDEXE_reg.mem_op;
            EXEMEM_reg.rd <= IDEXE_reg.rd;
            EXEMEM_reg.rs1 <= IDEXE_reg.rs1;
            EXEMEM_reg.rs2 <= IDEXE_reg.rs2;
            EXEMEM_reg.pc <= IDEXE_reg.pc;
            EXEMEM_reg.pc_4 <= IDEXE_reg.pc_4;
            EXEMEM_reg.npc <= next_pc;
            EXEMEM_reg.inst <= IDEXE_reg.inst;
            
            EXEMEM_reg.we_csr     <= IDEXE_reg.we_csr;
            EXEMEM_reg.csr_addr   <= IDEXE_reg.csr_addr;
            EXEMEM_reg.csr_ret    <= IDEXE_reg.csr_ret; 
        end
    end


    logic [63:0] wdata_mem;
    logic [7:0]  wmask_mem;
    
    DataPkg datapkg (
        .mem_op(EXEMEM_reg.mem_op),
        .reg_data(EXEMEM_reg.reg_data_2),
        .dmem_waddr(EXEMEM_reg.alu_res),
        .dmem_wdata(wdata_mem)
    );

    MaskGen maskgen (
        .mem_op(EXEMEM_reg.mem_op),
        .dmem_waddr(EXEMEM_reg.alu_res),
        .dmem_wmask(wmask_mem)
    );
    assign dmem_ift.r_request_bits.raddr  = EXEMEM_reg.alu_res;

    assign dmem_ift.r_request_valid       = (if_state==IF_MEM1)&& EXEMEM_reg.re_mem && EXEMEM_reg.valid;
    assign dmem_ift.w_request_valid       = (if_state==IF_MEM1) && EXEMEM_reg.we_mem && EXEMEM_reg.valid;

    assign dmem_ift.w_request_bits.waddr  = EXEMEM_reg.alu_res;
    assign dmem_ift.w_request_bits.wdata  = wdata_mem;
    assign dmem_ift.w_request_bits.wmask  = wmask_mem;

    assign dmem_ift.r_reply_ready         = (if_state==IF_MEM2);
    assign dmem_ift.w_reply_ready         = (if_state==IF_MEM2);

    logic [63:0] mem_rdata_trunc;
    
    DataTrunc trunc (
        .dmem_rdata(dmem_ift.r_reply_bits.rdata),
        .mem_op(EXEMEM_reg.mem_op),
        .dmem_raddr(EXEMEM_reg.alu_res),
        .read_data(mem_rdata_trunc)
    );


    
    always_ff @(posedge clk or posedge rst) begin
        if (rst||mem_stall |switch_mode) begin
            MEMWB_reg.valid <= 1'b0;
            MEMWB_reg.we_reg <= 1'b0;
            MEMWB_reg.re_mem <= 1'b0;
            MEMWB_reg.br_taken <= 1'b0;
            MEMWB_reg.mem_we <= 64'h0;
            MEMWB_reg.alu_res <= 64'h0;
            MEMWB_reg.data_trunc <= 64'h0;
            MEMWB_reg.read_data_1 <= 64'h0;
            MEMWB_reg.read_data_2 <= 64'h0;
            MEMWB_reg.csr_alu_res <= 64'h0;
            MEMWB_reg.mem_wdata <= 64'h0;
            MEMWB_reg.mem_rdata <= 64'h0;
            MEMWB_reg.mem_addr <= 64'h0;
            MEMWB_reg.wb_sel <= WB_SEL0;
            MEMWB_reg.rd <= 5'h0;
            MEMWB_reg.rs1 <= 5'h0;
            MEMWB_reg.rs2 <= 5'h0;
            MEMWB_reg.pc <= 64'h0;
            MEMWB_reg.pc_4 <= 64'h0;
            MEMWB_reg.npc <= 64'h0;
            MEMWB_reg.inst <= 32'h0;
            MEMWB_reg.we_csr    <= 1'b0;
            MEMWB_reg.csr_addr  <= 12'b0;
            MEMWB_reg.csr_ret   <= 2'b0;
        end 
        else begin
            MEMWB_reg.valid <= EXEMEM_reg.valid;
            MEMWB_reg.we_reg <= EXEMEM_reg.we_reg;
            MEMWB_reg.re_mem <= EXEMEM_reg.re_mem;
            MEMWB_reg.br_taken <= EXEMEM_reg.br_taken;
            MEMWB_reg.mem_we <= {63'b0, EXEMEM_reg.we_mem};
            MEMWB_reg.alu_res <= EXEMEM_reg.alu_res;
            MEMWB_reg.data_trunc <= mem_rdata_trunc;
            MEMWB_reg.read_data_1 <= EXEMEM_reg.reg_data_1;
            MEMWB_reg.read_data_2 <= EXEMEM_reg.reg_data_2;
            MEMWB_reg.csr_alu_res <= EXEMEM_reg.csr_alu_res;
            MEMWB_reg.mem_wdata <= EXEMEM_reg.mem_wdata;
            MEMWB_reg.mem_rdata <= dmem_ift.r_reply_bits.rdata;
            MEMWB_reg.mem_addr <= EXEMEM_reg.alu_res;
            MEMWB_reg.wb_sel <= EXEMEM_reg.wb_sel;
            MEMWB_reg.rd <= EXEMEM_reg.rd;
            MEMWB_reg.rs1 <= EXEMEM_reg.rs1;
            MEMWB_reg.rs2 <= EXEMEM_reg.rs2;
            MEMWB_reg.pc <= EXEMEM_reg.pc;
            MEMWB_reg.pc_4 <= EXEMEM_reg.pc_4;
            MEMWB_reg.npc <= EXEMEM_reg.npc;
            MEMWB_reg.inst <= EXEMEM_reg.inst;
            
            MEMWB_reg.we_csr    <= EXEMEM_reg.we_csr;
            MEMWB_reg.csr_addr  <= EXEMEM_reg.csr_addr;
            MEMWB_reg.csr_ret   <= EXEMEM_reg.csr_ret;
        end
    end

    
    logic [63:0] wb_data;
    
    always_comb begin
        case (MEMWB_reg.wb_sel)
            WB_SEL_ALU: wb_data = MEMWB_reg.alu_res;
            WB_SEL_MEM: wb_data = MEMWB_reg.data_trunc;
            WB_SEL_PC:  wb_data = MEMWB_reg.pc + 4;
            default:    wb_data = 64'b0;
        endcase
    end

    always_comb begin
        final_wdata_for_regfile = wb_data; 

        if (MEMWB_reg.we_csr) begin
            final_wdata_for_regfile = MEMWB_reg.csr_alu_res;
        end
    end


    // Cosim observes the retired architectural state.
    assign cosim_valid = MEMWB_reg.valid;
    assign cosim_core_info.pc        = MEMWB_reg.pc;
    assign cosim_core_info.inst      = {32'b0, MEMWB_reg.inst};
    assign cosim_core_info.rs1_id    = {59'b0, MEMWB_reg.rs1};
    assign cosim_core_info.rs1_data  = MEMWB_reg.read_data_1;
    assign cosim_core_info.rs2_id    = {59'b0, MEMWB_reg.rs2};
    assign cosim_core_info.rs2_data  = MEMWB_reg.read_data_2;
    assign cosim_core_info.alu       = MEMWB_reg.alu_res;
    assign cosim_core_info.mem_addr  = MEMWB_reg.mem_addr;
    assign cosim_core_info.mem_we    = MEMWB_reg.mem_we;
    assign cosim_core_info.mem_wdata = MEMWB_reg.mem_wdata;
    assign cosim_core_info.mem_rdata = MEMWB_reg.mem_rdata;
    assign cosim_core_info.rd_we     = {63'b0, MEMWB_reg.we_reg};
    assign cosim_core_info.rd_id     = {59'b0, MEMWB_reg.rd};
    assign cosim_core_info.rd_data   = final_wdata_for_regfile;
    assign cosim_core_info.br_taken  = {63'b0, MEMWB_reg.br_taken};
    assign cosim_core_info.npc       = MEMWB_reg.npc;

endmodule

