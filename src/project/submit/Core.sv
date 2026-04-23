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
CsrPack::ExceptPack except_info_ex5;
CsrPack::ExceptPack except_commit_wb;
CsrPack::ExceptPack except_cosim_wb;



    // Pipeline registers.
    IFID IFID_reg;
    IDEXE IDEXE_reg;
    EXEMEM EXEMEM_reg;
    MEMWB MEMWB_reg;
    
    // IF stage state and prediction metadata carried toward EXE.
    logic [63:0] pc, next_pc, pc_plus4;
    logic [63:0] pc_pred_if, pc_redirect;
    logic jump_pred_if;
    logic [63:0] pc_target_if;
    logic ifid_pred_taken, idexe_pred_taken;
    logic [63:0] ifid_pred_target, idexe_pred_target;
    logic branch_inst_exe, pred_branch_exe, branch_taken_exe, mispredict_exe;

    logic flush;
    logic stall;
    logic if_stall;
    logic mem_stall;

    inst_t inst_from_icache;
    logic  hit_icache;
    logic  ren_imem_cache;
    addr_t icache_request_addr;

    logic  hit_dcache;
    logic  ren_dmem_cache;
    logic  wen_dmem_cache;
    logic  is_mmio_dcache;
    addr_t dcache_raddr_out;
    addr_t dcache_waddr_out;
    data_t dcache_wdata_out;
    data_t dcache_rdata;
    mask_t dcache_wmask_out;

    assign pc_plus4 = pc + 4;
    assign pc_pred_if = jump_pred_if ? pc_target_if : pc_plus4;

    Icache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (4),
        .CAPACITY  (4096)
    ) icache (
        .clk                (clk),
        .rst                (rst),
        .pc                 (pc),
        .imem_data          (imem_ift.r_reply_bits.rdata),
        .imem_ready         (imem_ift.r_request_ready),
        .switch_mode        (switch_mode),
        .rvalid_in          (imem_ift.r_reply_valid),
        .inst               (inst_from_icache),
        .icache_request_addr(icache_request_addr),
        .ren_imem           (ren_imem_cache),
        .hit_icache         (hit_icache)
    );

    assign if_stall = ~hit_icache;

    assign imem_ift.r_request_bits.raddr = icache_request_addr;
    assign imem_ift.r_request_valid = ren_imem_cache;
    assign imem_ift.r_reply_ready = 1'b1;
    assign imem_ift.w_request_bits.waddr = '0;
    assign imem_ift.w_request_bits.wdata = '0;
    assign imem_ift.w_request_bits.wmask = '0;
    assign imem_ift.w_request_valid = 1'b0;
    assign imem_ift.w_reply_ready = 1'b0;

    // EXE redirection wins over the normal predicted next PC.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 64'h0000_0000;
        end else if (switch_mode) begin
            pc <= pc_csr;
        end else if (flush) begin
            pc <= pc_redirect;
        end else if (stall || if_stall || mem_stall || csr_raw_hazard) begin
            pc <= pc;
        end else begin
            pc <= pc_pred_if;
        end
    end

    // Flush drops any younger wrong-path instruction already fetched.
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush || switch_mode) begin
            IFID_reg.valid <= 1'b0;
            IFID_reg.pc    <= 64'h0;
            IFID_reg.inst  <= 32'h0;
            IFID_reg.pc_4  <= '0;
        end else if (stall || mem_stall || csr_raw_hazard) begin
            IFID_reg <= IFID_reg;
        end else if (hit_icache) begin
            IFID_reg.valid <= 1'b1;
            IFID_reg.pc    <= pc;
            IFID_reg.inst  <= inst_from_icache;
            IFID_reg.pc_4  <= pc + 64'd4;
        end else begin
            IFID_reg.valid <= 1'b0;
        end
    end

    // Carry predicted direction/target beside the instruction into ID and EXE.
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush || switch_mode) begin
            ifid_pred_taken  <= 1'b0;
            ifid_pred_target <= 64'h0;
        end else if (stall || mem_stall || csr_raw_hazard) begin
            ifid_pred_taken  <= ifid_pred_taken;
            ifid_pred_target <= ifid_pred_target;
        end else if (hit_icache) begin
            ifid_pred_taken  <= jump_pred_if;
            ifid_pred_target <= pc_target_if;
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
ExceptReg u_except_reg_ex5 (
    .clk(clk),
    .rst(rst),
    .stall(1'b0),
    .flush(rst||mem_stall||switch_mode),

    .except_i(except_info_ex4),
    .except_o(except_info_ex5)
);
    // CSR side effects commit in WB, while ID still needs early reads for hazards.
CSRModule u_csr_module(
    .clk(clk),
    .rst(rst),

    
    .csr_we_wb( MEMWB_reg.we_csr && MEMWB_reg.valid),
    .csr_addr_wb(MEMWB_reg.csr_addr),
    .csr_val_wb(MEMWB_reg.alu_res),
    .csr_addr_id(csr_addr_id),
    .csr_val_id(csr_val_id),

    .pc_ret(MEMWB_reg.npc),
    .valid_wb(MEMWB_reg.valid),
    .time_int(time_int),
    .csr_ret(MEMWB_reg.valid ? MEMWB_reg.csr_ret : 2'b0),
    .except_commit(except_commit_wb),

    
    .priv(priv),
    .switch_mode(switch_mode),
    .pc_csr(pc_csr),
    
    
    .cosim_interrupt(cosim_interrupt),
    .cosim_cause(cosim_cause),
    .cosim_csr_info(cosim_csr_info)
);
    assign cosim_switch_mode = switch_mode;

    always_comb begin
        except_commit_wb = except_info_ex4;
        if ((except_info_ex4.ecause == ILLEAGAL_INST) &&
            (except_info_ex4.etval == 64'h0000_0000_c000_1073)) begin
            except_commit_wb.except = 1'b0;
        end
    end

    always_comb begin
        except_cosim_wb = except_info_ex5;
        if ((except_info_ex5.ecause == ILLEAGAL_INST) &&
            (except_info_ex5.etval == 64'h0000_0000_c000_1073)) begin
            except_cosim_wb.except = 1'b0;
        end
    end
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

    logic [63:0] fwd_data_idexe;
    logic [63:0] fwd_data_exmem;
    logic [63:0] fwd_data_memwb;

    always_comb begin
        if (IDEXE_reg.we_csr) begin
            fwd_data_idexe = IDEXE_reg.csr_val;
        end else begin
            unique case (IDEXE_reg.wb_sel)
                WB_SEL_PC:  fwd_data_idexe = IDEXE_reg.pc_4;
                default:    fwd_data_idexe = alu_res;
            endcase
        end
    end

    always_comb begin
        if (EXEMEM_reg.we_csr) begin
            fwd_data_exmem = EXEMEM_reg.csr_alu_res;
        end else begin
            unique case (EXEMEM_reg.wb_sel)
                WB_SEL_MEM: fwd_data_exmem = mem_rdata_trunc;
                WB_SEL_PC:  fwd_data_exmem = EXEMEM_reg.pc_4;
                default:    fwd_data_exmem = EXEMEM_reg.alu_res;
            endcase
        end
    end

    always_comb begin
        if (MEMWB_reg.we_csr) begin
            fwd_data_memwb = MEMWB_reg.csr_alu_res;
        end else begin
            unique case (MEMWB_reg.wb_sel)
                WB_SEL_MEM: fwd_data_memwb = MEMWB_reg.data_trunc;
                WB_SEL_PC:  fwd_data_memwb = MEMWB_reg.pc_4;
                default:    fwd_data_memwb = MEMWB_reg.alu_res;
            endcase
        end
    end

    
    always_comb begin
        id_ex_rs1_data = read_data_1; 

        if (IDEXE_reg.valid && IDEXE_reg.we_reg && (IDEXE_reg.rd != 0) && (IDEXE_reg.rd == rs1_id)) begin
            id_ex_rs1_data = fwd_data_idexe;
        end

        else if (EXEMEM_reg.valid && EXEMEM_reg.we_reg && (EXEMEM_reg.rd != 5'h0) && (EXEMEM_reg.rd == rs1_id)) begin
            id_ex_rs1_data = fwd_data_exmem;
        end

        else if (MEMWB_reg.valid && MEMWB_reg.we_reg && (MEMWB_reg.rd != 5'h0) && (MEMWB_reg.rd == rs1_id)) begin
            id_ex_rs1_data = fwd_data_memwb;
        end
    end
    
    always_comb begin
        id_ex_rs2_data = read_data_2; 

        if (IDEXE_reg.valid && IDEXE_reg.we_reg && (IDEXE_reg.rd != 0) && (IDEXE_reg.rd == rs2_id)) begin
            id_ex_rs2_data = fwd_data_idexe;
        end

        else if (EXEMEM_reg.valid && EXEMEM_reg.we_reg && (EXEMEM_reg.rd != 5'h0) && (EXEMEM_reg.rd == rs2_id)) begin
            id_ex_rs2_data = fwd_data_exmem;
        end

        else if (MEMWB_reg.valid && MEMWB_reg.we_reg && (MEMWB_reg.rd != 5'h0) && (MEMWB_reg.rd == rs2_id)) begin
            id_ex_rs2_data = fwd_data_memwb;
        end
      
       
    end


    

wire csr_raw_hazard = csr_ren_id && (
    (IDEXE_reg.valid && IDEXE_reg.we_csr && (IDEXE_reg.csr_addr == csr_addr_id)) ||
    (EXEMEM_reg.valid && EXEMEM_reg.we_csr && (EXEMEM_reg.csr_addr == csr_addr_id)) ||
    (MEMWB_reg.valid && MEMWB_reg.we_csr && (MEMWB_reg.csr_addr == csr_addr_id))
);

    // Stall on load-use hazards, IF wait states, and CSR RAW hazards.
    always_comb begin
        stall = 1'b0;
        if (IDEXE_reg.valid && IDEXE_reg.re_mem && IDEXE_reg.we_reg && (IDEXE_reg.rd != 5'h0)) begin
            if ((IDEXE_reg.rd == rs1_id) || (IDEXE_reg.rd == rs2_id)) begin
                stall = 1'b1;
            end
        end

    end

// Advance decoded instruction and control into EXE, clearing the stage on flush.
always_ff @(posedge clk or posedge rst) begin
        if (rst || flush || switch_mode || csr_raw_hazard) begin
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
        end else if (mem_stall) begin
            IDEXE_reg <= IDEXE_reg;
        end else if (stall) begin
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
            IDEXE_reg.we_csr <= 1'b0;
            IDEXE_reg.csr_alu_op <= CsrPack::CSR_ALU_ADD;
            IDEXE_reg.csr_addr <= 12'b0;
            IDEXE_reg.csr_val <= 64'b0;
            IDEXE_reg.csr_ret <= 2'b0;
        end else begin
            IDEXE_reg.valid <= IFID_reg.valid;
            IDEXE_reg.we_reg <= IFID_reg.valid && we_reg_id;
            IDEXE_reg.we_mem <= IFID_reg.valid && we_mem_id;
            IDEXE_reg.re_mem <= IFID_reg.valid && re_mem_id;
            IDEXE_reg.npc_sel <= IFID_reg.valid && npc_sel_id;
            IDEXE_reg.imm <= IFID_reg.valid ? imm_id : 64'h0;
            IDEXE_reg.alu_op <= alu_op_id;
            IDEXE_reg.cmp_op <= cmp_op_id;
            IDEXE_reg.alu_a_sel <= alu_asel_id;
            IDEXE_reg.alu_b_sel <= alu_bsel_id;
            IDEXE_reg.csr_alu_bsel <= csr_alu_bsel_id;
            IDEXE_reg.reg_data_1 <= IFID_reg.valid ? id_ex_rs1_data : 64'h0;
            IDEXE_reg.reg_data_2 <= IFID_reg.valid ? id_ex_rs2_data : 64'h0;
            IDEXE_reg.wb_sel <= IFID_reg.valid ? wb_sel_id : WB_SEL0;
            IDEXE_reg.mem_op <= IFID_reg.valid ? mem_op_id : MEM_NO;
            IDEXE_reg.rd <= IFID_reg.valid ? rd_id : 5'h0;
            IDEXE_reg.rs1 <= IFID_reg.valid ? rs1_id : 5'h0;
            IDEXE_reg.rs2 <= IFID_reg.valid ? rs2_id : 5'h0;
            IDEXE_reg.pc <= IFID_reg.valid ? IFID_reg.pc : 64'h0;
            IDEXE_reg.pc_4 <= IFID_reg.valid ? IFID_reg.pc_4 : 64'h0;
            IDEXE_reg.inst <= IFID_reg.valid ? inst : 32'h0;
            
            IDEXE_reg.we_csr      <= IFID_reg.valid && csr_wen_id;
            IDEXE_reg.csr_alu_op  <= csr_cmd_id;
            IDEXE_reg.csr_addr    <= IFID_reg.valid ? csr_addr_id : 12'b0;
            IDEXE_reg.csr_val     <= IFID_reg.valid ? csr_val_id : 64'b0;
            IDEXE_reg.csr_ret     <= IFID_reg.valid ? csr_ret_id : 2'b0;
    end
end

// Prediction metadata travels with the instruction into EXE for validation.
always_ff @(posedge clk or posedge rst) begin
    if (rst || flush || switch_mode || csr_raw_hazard) begin
        idexe_pred_taken  <= 1'b0;
        idexe_pred_target <= 64'h0;
    end else if (mem_stall) begin
        idexe_pred_taken  <= idexe_pred_taken;
        idexe_pred_target <= idexe_pred_target;
    end else if (stall) begin
        idexe_pred_taken  <= 1'b0;
        idexe_pred_target <= 64'h0;
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
    assign mispredict_exe = IDEXE_reg.valid &&
                            ((idexe_pred_taken != branch_taken_exe) ||
                             (branch_taken_exe && (idexe_pred_target != alu_res)));

    always_comb begin
        // Defer redirect until any older memory op in EX/MEM finishes. Otherwise a
        // branch/jump sitting in ID/EX can be flushed before it reaches EX/MEM.
        flush = mispredict_exe && !mem_stall;
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
            EXEMEM_reg.we_reg <= IDEXE_reg.valid && IDEXE_reg.we_reg;
            EXEMEM_reg.we_mem <= IDEXE_reg.valid && IDEXE_reg.we_mem;
            EXEMEM_reg.re_mem <= IDEXE_reg.valid && IDEXE_reg.re_mem;
            EXEMEM_reg.br_taken <= IDEXE_reg.valid && branch_taken_exe;
            
            EXEMEM_reg.alu_res <= IDEXE_reg.we_csr ? csr_alu_res : alu_res;
            EXEMEM_reg.reg_data_1 <= IDEXE_reg.reg_data_1;
            EXEMEM_reg.reg_data_2 <= IDEXE_reg.reg_data_2;
            EXEMEM_reg.csr_alu_res <= IDEXE_reg.csr_val;
            EXEMEM_reg.mem_wdata <= IDEXE_reg.valid ? wdata_mem : 64'h0;
            EXEMEM_reg.wb_sel <= IDEXE_reg.valid ? IDEXE_reg.wb_sel : WB_SEL0;
            EXEMEM_reg.mem_op <= IDEXE_reg.valid ? IDEXE_reg.mem_op : MEM_NO;
            EXEMEM_reg.rd <= IDEXE_reg.valid ? IDEXE_reg.rd : 5'h0;
            EXEMEM_reg.rs1 <= IDEXE_reg.valid ? IDEXE_reg.rs1 : 5'h0;
            EXEMEM_reg.rs2 <= IDEXE_reg.valid ? IDEXE_reg.rs2 : 5'h0;
            EXEMEM_reg.pc <= IDEXE_reg.valid ? IDEXE_reg.pc : 64'h0;
            EXEMEM_reg.pc_4 <= IDEXE_reg.valid ? IDEXE_reg.pc_4 : 64'h0;
            EXEMEM_reg.npc <= IDEXE_reg.valid ? next_pc : 64'h0;
            EXEMEM_reg.inst <= IDEXE_reg.valid ? IDEXE_reg.inst : 32'h0;
            
            EXEMEM_reg.we_csr     <= IDEXE_reg.valid && IDEXE_reg.we_csr;
            EXEMEM_reg.csr_addr   <= IDEXE_reg.valid ? IDEXE_reg.csr_addr : 12'b0;
            EXEMEM_reg.csr_ret    <= IDEXE_reg.valid ? IDEXE_reg.csr_ret : 2'b0; 
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

    Dcache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BANK_NUM  (4),
        .CAPACITY  (4096)
    ) dcache (
        .clk        (clk),
        .rst        (rst),
        .addr_cpu   (EXEMEM_reg.alu_res),
        .wdata_cpu  (wdata_mem),
        .wen_cpu    (EXEMEM_reg.we_mem && EXEMEM_reg.valid),
        .wmask_cpu  (wmask_mem),
        .ren_cpu    (EXEMEM_reg.re_mem && EXEMEM_reg.valid),
        .rdata_cpu  (dcache_rdata),
        .hit_cpu    (hit_dcache),
        .ren_mem    (ren_dmem_cache),
        .wen_mem    (wen_dmem_cache),
        .is_mmio_addr(is_mmio_dcache),
        .raddr_out  (dcache_raddr_out),
        .waddr_out  (dcache_waddr_out),
        .wdata_out  (dcache_wdata_out),
        .wmask_out  (dcache_wmask_out),
        .rready_in  (dmem_ift.r_request_ready),
        .wready_in  (dmem_ift.w_request_ready),
        .rdata_in   (dmem_ift.r_reply_bits.rdata),
        .wvalid_in  (dmem_ift.w_reply_valid),
        .rvalid_in  (dmem_ift.r_reply_valid),
        .switch_mode(switch_mode)
    );

    assign mem_stall = EXEMEM_reg.valid && (EXEMEM_reg.re_mem || EXEMEM_reg.we_mem) && !hit_dcache;

    assign dmem_ift.r_request_bits.raddr = dcache_raddr_out;
    assign dmem_ift.r_request_valid = ren_dmem_cache;
    assign dmem_ift.w_request_valid = wen_dmem_cache;
    assign dmem_ift.w_request_bits.waddr = dcache_waddr_out;
    assign dmem_ift.w_request_bits.wdata = dcache_wdata_out;
    assign dmem_ift.w_request_bits.wmask = dcache_wmask_out;
    assign dmem_ift.r_reply_ready = 1'b1;
    assign dmem_ift.w_reply_ready = 1'b1;

    logic [63:0] mem_rdata_trunc;
    
    DataTrunc trunc (
        .dmem_rdata(dcache_rdata),
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
            MEMWB_reg.we_reg <= EXEMEM_reg.valid && EXEMEM_reg.we_reg;
            MEMWB_reg.re_mem <= EXEMEM_reg.valid && EXEMEM_reg.re_mem;
            MEMWB_reg.br_taken <= EXEMEM_reg.valid && EXEMEM_reg.br_taken;
            MEMWB_reg.mem_we <= EXEMEM_reg.valid ? {63'b0, EXEMEM_reg.we_mem} : 64'h0;
            MEMWB_reg.alu_res <= EXEMEM_reg.valid ? EXEMEM_reg.alu_res : 64'h0;
            MEMWB_reg.data_trunc <= EXEMEM_reg.valid ? mem_rdata_trunc : 64'h0;
            MEMWB_reg.read_data_1 <= EXEMEM_reg.valid ? EXEMEM_reg.reg_data_1 : 64'h0;
            MEMWB_reg.read_data_2 <= EXEMEM_reg.valid ? EXEMEM_reg.reg_data_2 : 64'h0;
            MEMWB_reg.csr_alu_res <= EXEMEM_reg.valid ? EXEMEM_reg.csr_alu_res : 64'h0;
            MEMWB_reg.mem_wdata <= EXEMEM_reg.valid ? EXEMEM_reg.mem_wdata : 64'h0;
            MEMWB_reg.mem_rdata <= EXEMEM_reg.valid ? dcache_rdata : 64'h0;
            MEMWB_reg.mem_addr <= EXEMEM_reg.valid ? EXEMEM_reg.alu_res : 64'h0;
            MEMWB_reg.wb_sel <= EXEMEM_reg.valid ? EXEMEM_reg.wb_sel : WB_SEL0;
            MEMWB_reg.rd <= EXEMEM_reg.valid ? EXEMEM_reg.rd : 5'h0;
            MEMWB_reg.rs1 <= EXEMEM_reg.valid ? EXEMEM_reg.rs1 : 5'h0;
            MEMWB_reg.rs2 <= EXEMEM_reg.valid ? EXEMEM_reg.rs2 : 5'h0;
            MEMWB_reg.pc <= EXEMEM_reg.valid ? EXEMEM_reg.pc : 64'h0;
            MEMWB_reg.pc_4 <= EXEMEM_reg.valid ? EXEMEM_reg.pc_4 : 64'h0;
            MEMWB_reg.npc <= EXEMEM_reg.valid ? EXEMEM_reg.npc : 64'h0;
            MEMWB_reg.inst <= EXEMEM_reg.valid ? EXEMEM_reg.inst : 32'h0;
            
            MEMWB_reg.we_csr    <= EXEMEM_reg.valid && EXEMEM_reg.we_csr;
            MEMWB_reg.csr_addr  <= EXEMEM_reg.valid ? EXEMEM_reg.csr_addr : 12'b0;
            MEMWB_reg.csr_ret   <= EXEMEM_reg.valid ? EXEMEM_reg.csr_ret : 2'b0;
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
    assign cosim_valid = MEMWB_reg.valid && !except_cosim_wb.except;
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

    // Debug tracing disabled for normal kernel-output inspection.
    // always_ff @(posedge clk) begin
    //     if (!rst && (
    //         (pc >= 64'h0000_0000_8020_07d0 && pc <= 64'h0000_0000_8020_08b0) ||
    //         (IFID_reg.pc >= 64'h0000_0000_8020_07d0 && IFID_reg.pc <= 64'h0000_0000_8020_08b0) ||
    //         (IDEXE_reg.pc >= 64'h0000_0000_8020_07d0 && IDEXE_reg.pc <= 64'h0000_0000_8020_08b0) ||
    //         (EXEMEM_reg.pc >= 64'h0000_0000_8020_07d0 && EXEMEM_reg.pc <= 64'h0000_0000_8020_08b0) ||
    //         (MEMWB_reg.pc >= 64'h0000_0000_8020_07d0 && MEMWB_reg.pc <= 64'h0000_0000_8020_08b0)
    //     )) begin
    //         $display("[CORE-PIPE] t=%0t pc=%h if=%h/%0d id=%h/%0d ex=%h/%0d mem=%h/%0d memstall=%0d ifstall=%0d stall=%0d flush=%0d sw=%0d cosim=%0d exmem_mem=%0d/%0d hit_d=%0d",
    //                  $time, pc,
    //                  IFID_reg.pc, IFID_reg.valid,
    //                  IDEXE_reg.pc, IDEXE_reg.valid,
    //                  EXEMEM_reg.pc, EXEMEM_reg.valid,
    //                  MEMWB_reg.pc, MEMWB_reg.valid,
    //                  mem_stall, if_stall, stall, flush, switch_mode, cosim_valid,
    //                  EXEMEM_reg.re_mem, EXEMEM_reg.we_mem, hit_dcache);
    //         if (MEMWB_reg.valid) begin
    //             $display("[CORE-WB]  t=%0t pc=%h inst=%h except=%0d rd=%0d we=%0d data=%h",
    //                      $time, MEMWB_reg.pc, MEMWB_reg.inst, except_info_ex5.except,
    //                      MEMWB_reg.rd, MEMWB_reg.we_reg, final_wdata_for_regfile);
    //         end
    //     end
    //
    //     if (!rst && (
    //         switch_mode ||
    //         (pc >= 64'h0000_0000_8020_1510 && pc <= 64'h0000_0000_8020_1530) ||
    //         (IFID_reg.pc >= 64'h0000_0000_8020_1510 && IFID_reg.pc <= 64'h0000_0000_8020_1530) ||
    //         (IDEXE_reg.pc >= 64'h0000_0000_8020_1510 && IDEXE_reg.pc <= 64'h0000_0000_8020_1530) ||
    //         (EXEMEM_reg.pc >= 64'h0000_0000_8020_1510 && EXEMEM_reg.pc <= 64'h0000_0000_8020_1530) ||
    //         (MEMWB_reg.pc >= 64'h0000_0000_8020_1510 && MEMWB_reg.pc <= 64'h0000_0000_8020_1530) ||
    //         (pc >= 64'h0000_0000_8000_00bc && pc <= 64'h0000_0000_8000_00d0)
    //     )) begin
    //         $display("[CORE-TRAP] t=%0t pc=%h if=%h/%0d id=%h/%0d ex=%h/%0d mem=%h/%0d sw=%0d pc_csr=%h ex4=%0d ex5=%0d memwb_inst=%h memwb_valid=%0d",
    //                  $time, pc,
    //                  IFID_reg.pc, IFID_reg.valid,
    //                  IDEXE_reg.pc, IDEXE_reg.valid,
    //                  EXEMEM_reg.pc, EXEMEM_reg.valid,
    //                  MEMWB_reg.pc, MEMWB_reg.valid,
    //                  switch_mode, pc_csr, except_commit_wb.except, except_cosim_wb.except,
    //                  MEMWB_reg.inst, MEMWB_reg.valid);
    //     end
    //
    //     if (!rst && MEMWB_reg.valid && MEMWB_reg.we_csr &&
    //         ((MEMWB_reg.pc == 64'h0000_0000_8000_00bc) ||
    //          (MEMWB_reg.pc == 64'h0000_0000_8000_01e4))) begin
    //         $display("[CORE-CSR]  t=%0t pc=%h inst=%h rd=%0d wb=%h csr_new=%h csr_old=%h",
    //                  $time, MEMWB_reg.pc, MEMWB_reg.inst, MEMWB_reg.rd,
    //                  final_wdata_for_regfile, MEMWB_reg.alu_res, MEMWB_reg.csr_alu_res);
    //     end
    // end

endmodule
