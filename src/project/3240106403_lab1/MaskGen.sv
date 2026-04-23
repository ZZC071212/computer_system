`include "core_struct.vh"

module MaskGen(
    input CorePack::mem_op_enum mem_op,
    input CorePack::addr_t dmem_waddr,
    output CorePack::mask_t dmem_wmask
);
import CorePack::*;

logic [2:0] offset = dmem_waddr[2:0];

always_comb begin
    dmem_wmask = '0;
    case(mem_op)
        MEM_B, MEM_UB:  dmem_wmask[offset] = 1'b1;
        MEM_H, MEM_UH:  begin
                         dmem_wmask[offset] = 1'b1;
                         dmem_wmask[offset+1] = 1'b1;
                         end
        MEM_W, MEM_UW:  begin
                         dmem_wmask[offset] = 1'b1;
                         dmem_wmask[offset+1] = 1'b1;
                         dmem_wmask[offset+2] = 1'b1;
                         dmem_wmask[offset+3] = 1'b1;
                         end
        MEM_D:          dmem_wmask = '1;
        default:        dmem_wmask = '0;
    endcase
end

endmodule




