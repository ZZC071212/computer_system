`timescale 1ns / 1ps

// Copyright 2023 Sycuricon Group
// Author: Jinyan Xu (phantom@zju.edu.cn)
`include "core_struct.vh"
`include "mem_struct.vh"

module top (
    input wire         clk,
	input wire         rstn,
    input wire  [15:0] switch, 
    input wire  [ 4:0] btn,
    output wire [ 7:0] cs,
    output wire [ 7:0] an,
    input wire rxd,
    output wire txd
);
    import CorePack::*;
    import MemPack::*;
    wire clk_core;
    CoreInfo cosim_core_info;
    MemInfo cosim_mem_info;

    SCPU dut (   
        .core_clk(clk_core),
	    .rstn(rstn),
	    .cosim_valid(cosim_valid),
	    .cosim_core_info(cosim_core_info),
        .cosim_mem_info(cosim_mem_info),

        .sys_clk(clk),
        .rxd(rxd),
        .rts(),
        .cts(1'b0),
        .txd(txd)
	);
    
    IO io(
        .clk(clk),
        .rstn(rstn),
        .clk_core(clk_core),
        .switch(switch),
        .btn(btn),
        .cs(cs),
        .an(an),
        .cosim_valid(cosim_valid),
        .cosim_core_info(cosim_core_info),
        .cosim_mem_info(cosim_mem_info)
    );

endmodule

