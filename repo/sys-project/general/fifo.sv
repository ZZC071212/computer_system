module DecoupledFifo #(
    parameter FIFO_DEPTH = 8,
    parameter FIFO_KIND  = "sync"
)(
    input logic rstn,

    input logic out_clk,
    Decoupled_ift.Master out_data,

    input logic in_clk,
    Decoupled_ift.Slave in_data
);

    logic empty;
    logic full;
    Fifo #(
        .DATA_WIDTH(out_data.DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_KIND(FIFO_KIND)
    ) fifo (
        .rstn(rstn),
        .rclk(out_clk),
        .ren(out_data.ready),
        .out_data(out_data.data),
        .empty(empty),

        .wclk(in_clk),
        .wen(in_data.valid),
        .in_data(in_data.data),
        .full(full)
    );

    assign in_data.ready = ~full;
    assign out_data.valid = ~empty;

endmodule

module Fifo #(
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 8,
    parameter FIFO_KIND  = "sync"
) (
    input logic rstn,

    input logic rclk,
    input logic ren,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic empty,

    input logic wclk,
    input logic wen,
    input logic [DATA_WIDTH-1:0] in_data,
    output logic full
);

    generate
        if(FIFO_KIND == "sync")begin
            SyncFifo # (
                .DATA_WIDTH(DATA_WIDTH),
                .FIFO_DEPTH(FIFO_DEPTH)
            ) fifo (
                .clk(rclk),
                .rstn(rstn),

                .ren(ren),
                .out_data(out_data),
                .empty(empty),

                .wen(wen),
                .in_data(in_data),
                .full(full)
            );
        end else begin // async
            AsyncFifo # (
                .DATA_WIDTH(DATA_WIDTH),
                .FIFO_DEPTH(FIFO_DEPTH)
            ) fifo (
                .rstn(rstn),

                .rclk(rclk),
                .ren(ren),
                .out_data(out_data),
                .empty(empty),

                .wclk(wclk),
                .wen(wen),
                .in_data(in_data),
                .full(full)
            );
        end
    endgenerate

endmodule

