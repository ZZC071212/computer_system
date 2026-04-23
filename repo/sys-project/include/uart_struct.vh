`ifndef __UART_STRUCT__
`define __UART_STRUCT__
package UartPack;

    parameter UART_DATA_WIDTH = 8;
    typedef logic [UART_DATA_WIDTH-1:0] uart_t;
    parameter UART_STRUCT_WIDTH = UART_DATA_WIDTH;

    parameter UART_ADDR_WIDTH  = 12;
    parameter [UART_ADDR_WIDTH-1:0] DATA_REG_OFFSET  = 0;
    parameter [UART_ADDR_WIDTH-1:0] STATE_REG_OFFSET = 1;
    
    typedef logic [UART_ADDR_WIDTH-1:0] addr_t;

    typedef struct {
        logic [63:0] uart_info;
    } UartInfo ;
    
endpackage
`endif