`ifndef __CONV_STRUCT__
`define __CONV_STRUCT__
package ConvPack;

    parameter CONV_ADDR_WIDTH = 12;
    parameter CONV_DATA_WIDTH = 64;
    typedef logic [CONV_DATA_WIDTH-1:0] conv_data_t;

    parameter [CONV_ADDR_WIDTH-1:0] KERNEL_REG_OFFSET  = 0;
    parameter [CONV_ADDR_WIDTH-1:0] DATA_REG_OFFSET  = 8;
    parameter [CONV_ADDR_WIDTH-1:0] STATE_REG_OFFSET  = 16;

    typedef struct {
        logic [127:0] conv_result;
        logic [63:0] conv_state;
    } ConvInfo ;
    
endpackage
`endif