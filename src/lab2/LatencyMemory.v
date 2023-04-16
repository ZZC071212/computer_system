`timescale 1ns / 1ps

module LatencyMemory(
    input clk,
    input rst,
    input en,
    input we,
    input [31:0] addr, // you can change the width
    input [31:0] data_in,
    output [31:0] data_out
);

	reg [31:0] clkdiv = 0; 

	always @ (posedge clk)begin
	    if (rst) clkdiv <= 0;
	    else clkdiv <= clkdiv + 1;
	end

	wire clk_latency;
	assign clk_latency = clkdiv[3]; // latency memory clock

	blk_mem Memory(
	    .clka(clk_latency),
	    .ena(en),
	    .wea(we),
	    .addra(addr[31:0]), // you can change the width
	    .dina(data_in[31:0]),
	    .douta(data_out[31:0])
	);
endmodule
