// =============================================================================
//  pe_sarmalayici_simler.sv — YALNIZCA TEST: Egemen'in PE testbench'lerini sarmalayıcıyla
//  koşturmak için, onun modülleriyle aynı portlara sahip ince kabuklar. Her kabuk
//  pe_sarmalayici'yi sabit bir modla çalıştırır. Testbench kopyalarında yalnızca modül adı
//  değiştirilir (ör. pe_chain3 -> sim_chain3). Yazan: Claude, 03.11.2026
// =============================================================================
`timescale 1ns/1ps
module sim_chain3 #(parameter MOD = 0) (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] x_row0, x_row1, x_row2,
    input wire signed [31:0] ps_in,
    output wire signed [31:0] psum_out);
    wire [127:0] c; wire [287:0] g;
    pe_sarmalayici u (.clk(clk), .rst(1'b0), .mod(MOD[2:0]),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({x_row2, x_row1, x_row0}), .akis2(24'd0), .akis3(24'd0),
        .ps_flat({96'd0, ps_in}), .cikis_flat(c), .g_flat(g));
    assign psum_out = c[31:0];
endmodule

module sim_fp_s2 (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] cift_r0, tek_r0, cift_r1, tek_r1, cift_r2, tek_r2,
    input wire signed [31:0] ps_in,
    output wire signed [31:0] psum_out);
    wire [127:0] c; wire [287:0] g;
    pe_sarmalayici u (.clk(clk), .rst(1'b0), .mod(3'd1),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({cift_r2, cift_r1, cift_r0}), .akis2({tek_r2, tek_r1, tek_r0}), .akis3(24'd0),
        .ps_flat({96'd0, ps_in}), .cikis_flat(c), .g_flat(g));
    assign psum_out = c[31:0];
endmodule

module sim_bp_s2 (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] e_row0, e_row1, e_row2,
    input wire signed [31:0] psA0, psB0, psA1, psB1,
    output wire signed [31:0] out0, out1, out2, out3);
    wire [127:0] c; wire [287:0] g;
    pe_sarmalayici u (.clk(clk), .rst(1'b0), .mod(3'd3),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({e_row2, e_row1, e_row0}), .akis2(24'd0), .akis3(24'd0),
        .ps_flat({psB1, psA1, psB0, psA0}), .cikis_flat(c), .g_flat(g));
    assign {out3, out2, out1, out0} = c;
endmodule

module sim_wg_s1 (
    input wire clk, input wire rst,
    input wire signed [7:0] a_row0, e_row0, a_row1, e_row1, a_row2, e_row2,
    output wire signed [31:0] g00, g01, g02, g10, g11, g12, g20, g21, g22);
    wire [127:0] c; wire [287:0] g;
    pe_sarmalayici u (.clk(clk), .rst(rst), .mod(3'd4), .w_flat(72'd0),
        .akis1({a_row2, a_row1, a_row0}), .akis2({e_row2, e_row1, e_row0}), .akis3(24'd0),
        .ps_flat(128'd0), .cikis_flat(c), .g_flat(g));
    assign {g22, g21, g20, g12, g11, g10, g02, g01, g00} = g;
endmodule

module sim_wg_s2 (
    input wire clk, input wire rst,
    input wire signed [7:0] cift_r0, tek_r0, e_row0, cift_r1, tek_r1, e_row1, cift_r2, tek_r2, e_row2,
    output wire signed [31:0] g00, g01, g02, g10, g11, g12, g20, g21, g22);
    wire [127:0] c; wire [287:0] g;
    pe_sarmalayici u (.clk(clk), .rst(rst), .mod(3'd5), .w_flat(72'd0),
        .akis1({cift_r2, cift_r1, cift_r0}), .akis2({tek_r2, tek_r1, tek_r0}), .akis3({e_row2, e_row1, e_row0}),
        .ps_flat(128'd0), .cikis_flat(c), .g_flat(g));
    assign {g22, g21, g20, g12, g11, g10, g02, g01, g00} = g;
endmodule
