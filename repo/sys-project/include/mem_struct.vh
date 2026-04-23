`ifndef __MEM_STRUCT__
`define __MEM_STRUCT__
`include"uart_struct.vh"
`include"conv_struct.vh"
`include"misc_struct.vh"
package MemPack;

    parameter boot_start    = 64'h0;
    parameter boot_len      = 64'h2000;
    parameter boot_end      = boot_start + boot_len;
    parameter buffer_start  = 64'h10000;
    parameter buffer_len    = 64'h4000;
    parameter buffer_end    = buffer_start + buffer_len;
    parameter uart_start    = 64'h10000000;
    parameter uart_len      = 64'h1000;
    parameter uart_end      = uart_start + uart_len;
    parameter cov_start     = 64'h10001000;
    parameter cov_len       = 64'h1000;
    parameter cov_end       = cov_start + cov_len;
    parameter misc_start    = 64'h10002000;
    parameter misc_len      = 64'h1000;
    parameter misc_end      = misc_start + misc_len;
    parameter ddr_start     = 64'h80000000;
    parameter ddr_len       = 64'h400000;
    parameter ddr_end       = ddr_start + ddr_len;

    typedef struct {
        UartPack::UartInfo uart_info;
        ConvPack::ConvInfo conv_info;
        MiscPack::MiscInfo misc_info;
    } MemInfo;

endpackage

`endif