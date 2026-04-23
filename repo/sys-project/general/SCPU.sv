`include "core_struct.vh"
`include "mem_struct.vh"
module SCPU (
    input logic core_clk,                  /* 时钟 */ 
    input logic rstn,                      /* 重置信号 */ 
    output logic cosim_valid,
    output CorePack::CoreInfo cosim_core_info,
    output MemPack::MemInfo cosim_mem_info,
    output CsrPack::CSRPack cosim_csr_info,
    output cosim_interrupt,
    output cosim_switch_mode,
    output CorePack::data_t cosim_cause,

    input logic sys_clk,
    input logic rxd,
    output logic rts,
    input logic cts,
    output logic txd
);
    import CorePack::*;
    import MemPack::*;

    `include "initial_mem.vh"

    wire rst=~rstn;

    Axi_ift #(
        .ADDR_WIDTH(xLen),
        .DATA_WIDTH(xLen)
    ) master_ift[1:0] ();

    Axi_ift #(
        .ADDR_WIDTH(xLen),
        .DATA_WIDTH(xLen)
    ) slave_ift[6:0] ();
    
    AxiCore core (
        .clk(core_clk),
        .rstn(rstn),
        .imem_ift(master_ift[0].Master),
        .dmem_ift(master_ift[1].Master),
        .time_int(time_int),
        .cosim_valid(cosim_valid),
        .cosim_core_info(cosim_core_info),
        .cosim_csr_info(cosim_csr_info),
        .cosim_interrupt(cosim_interrupt),
        .cosim_switch_mode(cosim_switch_mode),
        .cosim_cause(cosim_cause)
    );

    Axi_InterConnect #(
        .INPUT_NUM(2),
        .OUTPUT_NUM(6),
        .MEM_BEGIN({ddr_start, misc_start, cov_start, uart_start, buffer_start, boot_start}),
        .MEM_END({ddr_end, misc_end, cov_end, uart_end, buffer_end, boot_end})
    ) axi_interconnect (
        .clk(core_clk),
        .rstn(rstn),
        .master_ift(master_ift), // master_ift[INPUT_NUM] is dummy master
        .slave_ift(slave_ift) // slave_ift[OUTPUT_NUM] is dummy slave
    );

    Axi_DummySlave dummy_slave (
        .clk(core_clk),
        .rstn(rstn),
        .slave_ift(slave_ift[0].Slave)
    );

    Axi_Bram #(
        .FILE_PATH(ROM_PATH),
        .DATA_WIDTH(xLen),
        .CAPACITY(boot_len)
    ) axi_rom (
        .clk(core_clk),
        .rstn(rstn),
        .mem_ift(slave_ift[1].Slave)
    );

    Axi_Bram #(
        .FILE_PATH(BUFFER_PATH),
        .DATA_WIDTH(xLen),
        .CAPACITY(buffer_len)
    ) axi_buffer (
        .clk(core_clk),
        .rstn(rstn),
        .mem_ift(slave_ift[2].Slave)
    );

   UartPack::UartInfo cosim_uart_info;
   Axi_UartUnit #(
       .ClkFrequency(100000000),
   `ifdef VERILATE
       .Baud(10000000),
   `else
       .Baud(9600),
   `endif
       .FIFO_DEPTH(8),
       .FIFO_KIND("async")
   ) axi_uart (
       .core_clk(core_clk),
       .rstn(rstn),
       .mem_ift(slave_ift[3].Slave),
       .sys_clk(sys_clk),
       .rxd(rxd),
       .rts(rts),
       .txd(txd),
       .cts(cts),
       .cosim_uart_info(cosim_uart_info)
   );

    ConvPack::ConvInfo cosim_conv_info;
    Axi_ConvUnit #(
        .LEN(4)
    ) axi_conv (
        .clk(core_clk),
        .rstn(rstn),
        .mem_ift(slave_ift[4].Slave),

        .cosim_conv_info(cosim_conv_info)
    );
    wire time_int;
    MiscPack::MiscInfo cosim_misc_info;
    Axi_MiscUnit axi_misc (
        .clk(core_clk),
        .rstn(rstn),
        .mem_ift(slave_ift[5].Slave),

        .time_int(time_int),
        .cosim_misc_info(cosim_misc_info)
    );

`ifdef VERILATE
    Axi_Bram #(
        .FILE_PATH(KERNEL_PATH),
        .DATA_WIDTH(xLen),
        .CAPACITY(ddr_len)
    ) axi_ddr (
        .clk(core_clk),
        .rstn(rstn),
        .mem_ift(slave_ift[6].Slave)
    );
`else

`endif 

    assign cosim_mem_info.uart_info = cosim_uart_info;
    assign cosim_mem_info.conv_info = cosim_conv_info;
    assign cosim_mem_info.misc_info = cosim_misc_info;

endmodule
