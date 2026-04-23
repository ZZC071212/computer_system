`include "core_struct.vh"

module DataPkg(
    input CorePack::mem_op_enum mem_op,
    input CorePack::data_t reg_data,
    input CorePack::addr_t dmem_waddr,
    output CorePack::data_t dmem_wdata
);
import CorePack::*;

logic [2:0] offset = dmem_waddr[2:0];
logic [63:0] aligned_data;

always_comb begin
    case(mem_op)
        MEM_B, MEM_UB:  aligned_data = {8{reg_data[7:0]}};
        MEM_H, MEM_UH:  aligned_data = {4{reg_data[15:0]}};
        MEM_W, MEM_UW:  aligned_data = {2{reg_data[31:0]}};
        MEM_D:          aligned_data = reg_data;
        default:        aligned_data = reg_data;
    endcase
    
    dmem_wdata = aligned_data << (offset * 8);
end

endmodule




