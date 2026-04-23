`include "core_struct.vh"
`include "csr_struct.vh"

module Controller (
    input CorePack::inst_t inst,
    output logic we_reg,
    output logic we_mem,
    output logic re_mem,
    output logic npc_sel,
    output CorePack::imm_op_enum immgen_op,
    output CorePack::alu_op_enum alu_op,
    output CorePack::cmp_op_enum cmp_op,
    output CorePack::alu_asel_op_enum alu_asel,
    output CorePack::alu_bsel_op_enum alu_bsel,
    output CorePack::wb_sel_op_enum wb_sel,
    output CorePack::mem_op_enum mem_op,
    output logic csr_ren,
    output logic csr_wen,
    output CsrPack::csr_alu_bsel_op_enum csr_bsel,
    output CsrPack::csr_alu_op_enmu csr_cmd,
    output logic is_csr_op,
    output logic [1:0] csr_ret
);
    import CorePack::*;
    import CsrPack::*;

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

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

    wire inst_csr = inst_system &&
                    ((funct3 == CSRRW_FUNCT3)  || (funct3 == CSRRS_FUNCT3)  || (funct3 == CSRRC_FUNCT3) ||
                     (funct3 == CSRRWI_FUNCT3) || (funct3 == CSRRSI_FUNCT3) || (funct3 == CSRRCI_FUNCT3));

    assign we_reg = inst_lui | inst_auipc | inst_jal | inst_jalr | inst_load |
                    inst_imm | inst_reg | inst_immw | inst_regw | inst_csr;
    assign we_mem = inst_store;
    assign re_mem = inst_load;
    assign npc_sel = inst_jal | inst_jalr | inst_branch;

    always_comb begin
        unique case (1'b1)
            inst_lui, inst_auipc:       immgen_op = U_IMM;
            inst_jal:                   immgen_op = UJ_IMM;
            inst_jalr, inst_load,
            inst_imm, inst_immw:        immgen_op = I_IMM;
            inst_branch:                immgen_op = B_IMM;
            inst_store:                 immgen_op = S_IMM;
            inst_csr:                   immgen_op = CSR_IMM;
            default:                    immgen_op = IMM0;
        endcase
    end

    always_comb begin
        wb_sel = WB_SEL_ALU;
        if (inst_jal || inst_jalr) begin
            wb_sel = WB_SEL_PC;
        end else if (inst_load) begin
            wb_sel = WB_SEL_MEM;
        end
    end

    always_comb begin
        alu_asel = ASEL_REG;
        if (inst_auipc || inst_jal || inst_branch) begin
            alu_asel = ASEL_PC;
        end else if (inst_lui) begin
            alu_asel = ASEL0;
        end
    end

    always_comb begin
        alu_bsel = BSEL_REG;
        if (inst_lui || inst_auipc || inst_load || inst_store || inst_imm || inst_immw ||
            inst_jal || inst_jalr || inst_branch) begin
            alu_bsel = BSEL_IMM;
        end
    end

    always_comb begin
        alu_op = ALU_DEFAULT;
        if (inst_lui || inst_auipc || inst_jal || inst_jalr || inst_load || inst_store || inst_branch) begin
            alu_op = ALU_ADD;
        end else if (inst_imm) begin
            case (funct3)
                ADD_FUNCT3:  alu_op = ALU_ADD;
                SLT_FUNCT3:  alu_op = ALU_SLT;
                SLTU_FUNCT3: alu_op = ALU_SLTU;
                AND_FUNCT3:  alu_op = ALU_AND;
                OR_FUNCT3:   alu_op = ALU_OR;
                XOR_FUNCT3:  alu_op = ALU_XOR;
                SLL_FUNCT3:  alu_op = ALU_SLL;
                SRL_FUNCT3:  alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                default:     alu_op = ALU_DEFAULT;
            endcase
        end else if (inst_reg) begin
            case (funct3)
                ADD_FUNCT3:  alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                SLT_FUNCT3:  alu_op = ALU_SLT;
                SLTU_FUNCT3: alu_op = ALU_SLTU;
                AND_FUNCT3:  alu_op = ALU_AND;
                OR_FUNCT3:   alu_op = ALU_OR;
                XOR_FUNCT3:  alu_op = ALU_XOR;
                SLL_FUNCT3:  alu_op = ALU_SLL;
                SRL_FUNCT3:  alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                default:     alu_op = ALU_DEFAULT;
            endcase
        end else if (inst_immw) begin
            case (funct3)
                ADDW_FUNCT3: alu_op = ALU_ADDW;
                SLLW_FUNCT3: alu_op = ALU_SLLW;
                SRLW_FUNCT3: alu_op = funct7[5] ? ALU_SRAW : ALU_SRLW;
                default:     alu_op = ALU_DEFAULT;
            endcase
        end else if (inst_regw) begin
            case (funct3)
                ADDW_FUNCT3: alu_op = funct7[5] ? ALU_SUBW : ALU_ADDW;
                SLLW_FUNCT3: alu_op = ALU_SLLW;
                SRLW_FUNCT3: alu_op = funct7[5] ? ALU_SRAW : ALU_SRLW;
                default:     alu_op = ALU_DEFAULT;
            endcase
        end
    end

    always_comb begin
        cmp_op = CMP_NO;
        if (inst_branch) begin
            case (funct3)
                BEQ_FUNCT3:  cmp_op = CMP_EQ;
                BNE_FUNCT3:  cmp_op = CMP_NE;
                BLT_FUNCT3:  cmp_op = CMP_LT;
                BGE_FUNCT3:  cmp_op = CMP_GE;
                BLTU_FUNCT3: cmp_op = CMP_LTU;
                BGEU_FUNCT3: cmp_op = CMP_GEU;
                default:     cmp_op = CMP_NO;
            endcase
        end
    end

    always_comb begin
        mem_op = MEM_NO;
        if (inst_load || inst_store) begin
            unique case (funct3)
                LB_FUNCT3:  mem_op = MEM_B;
                LH_FUNCT3:  mem_op = MEM_H;
                LW_FUNCT3:  mem_op = MEM_W;
                LD_FUNCT3:  mem_op = MEM_D;
                LBU_FUNCT3: mem_op = MEM_UB;
                LHU_FUNCT3: mem_op = MEM_UH;
                LWU_FUNCT3: mem_op = MEM_UW;
                default:    mem_op = MEM_NO;
            endcase
        end
    end

    always_comb begin
        is_csr_op = 1'b0;
        csr_ren   = 1'b0;
        csr_wen   = 1'b0;
        csr_cmd   = CSR_ALU_ADD;
        csr_ret   = 2'b00;
        csr_bsel  = BSEL_CSR0;

        if (inst_csr) begin
            is_csr_op = 1'b1;
            csr_ren   = 1'b1;
            csr_wen   = 1'b1;
            unique case (funct3)
                CSRRW_FUNCT3: begin
                    csr_cmd  = CSR_ALU_ADD;
                    csr_bsel = BSEL_GPREG;
                end
                CSRRS_FUNCT3: begin
                    csr_cmd  = CSR_ALU_OR;
                    csr_bsel = BSEL_GPREG;
                end
                CSRRC_FUNCT3: begin
                    csr_cmd  = CSR_ALU_ANDNOT;
                    csr_bsel = BSEL_GPREG;
                end
                CSRRWI_FUNCT3: begin
                    csr_cmd  = CSR_ALU_ADD;
                    csr_bsel = BSEL_CSRIMM;
                end
                CSRRSI_FUNCT3: begin
                    csr_cmd  = CSR_ALU_OR;
                    csr_bsel = BSEL_CSRIMM;
                end
                CSRRCI_FUNCT3: begin
                    csr_cmd  = CSR_ALU_ANDNOT;
                    csr_bsel = BSEL_CSRIMM;
                end
                default: begin
                    is_csr_op = 1'b0;
                    csr_ren   = 1'b0;
                    csr_wen   = 1'b0;
                    csr_bsel  = BSEL_CSR0;
                end
            endcase
        end else if (inst_system && (funct3 == 3'b000)) begin
            if (inst == MRET) begin
                csr_ret = 2'b10;
            end else if (inst == SRET) begin
                csr_ret = 2'b01;
            end
        end
    end

endmodule
