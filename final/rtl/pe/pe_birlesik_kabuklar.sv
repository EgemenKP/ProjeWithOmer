// =============================================================================
//  pe_birlesik_kabuklar.sv — YALNIZCA TEST: Egemen'in PE testbench'lerini (tb_pe_*.sv)
//  DEĞİŞTİRMEDEN birleşik PE'yle (pe_birlesik.v, D69) koşturmak için kabuklar.
//  Modül adları ve portları Egemen'in beş modülüyle aynı; her kabuk pe_birlesik'i sabit bir
//  modla çalıştırır. Bu dosya Egemen'in pe_chain3.v, pe_fp_s2.v, pe_bp_s2.v, pe_wg_s1.v,
//  pe_wg_s2.v dosyalarıyla AYNI derlemeye eklenmemeli (aynı modül adları); rtl/pe/run_sim.tcl
//  iki ayrı koşu yapar: önce asıllar, sonra bu kabuklar.
//  pe_chain3 kabuğu FP s1 modunu (0) kullanır; BP s1 (2) birleşik PE'de aynı yolu seçer.
//  Yazan: Claude, 03.11.2026 (pe_sarmalayici_simler.sv'nin birleşik PE'ye uyarlanmışı)
// =============================================================================
`timescale 1ns/1ps
module pe_chain3 (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] x_row0, x_row1, x_row2,
    input wire signed [31:0] ps_in,
    output wire signed [31:0] psum_out);
    wire [127:0] c; wire [287:0] g;
    pe_birlesik u (.clk(clk), .rst(1'b0), .mod(3'd0),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({x_row2, x_row1, x_row0}), .akis2(24'd0), .akis3(24'd0),
        .ps_flat({96'd0, ps_in}), .cikis_flat(c), .g_flat(g));
    assign psum_out = c[31:0];
endmodule

module pe_fp_s2 (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] cift_r0, tek_r0, cift_r1, tek_r1, cift_r2, tek_r2,
    input wire signed [31:0] ps_in,
    output wire signed [31:0] psum_out);
    wire [127:0] c; wire [287:0] g;
    pe_birlesik u (.clk(clk), .rst(1'b0), .mod(3'd1),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({cift_r2, cift_r1, cift_r0}), .akis2({tek_r2, tek_r1, tek_r0}), .akis3(24'd0),
        .ps_flat({96'd0, ps_in}), .cikis_flat(c), .g_flat(g));
    assign psum_out = c[31:0];
endmodule

module pe_bp_s2 (
    input wire clk,
    input wire signed [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,
    input wire signed [7:0] e_row0, e_row1, e_row2,
    input wire signed [31:0] psA0, psB0, psA1, psB1,
    output wire signed [31:0] out0, out1, out2, out3);
    wire [127:0] c; wire [287:0] g;
    pe_birlesik u (.clk(clk), .rst(1'b0), .mod(3'd3),
        .w_flat({w22, w21, w20, w12, w11, w10, w02, w01, w00}),
        .akis1({e_row2, e_row1, e_row0}), .akis2(24'd0), .akis3(24'd0),
        .ps_flat({psB1, psA1, psB0, psA0}), .cikis_flat(c), .g_flat(g));
    assign {out3, out2, out1, out0} = c;
endmodule

module pe_wg_s1 (
    input wire clk, input wire rst,
    input wire signed [7:0] a_row0, e_row0, a_row1, e_row1, a_row2, e_row2,
    output wire signed [31:0] g00, g01, g02, g10, g11, g12, g20, g21, g22);
    wire [127:0] c; wire [287:0] g;
    pe_birlesik u (.clk(clk), .rst(rst), .mod(3'd4), .w_flat(72'd0),
        .akis1({a_row2, a_row1, a_row0}), .akis2({e_row2, e_row1, e_row0}), .akis3(24'd0),
        .ps_flat(128'd0), .cikis_flat(c), .g_flat(g));
    assign {g22, g21, g20, g12, g11, g10, g02, g01, g00} = g;
endmodule

module pe_wg_s2 (
    input wire clk, input wire rst,
    input wire signed [7:0] cift_r0, tek_r0, e_row0, cift_r1, tek_r1, e_row1, cift_r2, tek_r2, e_row2,
    output wire signed [31:0] g00, g01, g02, g10, g11, g12, g20, g21, g22);
    wire [127:0] c; wire [287:0] g;
    pe_birlesik u (.clk(clk), .rst(rst), .mod(3'd5), .w_flat(72'd0),
        .akis1({cift_r2, cift_r1, cift_r0}), .akis2({tek_r2, tek_r1, tek_r0}), .akis3({e_row2, e_row1, e_row0}),
        .ps_flat(128'd0), .cikis_flat(c), .g_flat(g));
    assign {g22, g21, g20, g12, g11, g10, g02, g01, g00} = g;
endmodule
