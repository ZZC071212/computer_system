`timescale 1ns / 10ps

// Copyright 2023 Sycuricon Group
// Author: Jinyan Xu (phantom@zju.edu.cn)

`include "core_struct.vh"
`include "mem_struct.vh"
`include "csr_struct.vh"

// `define UART_DEBUG
`define CONV_DEBUG

module Testbench;

	import CorePack::*;
	import MemPack::*;
	localparam max_sim_cycle = 32'd5000000;

	reg clk=1'b0;
	reg [31:0] clk_div=32'b0;
	reg rstn=1'b0;

	initial begin
		#20;
		rstn=1'b1;
	end
	always begin
		#5;
		clk=~clk;
	end
	always@(posedge clk)begin
		clk_div <= clk_div + 32'b1;
	end

	wire cosim_valid;
	CoreInfo cosim_core_info;
	CsrPack::CSRPack cosim_csr_info;
	MemInfo cosim_mem_info;
	wire rxd;
	wire rts;
	wire txd;
	wire cts;
	wire core_clk = clk_div[0];
	wire sys_clk = clk;
	wire cosim_interrupt;
	wire cosim_switch_mode;
	wire [63:0] cosim_cause;

    SCPU dut (   
        .core_clk(core_clk),
	    .rstn(rstn),
		.cosim_valid(cosim_valid),
		.cosim_core_info(cosim_core_info),
		.cosim_mem_info(cosim_mem_info),
        .cosim_csr_info(cosim_csr_info),
        .cosim_interrupt(cosim_interrupt),
		.cosim_switch_mode(cosim_switch_mode),
        .cosim_cause(cosim_cause),

		.sys_clk(sys_clk),
		.rxd(rxd),
		.rts(rts),
		.cts(cts),
		.txd(txd)
	);

	`ifdef VERILATE
		initial begin
			$dumpfile({`TOP_DIR,"/Testbench.vcd"});
			$dumpvars(0,dut);
			$dumpon;
		end

		wire error;
        cj_comsimulation difftest (   
            .clk(core_clk),
            .rstn(rstn),
            .cosim_valid(cosim_valid),
            .cosim_pc(cosim_core_info.pc),
            .cosim_inst(cosim_core_info.inst[31:0]),
            .cosim_we(cosim_core_info.rd_we[0]),
            .cosim_rd(cosim_core_info.rd_id[4:0]),
            .cosim_wdate(cosim_core_info.rd_data),
			.cosim_mmio_store(),
			.cosim_mmio_len(),
			.cosim_mmio_val(),
			.cosim_mmio_addr(),

			.cosim_interrupt(cosim_interrupt),
			.cosim_switch_mode(cosim_switch_mode),
        	.cosim_cause(cosim_cause),
            .error(error)
        );

		`ifdef UART_DEBUG
			SimUart #(
				.ClkFrequency(100000000),
				.Baud(10000000),
				.TransmitInterval(20) 
			) sim_uart (
				.sys_clk(sys_clk),
				.rstn(rstn),
				.txd(txd),
				.cts(cts),
				.rxd(rxd),
				.rts(rts)
			);
		`endif

		reg [31:0] cnt=32'b0;
		always@(negedge clk)begin
			cnt<=cnt+32'b1;
			if(error)begin
				$display("[CJ] something error");
				$dumpoff;
				$finish;
			end else if(cnt==max_sim_cycle)begin
				$display("[CJ] no simulation time");
				$dumpoff;
				$finish;
			end
		end
	`endif

endmodule

