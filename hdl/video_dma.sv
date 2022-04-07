/*
 * video_dma.sv
 *
 *  Created on: 2022-04-07 15:57
 *      Author: Jack Chen <redchenjs@live.com>
 */

module video_dma #(
    parameter MEM_ADDR_WIDTH = 32,
    parameter MEM_DATA_WIDTH = 32,
    parameter MEM_BURST_LEN = 256,
    parameter FIFO_DEPTH = 512
) (
    input logic clk,
    input logic oclk,
    input logic resetn,

    // config interface: axi4-lite slave
    //
    //    ADDR |31     24|23     16|15      8|7       0|
    //   ------+---------+---------+---------+---------+----
    //    0x00 |    frame start addr (0 = inactive)    | RW
    //   ------+---------+---------+---------+---------+----
    //    0x04 |    y-resolution   |    x-resolution   | RO
    //   ------+---------+---------+---------+---------+----
    input  logic       cfg_axi_awvalid,
    output logic       cfg_axi_awready,
    input  logic [7:0] cfg_axi_awaddr,

    input  logic        cfg_axi_wvalid,
    output logic        cfg_axi_wready,
    input  logic [31:0] cfg_axi_wdata,

    output logic cfg_axi_bvalid,
    input  logic cfg_axi_bready,

    input  logic       cfg_axi_arvalid,
    output logic       cfg_axi_arready,
    input  logic [7:0] cfg_axi_araddr,

    output logic        cfg_axi_rvalid,
    input  logic        cfg_axi_rready,
    output logic [31:0] cfg_axi_rdata,

    // memory interface: axi4 read-only master
    output logic [31:0] mem_axi_araddr,
    output logic  [7:0] mem_axi_arlen,
    output logic  [2:0] mem_axi_arsize,
    output logic  [2:0] mem_axi_arprot,
    output logic  [1:0] mem_axi_arburst,
    output logic        mem_axi_arvalid,
    input  logic        mem_axi_arready,

    input  logic [31:0] mem_axi_rdata,
    input  logic        mem_axi_rvalid,
    output logic        mem_axi_rready,

    output logic        out_axis_tvalid,
    input  logic        out_axis_tready,
    output logic [23:0] out_axis_tdata,
    output logic        out_axis_tuser
);

localparam VIDEO_HOR_PIXELS = 1920;
localparam VIDEO_VER_PIXELS = 1080;

localparam BYTES_PER_PIXEL = 4;
localparam BYTES_PER_BURST = MEM_BURST_LEN * MEM_DATA_WIDTH / 8;

localparam NUM_PIXELS = VIDEO_HOR_PIXELS * VIDEO_VER_PIXELS;
localparam NUM_PIXELS_WIDTH = $clog2(NUM_PIXELS);

localparam NUM_BURSTS = (NUM_PIXELS * BYTES_PER_PIXEL + BYTES_PER_BURST - 1) / BYTES_PER_BURST;
localparam NUM_BURSTS_WIDTH = $clog2(NUM_BURSTS);

localparam NUM_WORDS = MEM_BURST_LEN * NUM_BURSTS;
localparam NUM_WORDS_WIDTH = $clog2(NUM_WORDS);

localparam FIFO_ABITS = $clog2(FIFO_DEPTH);

// iresetn is used in AR logic to make sure that we do not issue mem read requests
// before the clock domain crossing fifo has been fully reset.

logic [3:0] oresetn_q, iresetn_q;
logic oresetn, iresetn;

// synchronize oresetn with oclk
always @(posedge oclk)
    {oresetn, oresetn_q} <= {oresetn_q, resetn};

// synchronize iresetn with clk
always @(posedge clk)
    {iresetn, iresetn_q} <= {iresetn_q, oresetn};

// --------------------------------------------------------------
// Configuration Interface
// --------------------------------------------------------------

logic [31:0] reg_startaddr;
logic [31:0] reg_activeframe;
logic [31:0] reg_resolution;

assign reg_resolution[31:16] = VIDEO_VER_PIXELS, reg_resolution[15:0] = VIDEO_HOR_PIXELS;

assign {cfg_axi_awready, cfg_axi_wready} = {2{resetn && cfg_axi_awvalid && cfg_axi_wvalid && (!cfg_axi_bvalid || cfg_axi_bready)}};
assign cfg_axi_arready = resetn && cfg_axi_arvalid && (!cfg_axi_rvalid || cfg_axi_rready);

