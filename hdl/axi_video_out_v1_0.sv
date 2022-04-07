/*
 * axi_video_out_v1_0.sv
 *
 *  Created on: 2022-04-04 16:53
 *      Author: Jack Chen <redchenjs@live.com>
 */

`timescale 1 ns / 1 ps

`include "svo/svo_defines.vh"

module axi_video_out_v1_0(
    input logic s_axi_aclk,
    input logic s_axi_aresetn,

    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic s_axi_bvalid,
    input  logic s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input logic m_axi_aclk,
    input logic m_axi_aresetn,

    output logic [31:0] m_axi_araddr,
    output logic  [7:0] m_axi_arlen,
    output logic  [2:0] m_axi_arsize,
    output logic  [1:0] m_axi_arburst,
    output logic  [2:0] m_axi_arprot,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    input logic tmds_pclk,
    input logic tmds_pclk_5x,

    output logic       tmds_clk_p,
    output logic       tmds_clk_n,
    output logic [2:0] tmds_data_p,
    output logic [2:0] tmds_data_n
);

localparam SVO_MODE           = "1920x1080R3";
localparam SVO_FRAMERATE      = 60;
localparam SVO_BITS_PER_PIXEL = 24;
localparam SVO_BITS_PER_RED   = 8;
localparam SVO_BITS_PER_GREEN = 8;
localparam SVO_BITS_PER_BLUE  = 8;
localparam SVO_BITS_PER_ALPHA = 0;

logic tmds_pclk_rst_n;

logic                          mem_axis_tvalid;
logic                          mem_axis_tready;
logic [SVO_BITS_PER_PIXEL-1:0] mem_axis_tdata;
logic                    [0:0] mem_axis_tuser;

logic                          video_enc_tvalid;
logic                          video_enc_tready;
logic [SVO_BITS_PER_PIXEL-1:0] video_enc_tdata;
logic                    [3:0] video_enc_tuser;

logic [2:0] tmds_d0, tmds_d1, tmds_d2, tmds_d3, tmds_d4;
logic [2:0] tmds_d5, tmds_d6, tmds_d7, tmds_d8, tmds_d9;

assign video_enc_tready = 1'b1;

rst_syn tmds_pclk_rst_syn(
    .clk_i(m_axi_aclk),
    .rst_n_i(m_axi_aresetn),
    .rst_n_o(tmds_pclk_rst_n)
);

video_dma #(
    .MEM_ADDR_WIDTH(32),
    .MEM_DATA_WIDTH(32),
    .MEM_BURST_LEN(256),
    .FIFO_DEPTH(512)
) video_dma (
    .clk(m_axi_aclk),
    .oclk(tmds_pclk),
    .resetn(m_axi_aresetn),

    .cfg_axi_awvalid(s_axi_awvalid),
    .cfg_axi_awready(s_axi_awready),
    .cfg_axi_awaddr(s_axi_awaddr),

    .cfg_axi_wvalid(s_axi_wvalid),
    .cfg_axi_wready(s_axi_wready),
    .cfg_axi_wdata(s_axi_wdata),

    .cfg_axi_bvalid(s_axi_bvalid),
    .cfg_axi_bready(s_axi_bready),

    .cfg_axi_arvalid(s_axi_arvalid),
    .cfg_axi_arready(s_axi_arready),
    .cfg_axi_araddr(s_axi_araddr),

    .cfg_axi_rvalid(s_axi_rvalid),
    .cfg_axi_rready(s_axi_rready),
    .cfg_axi_rdata(s_axi_rdata),

    .mem_axi_araddr(m_axi_araddr),
    .mem_axi_arlen(m_axi_arlen),
    .mem_axi_arsize(m_axi_arsize),
    .mem_axi_arprot(m_axi_arprot),
    .mem_axi_arburst(m_axi_arburst),
    .mem_axi_arvalid(m_axi_arvalid),
    .mem_axi_arready(m_axi_arready),

    .mem_axi_rdata(m_axi_rdata),
    .mem_axi_rvalid(m_axi_rvalid),
    .mem_axi_rready(m_axi_rready),

    .out_axis_tvalid(mem_axis_tvalid),
    .out_axis_tready(mem_axis_tready),
    .out_axis_tdata(mem_axis_tdata),
    .out_axis_tuser(mem_axis_tuser)
);

svo_enc #(
    `SVO_PASS_PARAMS
) svo_enc (
    .clk(tmds_pclk),
    .resetn(tmds_pclk_rst_n),

    .in_axis_tvalid(mem_axis_tvalid),
    .in_axis_tready(mem_axis_tready),
    .in_axis_tdata(mem_axis_tdata),
    .in_axis_tuser(mem_axis_tuser),

    .out_axis_tvalid(video_enc_tvalid),
    .out_axis_tready(video_enc_tready),
    .out_axis_tdata(video_enc_tdata),
    .out_axis_tuser(video_enc_tuser)
);

svo_tmds svo_tmds_b(
    .clk(tmds_pclk),
    .resetn(tmds_pclk_rst_n),
    .de(!video_enc_tuser[3]),
    .ctrl(video_enc_tuser[2:1]),
    .din(video_enc_tdata[7:0]),
    .dout({tmds_d9[0], tmds_d8[0], tmds_d7[0], tmds_d6[0], tmds_d5[0],
           tmds_d4[0], tmds_d3[0], tmds_d2[0], tmds_d1[0], tmds_d0[0]})
);

svo_tmds svo_tmds_g(
    .clk(tmds_pclk),
    .resetn(tmds_pclk_rst_n),
    .de(!video_enc_tuser[3]),
    .ctrl(2'b0),
    .din(video_enc_tdata[15:8]),
    .dout({tmds_d9[1], tmds_d8[1], tmds_d7[1], tmds_d6[1], tmds_d5[1],
           tmds_d4[1], tmds_d3[1], tmds_d2[1], tmds_d1[1], tmds_d0[1]})
);

svo_tmds svo_tmds_r(
    .clk(tmds_pclk),
    .resetn(tmds_pclk_rst_n),
    .de(!video_enc_tuser[3]),
    .ctrl(2'b0),
    .din(video_enc_tdata[23:16]),
    .dout({tmds_d9[2], tmds_d8[2], tmds_d7[2], tmds_d6[2], tmds_d5[2],
           tmds_d4[2], tmds_d3[2], tmds_d2[2], tmds_d1[2], tmds_d0[2]})
);

video_out video_out(
    .clk_i(tmds_pclk),
    .rst_n_i(tmds_pclk_rst_n),

    .clk_5x_i(tmds_pclk_5x),

    .tmds_d0_i(tmds_d0),
    .tmds_d1_i(tmds_d1),
    .tmds_d2_i(tmds_d2),
    .tmds_d3_i(tmds_d3),
    .tmds_d4_i(tmds_d4),
    .tmds_d5_i(tmds_d5),
    .tmds_d6_i(tmds_d6),
    .tmds_d7_i(tmds_d7),
    .tmds_d8_i(tmds_d8),
    .tmds_d9_i(tmds_d9),

    .tmds_clk_o_p(tmds_clk_p),
    .tmds_clk_o_n(tmds_clk_n),
    .tmds_data_o_p(tmds_data_p),
    .tmds_data_o_n(tmds_data_n)
);

endmodule
