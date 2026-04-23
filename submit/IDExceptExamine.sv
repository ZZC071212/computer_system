`include "core_struct.vh"
`include "csr_struct.vh"

module IDExceptExamine(
    input clk,
    input rst,
    input stall,
    input flush,

    input CorePack::addr_t pc_id,
    input [1:0] priv,
    input CorePack::inst_t inst_id,
    input valid_id,
    
    input CsrPack::ExceptPack except_id,
    output CsrPack::ExceptPack except_exe,
    output except_happen_id
);
    
    import CsrPack::ExceptPack;
    ExceptPack except_new;
    ExceptPack except;

    InstExamine instexmaine(
        .pc_i(pc_id),
        .priv_i(priv),
        .inst_i(inst_id),
        .valid_i(valid_id),
        .except_o(except_new)
    );

    assign except=except_id.except?except_id:except_new;
    assign except_happen_id=except_new.except&~except_id.except;

    ExceptReg exceptreg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .except_i(except),
        .except_o(except_exe)
    );

endmodule 

module InstExamine (
    input CorePack::addr_t pc_i,
    input [1:0] priv_i,
    input CorePack::inst_t inst_i,
    input valid_i,
    output CsrPack::ExceptPack except_o
);
    import CsrPack::*;
    import CorePack::*;
    
    wire [6:0] opcode = inst_i[6:0];
    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];
    wire [11:0] csr_addr = inst_i[31:20];
    wire [4:0] csr_src = inst_i[19:15];

    wire is_ecall=inst_i==ECALL;
    wire is_ebreak=inst_i==EBREAK;
    wire is_mret=inst_i==MRET;
    wire is_sret=inst_i==SRET;

    wire inst_lui    = (opcode == LUI_OPCODE);
    wire inst_auipc  = (opcode == AUIPC_OPCODE);
    wire inst_jal    = (opcode == JAL_OPCODE);
    wire inst_jalr   = (opcode == JALR_OPCODE);
    wire inst_branch = (opcode == BRANCH_OPCODE);
    wire inst_load   = (opcode == LOAD_OPCODE);
    wire inst_store  = (opcode == STORE_OPCODE);
    wire inst_imm    = (opcode == IMM_OPCODE);
    wire inst_reg    = (opcode == REG_OPCODE);
    wire inst_immw   = (opcode == IMMW_OPCODE);
    wire inst_regw   = (opcode == REGW_OPCODE);
    wire inst_system = (opcode == CSR_OPCODE);

    wire valid_jalr = inst_jalr && (funct3 == 3'b000);
    wire valid_branch = inst_branch &&
                        ((funct3 == BEQ_FUNCT3)  || (funct3 == BNE_FUNCT3) ||
                         (funct3 == BLT_FUNCT3)  || (funct3 == BGE_FUNCT3) ||
                         (funct3 == BLTU_FUNCT3) || (funct3 == BGEU_FUNCT3));
    wire valid_load = inst_load &&
                      ((funct3 == LB_FUNCT3)  || (funct3 == LH_FUNCT3)  ||
                       (funct3 == LW_FUNCT3)  || (funct3 == LD_FUNCT3)  ||
                       (funct3 == LBU_FUNCT3) || (funct3 == LHU_FUNCT3) ||
                       (funct3 == LWU_FUNCT3));
    wire valid_store = inst_store &&
                       ((funct3 == SB_FUNCT3) || (funct3 == SH_FUNCT3) ||
                        (funct3 == SW_FUNCT3) || (funct3 == SD_FUNCT3));

    wire valid_imm_shift = (funct3 == SLL_FUNCT3 && (inst_i[31:26] == 6'b000000)) ||
                           (funct3 == SRL_FUNCT3 &&
                            ((inst_i[31:26] == 6'b000000) || (inst_i[31:26] == 6'b010000)));
    wire valid_imm = inst_imm &&
                     ((funct3 == ADD_FUNCT3)  || (funct3 == SLT_FUNCT3)  ||
                      (funct3 == SLTU_FUNCT3) || (funct3 == XOR_FUNCT3)  ||
                      (funct3 == OR_FUNCT3)   || (funct3 == AND_FUNCT3)  ||
                      valid_imm_shift);

    wire valid_reg_shift = (funct3 == SLL_FUNCT3 && (funct7 == 7'b0000000)) ||
                           (funct3 == SRL_FUNCT3 && ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)));
    wire valid_reg_addsub = (funct3 == ADD_FUNCT3) && ((funct7 == 7'b0000000) || (funct7 == 7'b0100000));
    wire valid_reg_logic = ((funct3 == SLT_FUNCT3)  || (funct3 == SLTU_FUNCT3) ||
                            (funct3 == XOR_FUNCT3)  || (funct3 == OR_FUNCT3)   ||
                            (funct3 == AND_FUNCT3)) && (funct7 == 7'b0000000);
    wire valid_reg = inst_reg && (valid_reg_addsub || valid_reg_shift || valid_reg_logic);

    wire valid_immw_shift = (funct3 == SLLW_FUNCT3 && (funct7 == 7'b0000000)) ||
                            (funct3 == SRLW_FUNCT3 && ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)));
    wire valid_immw = inst_immw &&
                      ((funct3 == ADDW_FUNCT3) || valid_immw_shift);

    wire valid_regw_addsub = (funct3 == ADDW_FUNCT3) &&
                             ((funct7 == 7'b0000000) || (funct7 == 7'b0100000));
    wire valid_regw_shift = (funct3 == SLLW_FUNCT3 && (funct7 == 7'b0000000)) ||
                            (funct3 == SRLW_FUNCT3 && ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)));
    wire valid_regw = inst_regw && (valid_regw_addsub || valid_regw_shift);

    wire csr_cmd_valid = inst_system &&
                         ((funct3 == CSRRW_FUNCT3)  || (funct3 == CSRRS_FUNCT3)  ||
                          (funct3 == CSRRC_FUNCT3)  || (funct3 == CSRRWI_FUNCT3) ||
                          (funct3 == CSRRSI_FUNCT3) || (funct3 == CSRRCI_FUNCT3));
    wire csr_read_only = csr_addr[11:10] == 2'b11;
    wire csr_writes = (funct3 == CSRRW_FUNCT3) || (funct3 == CSRRWI_FUNCT3) ||
                      (((funct3 == CSRRS_FUNCT3) || (funct3 == CSRRC_FUNCT3) ||
                        (funct3 == CSRRSI_FUNCT3) || (funct3 == CSRRCI_FUNCT3)) && (csr_src != 5'b0));
    wire illegal_csr = csr_cmd_valid && csr_read_only && csr_writes;
    wire valid_system = (inst_system && (funct3 == 3'b000) && (is_ecall || is_ebreak || is_mret || is_sret)) ||
                        (csr_cmd_valid && !illegal_csr);

    wire is_illegal = valid_i && ((inst_i[1:0] != 2'b11) ||
                                  !(inst_lui || inst_auipc || inst_jal || valid_jalr ||
                                    valid_branch || valid_load || valid_store || valid_imm ||
                                    valid_reg || valid_immw || valid_regw || valid_system));

    wire [63:0] ecall_code [3:0];
    assign ecall_code[0]=U_CALL;
    assign ecall_code[1]=S_CALL;
    assign ecall_code[2]=H_CALL;
    assign ecall_code[3]=M_CALL;

    assign except_o.except=is_ebreak|is_ecall|is_illegal;
    assign except_o.epc=pc_i;
    assign except_o.ecause=is_ebreak?BREAKPOINT:
                           is_ecall?ecall_code[priv_i]:
                           is_illegal?ILLEAGAL_INST:
                           64'h0;
    assign except_o.etval=is_illegal?{32'b0,inst_i}:64'h0;
    
endmodule