always_ff @(posedge clk or negedge resetn)
begin
    if (!resetn) begin
        reg_startaddr <= 0;
        cfg_axi_bvalid <= 0;
        cfg_axi_rvalid <= 0;
    end else begin
        if (cfg_axi_bready) begin
            cfg_axi_bvalid <= 0;
        end

        if (cfg_axi_rready) begin
            cfg_axi_rvalid <= 0;
        end

        if (cfg_axi_awready) begin
            cfg_axi_bvalid <= 1;
            case (cfg_axi_awaddr)
                8'h00: reg_startaddr <= cfg_axi_wdata;
            endcase
        end

        if (cfg_axi_arready) begin
            cfg_axi_rvalid <= 1;
            case (cfg_axi_araddr)
                8'h00: cfg_axi_rdata <= reg_startaddr;
                8'h04: cfg_axi_rdata <= reg_resolution;
                default: cfg_axi_rdata <= {32{1'b0}};
            endcase
        end
    end
end

// --------------------------------------------------------------
// Memory AR channel
// --------------------------------------------------------------

logic [NUM_BURSTS_WIDTH-1:0] ar_burst_count;
logic [3:0] ar_burst_delay;
logic ar_flow_ctrl;

assign mem_axi_arlen = MEM_BURST_LEN-1;
assign mem_axi_arsize = $clog2(MEM_DATA_WIDTH/8);
assign mem_axi_arprot = 0;
assign mem_axi_arburst = 1;

always @(posedge clk) begin
    if (ar_burst_delay)
        ar_burst_delay <= ar_burst_delay-1;
    if (!iresetn || !resetn) begin
        ar_burst_delay <= 0;
        ar_burst_count <= 0;
        mem_axi_araddr <= 0;
        mem_axi_arvalid <= 0;
        reg_activeframe <= 0;
    end else begin
        if (mem_axi_araddr == 0) begin
            mem_axi_araddr <= reg_startaddr;
            reg_activeframe <= reg_startaddr;
        end else begin
            if (mem_axi_arready && mem_axi_arvalid) begin
                mem_axi_arvalid <= 0;
                ar_burst_delay <= 6;
            end else begin
                if (ar_flow_ctrl && !mem_axi_arvalid && !ar_burst_delay) begin
                    mem_axi_arvalid <= 1;

                    if (ar_burst_count == NUM_BURSTS-1) begin
                        ar_burst_count <= 0;
                    end else begin
                        ar_burst_count <= ar_burst_count + 1;
                    end

                    if (ar_burst_count == 0) begin
                        mem_axi_araddr <= reg_startaddr;
                        reg_activeframe <= reg_startaddr;
                        if (!reg_startaddr) begin
                            ar_burst_count <= 0;
                            mem_axi_arvalid <= 0;
                        end
                    end else begin
                        mem_axi_araddr <= mem_axi_araddr + (MEM_BURST_LEN*MEM_DATA_WIDTH/8);
                    end
                end
            end
        end
    end
end


// --------------------------------------------------------------
// Memory R channel and flow control
// --------------------------------------------------------------

logic [NUM_WORDS_WIDTH-1:0] r_word_count;
logic [FIFO_ABITS:0] requested_words;

logic fifo_out_en;
logic fifo_out_first_word;
logic [MEM_DATA_WIDTH-1:0] fifo_out_data;
logic [FIFO_ABITS-1:0] fifo_in_free;
logic [FIFO_ABITS-1:0] fifo_out_avail;

fifo #(
    .WIDTH(MEM_DATA_WIDTH+1),
    .DEPTH(FIFO_DEPTH),
    .ABITS(FIFO_ABITS)
) fifo (
    .in_clk(clk),
    .in_resetn(resetn),
    .in_enable(mem_axi_rvalid && mem_axi_rready),
    .in_data({r_word_count == 0, mem_axi_rdata}),
    .in_free(fifo_in_free),

    .out_clk(oclk),
    .out_resetn(oresetn),
    .out_enable(fifo_out_en),
    .out_data({fifo_out_first_word, fifo_out_data}),
    .out_avail(fifo_out_avail)
);

always_ff @(posedge clk or negedge resetn)
begin
    if (!resetn) begin
        requested_words = 0;
        mem_axi_rready <= 0;
        r_word_count <= 0;
        ar_flow_ctrl <= 0;
    end else begin
        if (mem_axi_arvalid && mem_axi_arready) begin
            requested_words = requested_words + MEM_BURST_LEN;
        end

        if (mem_axi_rvalid && mem_axi_rready) begin
            requested_words = requested_words - 1;
            r_word_count <= r_word_count == NUM_WORDS-1 ? 0 : r_word_count + 1;
        end

        ar_flow_ctrl <= requested_words + MEM_BURST_LEN + 4 < fifo_in_free;
        mem_axi_rready <= fifo_in_free > 4;
    end
end


// --------------------------------------------------------------
// Output stream
// --------------------------------------------------------------

logic [MEM_DATA_WIDTH + 8*BYTES_PER_PIXEL - 9 : 0] outbuf;
logic [7:0] outbuf_bytes;
logic outbuf_framestart;

logic pixel_rd;
logic [NUM_PIXELS_WIDTH:0] pixel_count;
logic [23:0] pixel_data;

always @(posedge oclk or negedge oresetn)
begin
    if (!oresetn) begin
        outbuf_bytes = 0;
        pixel_count <= NUM_PIXELS;
        fifo_out_en <= 0;
    end else begin
        outbuf = outbuf;
        outbuf_bytes = outbuf_bytes;
        fifo_out_en <= 0;

        if (fifo_out_avail && outbuf_bytes < BYTES_PER_PIXEL && (!fifo_out_first_word || pixel_count >= NUM_PIXELS-1)) begin
            for (integer i = 0; i < BYTES_PER_PIXEL; i = i+1) begin
                if (outbuf_bytes == i || (!i && fifo_out_first_word)) begin
                    outbuf = (fifo_out_data << (8*i)) | (outbuf & ~(~0 << (8*i)));
                    outbuf_bytes = MEM_DATA_WIDTH/8 + i;
                    fifo_out_en <= 1;
                end
            end

            outbuf_framestart = fifo_out_first_word;
        end

        if (pixel_rd) begin
            pixel_data <= outbuf;
            if (outbuf_framestart || pixel_count > ((NUM_WORDS*(MEM_DATA_WIDTH/8) + BYTES_PER_PIXEL - 1) / BYTES_PER_PIXEL)) begin
                pixel_count <= 0;
            end else begin
                pixel_count <= pixel_count + 1;
            end

            outbuf_bytes = outbuf_bytes < BYTES_PER_PIXEL ? 0 : outbuf_bytes - BYTES_PER_PIXEL;
            outbuf = outbuf >> (8*BYTES_PER_PIXEL);
            outbuf_framestart = 0;
        end
    end
end

assign pixel_rd = out_axis_tready;
assign out_axis_tvalid = pixel_count < NUM_PIXELS;
assign out_axis_tdata = pixel_data;
assign out_axis_tuser = !pixel_count;

endmodule

module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 12,
    parameter ABITS = 4
) (
    input  logic             in_clk,
    input  logic             in_resetn,
    input  logic             in_enable,
    input  logic [WIDTH-1:0] in_data,
    output logic [ABITS-1:0] in_free,

    input  logic             out_clk,
    input  logic             out_resetn,
    input  logic             out_enable,
    output logic [WIDTH-1:0] out_data,
    output logic [ABITS-1:0] out_avail
);

