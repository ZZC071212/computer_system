`include "csr_struct.vh"

`ifndef __CORE_STRUCT__
`define __CORE_STRUCT__

package CorePack;

    parameter xLen = 64;
    parameter ADDR_WIDTH = xLen;
    parameter DATA_WIDTH = xLen;
    parameter MASK_WIDTH = DATA_WIDTH/8;
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [MASK_WIDTH-1:0] mask_t;
    typedef logic [31:0] inst_t;
    typedef logic [4:0] reg_ind_t;

    typedef enum logic [3:0] {
        ALU_ADD,  ALU_SUB,  ALU_AND,  ALU_OR,
        ALU_XOR,  ALU_SLT,  ALU_SLTU, ALU_SLL,
        ALU_SRL,  ALU_SRA,  ALU_ADDW, ALU_SUBW,
        ALU_SLLW, ALU_SRLW, ALU_SRAW, ALU_DEFAULT
    } alu_op_enum;

    typedef enum logic [2:0] {
        MEM_NO, MEM_D,  MEM_W,  MEM_H,
        MEM_B,  MEM_UB, MEM_UH, MEM_UW
    } mem_op_enum;

    typedef enum logic [2:0] {
        CMP_NO,  CMP_EQ,  CMP_NE,  CMP_LT,
        CMP_GE,  CMP_LTU, CMP_GEU, CMP7
    } cmp_op_enum;

    typedef enum logic [3:0] {
        IMM0,  I_IMM, S_IMM, B_IMM, 
        U_IMM, UJ_IMM, IMM6, IMM7, CSR_IMM
    } imm_op_enum;

    typedef enum logic [1:0] {
        ASEL0,  ASEL_REG,  ASEL_PC,  ASEL_CSR
    } alu_asel_op_enum;

    typedef enum logic [1:0] {
        BSEL0,  BSEL_REG,  BSEL_IMM,  BSEL3
    } alu_bsel_op_enum;

    typedef enum logic [1:0] {
        WB_SEL0, WB_SEL_ALU, WB_SEL_MEM, WB_SEL_PC
    } wb_sel_op_enum;

    typedef enum logic [2:0] {
        REGFILE, ALUEXE, ALUMEM, ALUWB, RDATAWB
    } rs_sel_enum;

    typedef logic [6:0] opcode_t;
    parameter LOAD_OPCODE   = 7'b0000011;
    parameter IMM_OPCODE    = 7'b0010011;
    parameter AUIPC_OPCODE  = 7'b0010111;
    parameter IMMW_OPCODE   = 7'b0011011;
    parameter STORE_OPCODE  = 7'b0100011;
    parameter REG_OPCODE    = 7'b0110011;
    parameter LUI_OPCODE    = 7'b0110111;
    parameter REGW_OPCODE   = 7'b0111011;
    parameter BRANCH_OPCODE = 7'b1100011;
    parameter JALR_OPCODE   = 7'b1100111;
    parameter JAL_OPCODE    = 7'b1101111;

    typedef logic [2:0] funct3_t;
    typedef logic [6:0] funct7_t;
    parameter BEQ_FUNCT3   =   3'b000;
    parameter BNE_FUNCT3   =   3'b001;
    parameter BLT_FUNCT3   =   3'b100;
    parameter BGE_FUNCT3   =   3'b101;
    parameter BLTU_FUNCT3  =   3'b110;
    parameter BGEU_FUNCT3  =   3'b111;

    parameter LB_FUNCT3    =   3'b000;
    parameter LH_FUNCT3    =   3'b001;
    parameter LW_FUNCT3    =   3'b010;
    parameter LD_FUNCT3    =   3'b011;
    parameter LBU_FUNCT3   =   3'b100;
    parameter LHU_FUNCT3   =   3'b101;
    parameter LWU_FUNCT3   =   3'b110;

    parameter SB_FUNCT3    =   3'b000;
    parameter SH_FUNCT3    =   3'b001;
    parameter SW_FUNCT3    =   3'b010;
    parameter SD_FUNCT3    =   3'b011;

    parameter ADD_FUNCT3   =   3'b000;
    parameter SUB_FUNCT3   =   3'b000;
    parameter SLL_FUNCT3   =   3'b001;
    parameter SLT_FUNCT3   =   3'b010;
    parameter SLTU_FUNCT3  =   3'b011;
    parameter XOR_FUNCT3   =   3'b100;
    parameter SRL_FUNCT3   =   3'b101;
    parameter SRA_FUNCT3   =   3'b101;
    parameter OR_FUNCT3    =   3'b110;
    parameter AND_FUNCT3   =   3'b111;
    parameter ADDW_FUNCT3  =   3'b000;
    parameter SUBW_FUNCT3  =   3'b000;
    parameter SLLW_FUNCT3  =   3'b001;
    parameter SRLW_FUNCT3  =   3'b101;
    parameter SRAW_FUNCT3  =   3'b101;

    typedef struct{
        logic   [63:0]  pc;   
        logic   [63:0]  inst;    
        logic   [63:0]  rs1_id;  
        logic   [63:0]  rs1_data;
        logic   [63:0]  rs2_id; 
        logic   [63:0]  rs2_data;
        logic   [63:0]  alu;
        logic   [63:0]  mem_addr;
        logic   [63:0]  mem_we;
        logic   [63:0]  mem_wdata;
        logic   [63:0]  mem_rdata;
        logic   [63:0]  rd_we;
        logic   [63:0]  rd_id;   
        logic   [63:0]  rd_data; 
        logic   [63:0]  br_taken;
        logic   [63:0]  npc;
    } CoreInfo;
endpackage

package PipelinePack;
    import CorePack::*;
    import CsrPack::*;

    typedef struct{
        addr_t  pc;
        addr_t  pc_4;
        inst_t  inst;
        logic   valid;
    } IFID;

    typedef struct{
        logic               we_reg;
        logic               we_mem;
        logic               re_mem;
        logic               npc_sel;
        logic               we_csr;
        logic   [1:0]       csr_ret;
        data_t              imm;
        alu_op_enum         alu_op;
        csr_alu_op_enmu     csr_alu_op;
        cmp_op_enum         cmp_op;
        alu_asel_op_enum    alu_a_sel;
        alu_bsel_op_enum    alu_b_sel;
        csr_alu_asel_op_enum csr_alu_asel;
        csr_alu_bsel_op_enum csr_alu_bsel;
        data_t              reg_data_1;
        data_t              reg_data_2;
        data_t              csr_val;
        wb_sel_op_enum      wb_sel;
        mem_op_enum         mem_op;

        reg_ind_t   rd;
        reg_ind_t   rs1;
        reg_ind_t   rs2;
        csr_reg_ind_t  csr_addr;

        addr_t      pc;
        addr_t      pc_4;
        inst_t      inst;
        logic       valid;
    } IDEXE;

    typedef struct{
        logic           we_reg;
        logic           we_mem;
        logic           re_mem;
        logic           br_taken;
        logic           we_csr;
        logic   [1:0]       csr_ret;
        data_t          alu_res;
        data_t          reg_data_1;
        data_t          reg_data_2;
        data_t          csr_alu_res;
        data_t          mem_wdata;

        wb_sel_op_enum  wb_sel;
        mem_op_enum     mem_op;

        reg_ind_t       rd;
        reg_ind_t       rs1;
        reg_ind_t       rs2;
        csr_reg_ind_t   csr_addr;

        addr_t          pc;
        addr_t          pc_4;
        addr_t          npc;
        inst_t          inst;
        logic           valid;
    } EXEMEM;

    typedef struct{
        logic           we_reg;
        logic           re_mem;
        logic           br_taken;
        logic           we_csr;
        logic   [1:0]   csr_ret;
        data_t          mem_we;
        data_t          alu_res;
        data_t          data_trunc;
        data_t          read_data_1;
        data_t          read_data_2;
        data_t          csr_alu_res;
        data_t          mem_wdata;
        data_t          mem_rdata;
        addr_t          mem_addr;
        wb_sel_op_enum  wb_sel;

        reg_ind_t       rd;
        reg_ind_t       rs1;
        reg_ind_t       rs2;
        csr_reg_ind_t   csr_addr;

        addr_t          pc;
        addr_t          pc_4;
        addr_t          npc;
        inst_t          inst;
        logic           valid;
    } MEMWB;

endpackage

package ControllerPack;
    import CorePack::*;
    import CsrPack::*;
    typedef struct{
        logic               we_reg;
        logic               we_mem;
        logic               re_mem;
        logic               npc_sel;
        logic               we_csr;
        logic   [1:0]       csr_ret;
        reg_ind_t           rd;
        reg_ind_t           rs1;
        reg_ind_t           rs2;
        imm_op_enum         immgen_op;
        alu_op_enum         alu_op;
        cmp_op_enum         cmp_op;
        alu_asel_op_enum    alu_a_sel;
        alu_bsel_op_enum    alu_b_sel;
        wb_sel_op_enum      wb_sel;
        mem_op_enum         mem_op;
        csr_reg_ind_t       csr_addr;
        csr_alu_asel_op_enum csr_alu_asel;
        csr_alu_bsel_op_enum csr_alu_bsel;
        csr_alu_op_enmu     csr_alu_op;
    } ControllerSignals;
endpackage

`endif