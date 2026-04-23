`include "ExceptStruct.vh"
`include "CSRStruct.vh"
`include "RegStruct.vh"
`include "TimerStruct.vh"

module Core (
    input wire clk,  /* 时钟 */
    input wire rstn, /* 重置信号 */

    output wire [63:0] pc,   /* current pc */
    input  wire [31:0] inst, /* read inst from ram */

    output wire [63:0] address,    /* memory address */
    output wire        we_mem,     /* write enable */
    output wire [63:0] wdata_mem,  /* write data to memory */
    output wire [ 7:0] wmask_mem,  /* write enable for each byte */
    output wire        re_mem,     /* read enable */
    input  wire [63:0] rdata_mem,  /* read data from memory */

    input  wire if_stall,
    input  wire mem_stall,
    output wire if_request,
    output wire switch_mode,

    input TimerStruct::TimerPack time_out,

    output        cosim_valid,
    output [63:0] cosim_pc,         /* current pc */
    output [31:0] cosim_inst,       /* current instruction */
    output [ 7:0] cosim_rs1_id,     /* rs1 id */
    output [63:0] cosim_rs1_data,   /* rs1 data */
    output [ 7:0] cosim_rs2_id,     /* rs2 id */
    output [63:0] cosim_rs2_data,   /* rs2 data */
    output [63:0] cosim_alu,        /* alu out */
    output [63:0] cosim_mem_addr,   /* memory address */
    output [ 3:0] cosim_mem_we,     /* memory write enable */
    output [63:0] cosim_mem_wdata,  /* memory write data */
    output [63:0] cosim_mem_rdata,  /* memory read data */
    output [ 3:0] cosim_rd_we,      /* rd write enable */
    output [ 7:0] cosim_rd_id,      /* rd id */
    output [63:0] cosim_rd_data,    /* rd data */
    output [ 3:0] cosim_br_taken,   /* branch taken? */
    output [63:0] cosim_npc,        /* next pc */

    output CSRStruct::CSRPack cosim_csr_info,
    output RegStruct::RegPack cosim_regs,

    output        cosim_interrupt,
    output [63:0] cosim_cause
);


endmodule