logic [WIDTH-1:0] fifo [0:DEPTH-1];
logic [ABITS-1:0] in_ptr, in_ptr_gray;
logic [ABITS-1:0] out_ptr, out_ptr_gray;

logic [ABITS-1:0] out_ptr_for_in_clk, in_ptr_for_out_clk;
logic [ABITS-1:0] sync_in_ptr_0, sync_out_ptr_0;
logic [ABITS-1:0] sync_in_ptr_1, sync_out_ptr_1;
logic [ABITS-1:0] sync_in_ptr_2, sync_out_ptr_2;

function [ABITS-1:0] bin2gray(input [ABITS-1:0] in);
    logic [ABITS:0] temp;
    begin
        temp = in;
        for (integer i = 0; i < ABITS; i++) begin
            bin2gray[i] = ^temp[i +: 2];
        end
    end
endfunction

function [ABITS-1:0] gray2bin(input [ABITS-1:0] in);
    begin
        for (integer i = 0; i < ABITS; i++) begin
            gray2bin[i] = ^(in >> i);
        end
    end
endfunction

always_ff @(posedge in_clk) begin
    if (!in_resetn) begin
        in_ptr <= 0;
        in_ptr_gray <= 0;
    end else begin
        if (in_enable) begin
            fifo[in_ptr] <= in_data;
            in_ptr <= in_ptr + 1'b1;
            in_ptr_gray <= bin2gray(in_ptr + 1'b1);
        end
    end

    sync_out_ptr_0 <= out_ptr_gray;
    sync_out_ptr_1 <= sync_out_ptr_0;
    sync_out_ptr_2 <= sync_out_ptr_1;
    out_ptr_for_in_clk <= gray2bin(sync_out_ptr_2);

    in_free <= DEPTH - in_ptr + out_ptr_for_in_clk - 1;
end

always_ff @(posedge out_clk) begin
    if (!out_resetn) begin
        out_ptr <= 0;
        out_ptr_gray <= 0;
    end else begin
        if (out_enable) begin
            out_ptr <= out_ptr + 1'b1;
            out_ptr_gray <= bin2gray(out_ptr + 1'b1);
            out_data <= fifo[out_ptr + 1'b1];
        end else begin
            out_data <= fifo[out_ptr];
        end
    end

    sync_in_ptr_0 <= in_ptr_gray;
    sync_in_ptr_1 <= sync_in_ptr_0;
    sync_in_ptr_2 <= sync_in_ptr_1;
    in_ptr_for_out_clk <= gray2bin(sync_in_ptr_2);

    out_avail <= in_ptr_for_out_clk - out_ptr;
end

endmodule
