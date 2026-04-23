`ifndef __BUS_STRUCT__
`define __BUS_STRUCT__

package BusPack;

    typedef logic [1:0] resp_t;
    parameter OKAY = 2'b00;
    parameter EXOKAY = 2'b01;
    parameter SLVERR = 2'b10;
    parameter DECERR = 2'b11;

endpackage

`endif