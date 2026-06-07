`include "core_struct.vh"

module ALU (
    input CorePack::data_t a,
    input CorePack::data_t b,
    input CorePack::alu_op_enum alu_op,
    output CorePack::data_t res
);
import CorePack::*;

logic [31:0] addw_sum, subw_diff, sllw_shift, sraw_shift;

/* verilator lint_off LATCH */
always_comb begin
    case(alu_op)
        ALU_ADD:  res = a + b;
        ALU_SUB:  res = a - b;
        ALU_AND:  res = a & b;
        ALU_OR:   res = a | b;
        ALU_XOR:  res = a ^ b;
        ALU_SLT:  res = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
        ALU_SLTU: res = (a < b) ? 64'd1 : 64'd0;
        ALU_SLL:  res = a << b[5:0];
        ALU_SRL:  res = a >> b[5:0];
        ALU_SRA:  res = $signed(a) >>> b[5:0];
        ALU_ADDW: begin
            addw_sum = a[31:0] + b[31:0];
            res = {{32{addw_sum[31]}}, addw_sum};
        end
        ALU_SUBW: begin
            subw_diff = a[31:0] - b[31:0];
            res = {{32{subw_diff[31]}}, subw_diff};
        end
        ALU_SLLW: begin
            sllw_shift = a[31:0] << b[4:0];
            res = {{32{sllw_shift[31]}}, sllw_shift};
        end
        ALU_SRAW: begin
            sraw_shift = $signed(a[31:0]) >>> b[4:0];
            res = {{32{sraw_shift[31]}}, sraw_shift};
        end
        
        // ALU_SRLW保持不变（零扩展）
        ALU_SRLW: res = {{32{1'b0}}, a[31:0] >> b[4:0]};
       // ALU_ADDW: res = {{32{a[31]}}, a[31:0] + b[31:0]};
        //ALU_SUBW: res = {{32{a[31]}}, a[31:0] - b[31:0]};
        //ALU_SLLW: res = {{32{a[31]}}, a[31:0] << b[4:0]};
        //ALU_SRLW: res = {{32{1'b0}}, a[31:0] >> b[4:0]};
        //ALU_SRAW: res = {{32{a[31]}}, $signed(a[31:0]) >>> b[4:0]};
        default:  res = a + b; // ALU_DEFAULT
    endcase
end
/* verilator lint_off LATCH */
endmodule