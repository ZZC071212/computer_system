`ifdef VERILATE
    `ifdef TESTCASE
        localparam ROM_PATH = "testcase.hex";
    `else
        localparam ROM_PATH = "rom.hex";
    `endif
    
    `ifdef BOARD_SIM
        localparam BUFFER_PATH = "elf.hex";
        localparam KERNEL_PATH = "dummy.hex";
    `else
        localparam BUFFER_PATH = "dummy.hex";
        localparam KERNEL_PATH = "mini_sbi.hex";
    `endif
`else
    localparam FILE_PATH = "E:\\A_Study\\TA-SYS2\\Lab2\\testcase.hex";
`endif 