/*
 * video_out.sv
 *
 *  Created on: 2022-03-03 15:55
 *      Author: Jack Chen <redchenjs@live.com>
 */

module video_out(
    input logic clk_i,
    input logic rst_n_i,

    input logic clk_5x_i,

    input logic [2:0] tmds_d0_i,
    input logic [2:0] tmds_d1_i,
    input logic [2:0] tmds_d2_i,
    input logic [2:0] tmds_d3_i,
    input logic [2:0] tmds_d4_i,
    input logic [2:0] tmds_d5_i,
    input logic [2:0] tmds_d6_i,
    input logic [2:0] tmds_d7_i,
    input logic [2:0] tmds_d8_i,
    input logic [2:0] tmds_d9_i,

    output logic       tmds_clk_o_p,
    output logic       tmds_clk_o_n,
    output logic [2:0] tmds_data_o_p,
    output logic [2:0] tmds_data_o_n
);

logic [2:0] tmds_data;

logic [2:0] shiftout1;
logic [2:0] shiftout2;

OSERDESE2 #(
    .DATA_RATE_OQ("DDR"),
    .DATA_RATE_TQ("DDR"),
    .DATA_WIDTH(10),
    .INIT_OQ(1'b0),
    .INIT_TQ(1'b0),
    .SERDES_MODE("MASTER"),
    .SRVAL_OQ(1'b0),
    .SRVAL_TQ(1'b0),
    .TBYTE_CTL("FALSE"),
    .TBYTE_SRC("FALSE"),
    .TRISTATE_WIDTH(1)
) OSERDES_M [2:0] (
    .OFB(),
    .OQ(tmds_data),
    .SHIFTOUT1(),
    .SHIFTOUT2(),
    .TBYTEOUT(),
    .TFB(),
    .TQ(),
    .CLK(clk_5x_i),
    .CLKDIV(clk_i),
    .D1(tmds_d0_i),
    .D2(tmds_d1_i),
    .D3(tmds_d2_i),
    .D4(tmds_d3_i),
    .D5(tmds_d4_i),
    .D6(tmds_d5_i),
    .D7(tmds_d6_i),
    .D8(tmds_d7_i),
    .OCE(1'b1),
    .RST(~rst_n_i),
    .SHIFTIN1(shiftout1),
    .SHIFTIN2(shiftout2),
    .T1(1'b0),
    .T2(1'b0),
    .T3(1'b0),
    .T4(1'b0),
    .TBYTEIN(1'b0),
    .TCE(1'b0)
);

OSERDESE2 #(
    .DATA_RATE_OQ("DDR"),
    .DATA_RATE_TQ("DDR"),
    .DATA_WIDTH(10),
    .INIT_OQ(1'b0),
    .INIT_TQ(1'b0),
    .SERDES_MODE("SLAVE"),
    .SRVAL_OQ(1'b0),
    .SRVAL_TQ(1'b0),
    .TBYTE_CTL("FALSE"),
    .TBYTE_SRC("FALSE"),
    .TRISTATE_WIDTH(1)
) OSERDES_S [2:0] (
    .OFB(),
    .OQ(),
    .SHIFTOUT1(shiftout1),
    .SHIFTOUT2(shiftout2),
    .TBYTEOUT(),
    .TFB(),
    .TQ(),
    .CLK(clk_5x_i),
    .CLKDIV(clk_i),
    .D1(1'b0),
    .D2(1'b0),
    .D3(tmds_d8_i),
    .D4(tmds_d9_i),
    .D5(1'b0),
    .D6(1'b0),
    .D7(1'b0),
    .D8(1'b0),
    .OCE(1'b1),
    .RST(~rst_n_i),
    .SHIFTIN1(1'b0),
    .SHIFTIN2(1'b0),
    .T1(1'b0),
    .T2(1'b0),
    .T3(1'b0),
    .T4(1'b0),
    .TBYTEIN(1'b0),
    .TCE(1'b0)
);         

OBUFDS #(
    .IOSTANDARD("TMDS_33"),
    .SLEW("FAST")
) OBUFDS [3:0] (
    .I({clk_i, tmds_data}),
    .O({tmds_clk_o_p, tmds_data_o_p}),
    .OB({tmds_clk_o_n, tmds_data_o_n})
);

endmodule
