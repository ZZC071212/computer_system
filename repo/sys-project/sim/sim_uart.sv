`include"uart_struct.vh"
module SimUart #(
    parameter ClkFrequency = 100000000,
    parameter Baud = 9600,
    parameter TransmitInterval = 100 
)(
    input sys_clk,
    input rstn,
    input txd,
    output cts,
    output reg rxd,
    input rts
);

    localparam BaudCnt = ClkFrequency/Baud/2;
    localparam BaudCnt_1 = BaudCnt - 1;
    localparam BaudWidth = $clog2(BaudCnt);
    logic [BaudWidth-1:0] baud_cnt;
    logic baud_clk;
    always_ff@(posedge sys_clk or negedge rstn)begin
        if(~rstn)begin
            baud_cnt <= {BaudWidth{1'b0}};
            baud_clk <= 1'b0;
        end else if(baud_cnt == BaudCnt_1[BaudWidth-1:0])begin
            baud_cnt <= {BaudWidth{1'b0}};
            baud_clk <= ~baud_clk;
        end else begin
            baud_cnt <= baud_cnt + {{(BaudWidth-1){1'b0}}, 1'b1};
        end
    end

    localparam INTERVAL_WIDTH = $clog2(TransmitInterval);
    integer rdata_cnt=0;
    typedef enum logic [1:0] {RIDLE, RWORK, RSTOP} rdata_state;
    rdata_state rdata_state_reg;
    reg [2:0] rwork_cnt;
    reg [INTERVAL_WIDTH-1:0] wait_cnt;
    reg [7:0] rdata;
    reg [31:0] next_rdata;
    always@(posedge baud_clk or negedge rstn)begin
        if(~rstn)begin
            rdata_state_reg <= RIDLE;
            rxd <= 1'b1;
            wait_cnt <= TransmitInterval[INTERVAL_WIDTH-1:0];
        end else begin
            case(rdata_state_reg)
                RIDLE:begin
                    if(~|wait_cnt)begin
                        wait_cnt <= TransmitInterval[INTERVAL_WIDTH-1:0];
                    end else begin
                        wait_cnt <= wait_cnt - {{(INTERVAL_WIDTH-1){1'b0}},1'b1};
                    end
                    if(~rts & ~|wait_cnt)begin
                        next_rdata = $random();
                        rdata <= next_rdata[7:0];
                        `ifdef UART_DEBUG
                            $display("host transmit data %x",next_rdata[7:0]);
                        `endif
                        rdata_cnt <= rdata_cnt + 1;
                        rxd <= 0;
                        rdata_state_reg <= RWORK;
                        rwork_cnt <= 3'd7;
                    end
                end 
                RWORK:begin
                    rdata <= {1'b0,rdata[7:1]};
                    rxd <= rdata[0];
                    rwork_cnt <= rwork_cnt - 3'b1;
                    if(rwork_cnt == 3'b0)begin
                        rdata_state_reg <= RSTOP;
                    end
                end
                default:begin
                    rxd <= 1'b1;
                    rdata_state_reg <= RIDLE;
                end
            endcase
        end
    end

    assign cts = 1'b0;
    integer tdata_cnt=0;
    typedef enum logic [1:0] {TIDLE, TWORK, TSTOP} tdata_state;
    tdata_state tdata_state_reg;
    reg [2:0] twork_cnt;
    reg [7:0] tdata;
    always@(negedge baud_clk or negedge rstn)begin
        if(~rstn)begin
            tdata_state_reg <= TIDLE;
            tdata <= 8'b0;
        end else begin
            case(tdata_state_reg)
                TIDLE:begin
                    if(txd == 1'b0)begin
                        tdata_state_reg <= TWORK;
                        twork_cnt <= 3'd7;
                    end
                end 
                TWORK:begin
                    tdata <= {txd, tdata[7:1]};
                    twork_cnt <= twork_cnt - 3'b1;
                    if(twork_cnt == 3'b0)begin
                        tdata_state_reg <= TSTOP;
                    end
                end
                TSTOP:begin
                    `ifdef UART_DEBUG
                        $display("host receive data %x",tdata);
                    `endif
                    tdata_cnt <= tdata_cnt + 1;
                    tdata_state_reg <=  TIDLE;
                end
                default:begin
                    tdata_state_reg <= TIDLE;
                end
            endcase
        end
    end

endmodule