module SyncFifo # (
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 8
) (
    input logic clk,
    input logic rstn,

    input logic ren,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic empty,

    input logic wen,
    input logic [DATA_WIDTH-1:0] in_data,
    output logic full
);
    typedef logic [DATA_WIDTH-1:0] data_t;
    data_t fifo [FIFO_DEPTH-1:0];

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH)+1;
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    addr_t wptr;
    addr_t rptr;

    logic [ADDR_WIDTH-2:0] windex;
    logic [ADDR_WIDTH-2:0] rindex;
    assign windex = wptr[ADDR_WIDTH-2:0];
    assign rindex = rptr[ADDR_WIDTH-2:0];

    always_ff@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            wptr <= {ADDR_WIDTH{1'b0}};
        end else if(wen&~full)begin
            wptr <= wptr + {{(ADDR_WIDTH-1){1'b0}},1'b1};
        end
    end
    
    always_ff@(posedge clk)begin
        if(wen&~full)begin
            fifo[windex] <= in_data;
        end
    end

    assign full = (wptr[ADDR_WIDTH-1] ^ rptr[ADDR_WIDTH-1]) & (windex == rindex);

    data_t out_data_buffer;
    logic out_data_valid;
    logic empty_tmp;

    assign empty = ~out_data_valid;
    assign empty_tmp = rptr == wptr;
    assign out_data = out_data_buffer;

    always_ff@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            out_data_buffer <= {DATA_WIDTH{1'b0}};
            rptr <= {ADDR_WIDTH{1'b0}};
        end else if(~empty_tmp & (empty | ~empty&ren))begin
            out_data_buffer <= fifo[rindex];
            rptr <= rptr + {{(ADDR_WIDTH-1){1'b0}},1'b1};
        end
    end

    always_ff@(posedge clk or negedge rstn)begin
        if(~rstn)begin
            out_data_valid <= 1'b0;
        end else if(~empty_tmp)begin
            out_data_valid <= 1'b1;
        end else if(~empty & ren)begin
            out_data_valid <= 1'b0;
        end
    end

endmodule

module AsyncFifo # (
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 8
) (
    input logic rstn,

    input logic rclk,
    input logic ren,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic empty,

    input logic wclk,
    input logic wen,
    input logic [DATA_WIDTH-1:0] in_data,
    output logic full
);
    typedef logic [DATA_WIDTH-1:0] data_t;
    data_t fifo [FIFO_DEPTH-1:0];

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH)+1;
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    addr_t wptr;
    addr_t rptr;

    logic [ADDR_WIDTH-2:0] windex;
    logic [ADDR_WIDTH-2:0] rindex;
    assign windex = wptr[ADDR_WIDTH-2:0];
    assign rindex = rptr[ADDR_WIDTH-2:0];

    always_ff@(posedge wclk or negedge rstn)begin
        if(~rstn)begin
            wptr <= {ADDR_WIDTH{1'b0}};
        end else if(wen&~full)begin
            wptr <= wptr + {{(ADDR_WIDTH-1){1'b0}},1'b1};
        end
    end
    
    always_ff@(posedge wclk)begin
        if(wen&~full)begin
            fifo[windex] <= in_data;
        end
    end

    data_t out_data_buffer;
    logic out_data_valid;
    logic empty_tmp;

    assign empty = ~out_data_valid;
    assign out_data = out_data_buffer;

    always_ff@(posedge rclk or negedge rstn)begin
        if(~rstn)begin
            out_data_buffer <= {DATA_WIDTH{1'b0}};
            rptr <= {ADDR_WIDTH{1'b0}};
        end else if(~empty_tmp & (empty | ~empty&ren))begin
            out_data_buffer <= fifo[rindex];
            rptr <= rptr + {{(ADDR_WIDTH-1){1'b0}},1'b1};
        end
    end

    always_ff@(posedge rclk or negedge rstn)begin
        if(~rstn)begin
            out_data_valid <= 1'b0;
        end else if(~empty_tmp)begin
            out_data_valid <= 1'b1;
        end else if(~empty & ren)begin
            out_data_valid <= 1'b0;
        end
    end

    addr_t rptr_gray;
    addr_t rptr_gray_tmp;
    addr_t wptr_gray;
    addr_t wptr_gray_tmp;
    addr_t rptr_gray_d [1:0];
    addr_t wptr_gray_d [1:0];

    assign wptr_gray_tmp = (wptr >> 1) ^ wptr;
    always_ff@(posedge wclk or negedge rstn)begin
        if(~rstn)begin
            wptr_gray <= {ADDR_WIDTH{1'b0}};
        end else begin
            wptr_gray <= wptr_gray_tmp;
        end
    end

    assign rptr_gray_tmp = (rptr >> 1) ^ rptr;
    always_ff@(posedge rclk or negedge rstn)begin
        if(~rstn)begin
            rptr_gray <= {ADDR_WIDTH{1'b0}};
        end else begin
            rptr_gray <= rptr_gray_tmp;
        end
    end

    always_ff@(posedge wclk or negedge rstn)begin
        if(~rstn)begin
            rptr_gray_d[0] <= {ADDR_WIDTH{1'b0}};
            rptr_gray_d[1] <= {ADDR_WIDTH{1'b0}};
        end else begin
            rptr_gray_d[0] <= rptr_gray;
            rptr_gray_d[1] <= rptr_gray_d[0];
        end
    end

    always_ff@(posedge rclk or negedge rstn)begin
        if(~rstn)begin
            wptr_gray_d[0] <= {ADDR_WIDTH{1'b0}};
            wptr_gray_d[1] <= {ADDR_WIDTH{1'b0}};
        end else begin
            wptr_gray_d[0] <= wptr_gray;
            wptr_gray_d[1] <= wptr_gray_d[0];
        end
    end

    assign empty_tmp = rptr_gray_tmp == wptr_gray_d[1];
    assign full = (~wptr_gray_tmp[ADDR_WIDTH-1:ADDR_WIDTH-2] == rptr_gray_d[1][ADDR_WIDTH-1:ADDR_WIDTH-2]) & 
        (wptr_gray_tmp[ADDR_WIDTH-3:0] == rptr_gray_d[1][ADDR_WIDTH-3:0]);

endmodule

