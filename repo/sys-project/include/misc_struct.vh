`ifndef __MISC_STRUCT__
`define __MISC_STRUCT__
package MiscPack;

    parameter MISC_ADDR_WIDTH = 12;
    parameter MISC_DATA_WIDTH = 64;

    parameter [MISC_ADDR_WIDTH-1:0] MTIME_REG_OFFSET  = 0;
    parameter [MISC_ADDR_WIDTH-1:0] MTIMECMP_REG_OFFSET  = 8;
    parameter [MISC_ADDR_WIDTH-1:0] DISPLAY_REG_OFFSET  = 16;

    typedef struct {
        logic [63:0] misc_mtime;
        logic [63:0] misc_mtimecmp;
        logic [63:0] misc_display;
    } MiscInfo;
    
endpackage
`endif