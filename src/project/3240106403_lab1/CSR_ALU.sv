`include "csr_struct.vh"

module CSR_ALU (
    input logic [63:0] op1,
    input logic [63:0] op2,
    input CsrPack::csr_alu_op_enmu op,
    output logic [63:0] result
);

    always_comb begin
        unique case (op)
            CsrPack::CSR_ALU_ADD:    result = op2;
            CsrPack::CSR_ALU_OR:     result = op1 | op2;
            CsrPack::CSR_ALU_ANDNOT: result = op1 & (~op2);
            default:                 result = op2;
        endcase
    end

endmodule
