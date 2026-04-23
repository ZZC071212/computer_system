`include "core_struct.vh"

module DataTrunc (
    input CorePack::data_t dmem_rdata,
    input CorePack::mem_op_enum mem_op,
    input CorePack::addr_t dmem_raddr,
    output CorePack::data_t read_data
);
import CorePack::*;

always_comb begin
    logic [2:0] offset = dmem_raddr[2:0];
    logic [63:0] shifted_data = dmem_rdata >> (offset * 8);

    case(mem_op)
        MEM_B:  read_data = {{56{shifted_data[7]}}, shifted_data[7:0]};
        MEM_H:  read_data = {{48{shifted_data[15]}}, shifted_data[15:0]};
        MEM_W:  read_data = {{32{shifted_data[31]}}, shifted_data[31:0]};
        MEM_D:  read_data = shifted_data;
        MEM_UB: read_data = {56'b0, shifted_data[7:0]};
        MEM_UH: read_data = {48'b0, shifted_data[15:0]};
        MEM_UW: read_data = {32'b0, shifted_data[31:0]};
        default: read_data = shifted_data;
    endcase
end

endmodule


