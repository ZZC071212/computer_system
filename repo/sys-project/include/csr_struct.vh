`ifndef __CSR_STRUCT__
`define __CSR_STRUCT__

package CsrPack;
    typedef enum logic [1:0] {
        CSR_ALU_ADD, CSR_ALU_OR, CSR_ALU_ANDNOT
    } csr_alu_op_enmu;

    typedef enum logic [1:0] {
        ASEL_CSR0, ASEL_CSRREG
    } csr_alu_asel_op_enum;

    typedef enum logic [1:0] {
        BSEL_CSR0,  BSEL_GPREG,  BSEL_CSRIMM
    } csr_alu_bsel_op_enum;

    typedef struct{
        logic except;
        logic [63:0] epc;
        logic [63:0] ecause;
        logic [63:0] etval;
    } ExceptPack;

    typedef struct{
        logic [63:0] sstatus;
        logic [63:0] sie;
        logic [63:0] stvec;
        logic [63:0] sscratch;
        logic [63:0] sepc;
        logic [63:0] scause;
        logic [63:0] stval;
        logic [63:0] sip;

        logic [63:0] mstatus;
        logic [63:0] mie;
        logic [63:0] mtvec;
        logic [63:0] mscratch;
        logic [63:0] mepc;
        logic [63:0] mcause;
        logic [63:0] mtval;
        logic [63:0] mip;

        logic [63:0] medeleg;
        logic [63:0] mideleg;
        
        logic [63:0] priv;
        logic [63:0] switch_mode;
        logic [63:0] pc_csr;
        logic [63:0] cosim_epc;
        logic [63:0] cosim_cause;
        logic [63:0] cosim_tval;
        logic [63:0] csr_ret;
    } CSRPack;
    
    typedef logic [11:0] csr_reg_ind_t;

    parameter CSR_OPCODE    = 7'b1110011;

    parameter CSRRW_FUNCT3 =   3'b001;
    parameter CSRRS_FUNCT3 =   3'b010;
    parameter CSRRC_FUNCT3 =   3'b011;
    parameter CSRRWI_FUNCT3 =  3'b101;
    parameter CSRRSI_FUNCT3 =  3'b110;
    parameter CSRRCI_FUNCT3 =  3'b111;

    parameter TIME_BASE = 64'h2000000;
    parameter TIME_LEN = 64'h10000;
    parameter MTIME_BASE = 64'h200bff8;
    parameter MTIME_LEN = 64'h8;
    parameter MTIMECMP_BASE = 64'h2004000;
    parameter MTIMECMP_LEN = 64'h8;
    parameter DISP_BASE = 64'h3000000;
    parameter DISP_LEN = 64'h1;
    parameter UART_BASE = 64'h4000000;
    parameter UART_LEN = 64'h10;

    parameter ROM_BASE = 64'h0;
    parameter ROM_LEN = 64'h1000;
    parameter BUFFER_BASE = 64'h10000;
    parameter BUFFER_LEN = 64'h4000;
    parameter MEM_BASE = 64'h80000000;
    parameter MEM_LEN = 64'h80000000;

    parameter USI = 64'h8000000000000000;
    parameter SSI = 64'h8000000000000001;
    parameter HSI = 64'h8000000000000002;
    parameter MSI = 64'h8000000000000003;
    parameter UTI = 64'h8000000000000004;
    parameter STI = 64'h8000000000000005;
    parameter HTI = 64'h8000000000000006;
    parameter MTI = 64'h8000000000000007;
    parameter UEI = 64'h8000000000000008;
    parameter SEI = 64'h8000000000000009;
    parameter HEI = 64'h800000000000000a;
    parameter MEI = 64'h800000000000000b;
    parameter INST_ADDR_UNALIGN =  64'h0;
    parameter INST_ACCESS_FAULT =  64'h1;
    parameter ILLEAGAL_INST =      64'h2;
    parameter BREAKPOINT =         64'h3;
    parameter LOAD_ADDR_UNALIGN =  64'h4;
    parameter LOAD_ACCESS_FAULT =  64'h5;
    parameter STORE_ADDR_UNALIGN = 64'h6;
    parameter STORE_ACCESS_FAULT = 64'h7;
    parameter U_CALL = 64'h8;
    parameter S_CALL = 64'h9;
    parameter H_CALL = 64'ha;
    parameter M_CALL = 64'hb;

    parameter ECALL = 32'h00000073;
    parameter EBREAK = 32'h00100073;

    parameter MRET =  32'h30200073;
    parameter SRET =  32'h10200073;

    parameter SSTATUS =  12'h100;
    parameter SIE     =  12'h104;
    parameter STVEC   =  12'h105;
    parameter SSCRATCH = 12'h140;
    parameter SEPC    =  12'h141;
    parameter SCAUSE  =  12'h142;
    parameter STVAL   =  12'h143;
    parameter SIP     =  12'h144;

    parameter SSTATUS_COMPRESS =  5'b00000;
    parameter SIE_COMPRESS     =  5'b00100;
    parameter STVEC_COMPRESS   =  5'b00101;
    parameter SSCRATCH_COMPRESS = 5'b01000;
    parameter SEPC_COMPRESS    =  5'b01001;
    parameter SCAUSE_COMPRESS  =  5'b01010;
    parameter STVAL_COMPRESS   =  5'b01011;
    parameter SIP_COMPRESS     =  5'b01100;

    parameter MSTATUS  = 12'h300;
    parameter MEDELEG  = 12'h302;
    parameter MIDELEG  = 12'h303;
    parameter MIE      = 12'h304;
    parameter MTVEC    = 12'h305;
    parameter MSCRATCH = 12'h340;
    parameter MEPC     = 12'h341;
    parameter MCAUSE   = 12'h342;
    parameter MTVAL    = 12'h343;
    parameter MIP      = 12'h344;

    parameter MSTATUS_COMPRESS = 5'b10000;
    parameter MEDELEG_COMPRESS = 5'b10010;
    parameter MIDELEG_COMPRESS = 5'b10011;
    parameter MIE_COMPRESS     = 5'b10100;
    parameter MTVEC_COMPRESS   = 5'b10101;
    parameter MSCRATCH_COMPRESS= 5'b11000;
    parameter MEPC_COMPRESS    = 5'b11001;
    parameter MCAUSE_COMPRESS  = 5'b11010;
    parameter MTVAL_COMPRESS   = 5'b11011;
    parameter MIP_COMPRESS     = 5'b11100;
endpackage

`endif 

