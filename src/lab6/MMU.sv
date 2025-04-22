`include "core_struct.vh"
`include "csr_struct.vh"

module MMU(
    input clk,
    input rst,
    input CorePack::data_t satp,
    input [1:0] priv,
    input switch_mode,
    input CorePack::data_t pc_if,
    input CorePack::data_t pc_mem,

    output CsrPack::ExceptPack except_mmu,

    Mem_ift.Slave core_imem_ift,
    Mem_ift.Slave core_dmem_ift,

    Mem_ift.Master mem_imem_ift,
    Mem_ift.Master mem_dmem_ift
);


    //TODO: Finish your MMU

endmodule