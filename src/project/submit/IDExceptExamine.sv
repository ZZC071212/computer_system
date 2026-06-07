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
    
    wire is_ecall=inst_i==ECALL;
    wire is_ebreak=inst_i==EBREAK;
    wire is_mret=inst_i==MRET;
    wire is_sret=inst_i==SRET;
    wire is_sfence_vma=(inst_i[6:0] == CSR_OPCODE) && (inst_i[14:12] == 3'b000) &&
                       (inst_i[31:25] == 7'b0001001);
    wire is_csr_inst=(inst_i[6:0] == CSR_OPCODE) && (inst_i[14:12] != 3'b000);
    wire csr_known=(inst_i[31:20] == SSTATUS)  || (inst_i[31:20] == SIE)    ||
                   (inst_i[31:20] == STVEC)    || (inst_i[31:20] == SSCRATCH) ||
                   (inst_i[31:20] == SEPC)     || (inst_i[31:20] == SCAUSE) ||
                   (inst_i[31:20] == STVAL)    || (inst_i[31:20] == SIP)    ||
                   (inst_i[31:20] == SATP)     ||
                   (inst_i[31:20] == MSTATUS)  || (inst_i[31:20] == MEDELEG) ||
                   (inst_i[31:20] == MIDELEG)  || (inst_i[31:20] == MIE)    ||
                   (inst_i[31:20] == MTVEC)    || (inst_i[31:20] == MSCRATCH) ||
                   (inst_i[31:20] == MEPC)     || (inst_i[31:20] == MCAUSE) ||
                   (inst_i[31:20] == MTVAL)    || (inst_i[31:20] == MIP);
    wire is_unknown_system=(inst_i[6:0] == CSR_OPCODE) && !is_ecall && !is_ebreak &&
                           !is_mret && !is_sret && !is_sfence_vma &&
                           !(is_csr_inst && csr_known);
    wire is_illegal=((inst_i[1:0]!=2'b11) || is_unknown_system) & valid_i;

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
