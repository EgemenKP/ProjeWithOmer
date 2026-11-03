// =============================================================================
//  pe_sarmalayici.v — Egemen'in beş PE devresini tek bir mod girişiyle seçen sarmalayıcı
// -----------------------------------------------------------------------------
//  Adım 4, arayüz sözleşmesi Bölüm 5. Egemen'in modülleri DEĞİŞMEDEN kullanılıyor:
//    pe_chain3 (FP s1 ve BP s1), pe_fp_s2, pe_bp_s2, pe_wg_s1, pe_wg_s2
//  Not: Shao'nun PE'si 6 deseni aynı 9 MAC'le yapıyor; burada 5 ayrı devre var (45 MAC).
//  İşlev aynı; tek PE'ye indirgemek Adım 5'te Egemen'le konuşulacak (INCELEME_03_11 Bölüm 5).
//
//  Seçilmeyen devrelerin girişleri 0'a çekiliyor: böylece WG akümülatörleri başka bir mod
//  çalışırken değişmiyor (0 · 0 eklenir) ve kullanılmayan devreler boşuna anahtarlanmıyor.
//  Sarmalayıcı kayıt eklemiyor; çıkış gecikmeleri Egemen'in modülleriyle aynı (D16:
//  FP s1, BP s1, FP s2'de 2 çevrim kayma, BP s2'de 1).
//  Yazan: Claude, 03.11.2026
//
//  Portlar (veriler işaretli, ikiye tümleyen):
//    clk, rst      : saat; rst eşzamanlı, aktif-yüksek, yalnızca WG akümülatörlerini sıfırlar
//                    (seçili WG devresine gider)
//    mod     [2:0] : 0 FP s1, 1 FP s2, 2 BP s1, 3 BP s2, 4 WG s1, 5 WG s2 (6, 7: hiçbiri)
//    w_flat  [71:0]: 9 ağırlık, w[i][j] = w_flat[(3i+j)*8 +: 8]. BP s1'de 180° döndürülmüş,
//                    BP s2'de Fig. 4(b) düzeninde verilir (ön-getirmenin işi, golden: yorumla())
//    akis1   [23:0]: satır r'nin 1. akışı ([8r +: 8]):
//                    FP s1 / BP s1: x_row · FP s2 / WG s2: çift · BP s2: e_row · WG s1: a_row
//    akis2   [23:0]: satır r'nin 2. akışı: FP s2 / WG s2: tek · WG s1: e_row · diğerleri: kullanılmaz
//    akis3   [23:0]: satır r'nin 3. akışı: WG s2: e_row · diğerleri: kullanılmaz
//    ps_flat [127:0]: kısmi toplam girişleri ([32k +: 32]): FP s1, BP s1, FP s2: k=0 ps_in;
//                    BP s2: k=0 psA0, 1 psB0, 2 psA1, 3 psB1; WG: kullanılmaz
//    cikis_flat[127:0]: FP s1, BP s1, FP s2: k=0 psum_out (diğerleri 0); BP s2: k=0..3 out0..out3;
//                    WG: 0
//    g_flat  [287:0]: WG s1 / WG s2: 9 akümülatör, g[i][j] = g_flat[(3i+j)*32 +: 32]; diğer modlar: 0
// =============================================================================
`timescale 1ns/1ps

module pe_sarmalayici (
    input  wire          clk,
    input  wire          rst,
    input  wire [2:0]    mod,
    input  wire [71:0]   w_flat,
    input  wire [23:0]   akis1,
    input  wire [23:0]   akis2,
    input  wire [23:0]   akis3,
    input  wire [127:0]  ps_flat,
    output wire [127:0]  cikis_flat,
    output wire [287:0]  g_flat
);

    localparam FP_S1 = 3'd0, FP_S2 = 3'd1, BP_S1 = 3'd2, BP_S2 = 3'd3, WG_S1 = 3'd4, WG_S2 = 3'd5;

    wire s_chain = (mod == FP_S1) || (mod == BP_S1);
    wire s_fp2   = (mod == FP_S2);
    wire s_bp2   = (mod == BP_S2);
    wire s_wg1   = (mod == WG_S1);
    wire s_wg2   = (mod == WG_S2);

    // Seçilmeyen devreye 0 ver
    function [71:0] kapi72;  input s; input [71:0] v;  kapi72 = s ? v : 72'd0;  endfunction
    function [23:0] kapi24;  input s; input [23:0] v;  kapi24 = s ? v : 24'd0;  endfunction
    function [127:0] kapi128; input s; input [127:0] v; kapi128 = s ? v : 128'd0; endfunction

    // ---------------- pe_chain3: FP s1 ve BP s1 ----------------
    wire [71:0]  w_c  = kapi72(s_chain, w_flat);
    wire [23:0]  x_c  = kapi24(s_chain, akis1);
    wire [127:0] p_c  = kapi128(s_chain, ps_flat);
    wire signed [31:0] c_out;
    pe_chain3 u_chain3 (
        .clk(clk),
        .w00(w_c[0*8 +: 8]), .w01(w_c[1*8 +: 8]), .w02(w_c[2*8 +: 8]),
        .w10(w_c[3*8 +: 8]), .w11(w_c[4*8 +: 8]), .w12(w_c[5*8 +: 8]),
        .w20(w_c[6*8 +: 8]), .w21(w_c[7*8 +: 8]), .w22(w_c[8*8 +: 8]),
        .x_row0(x_c[0 +: 8]), .x_row1(x_c[8 +: 8]), .x_row2(x_c[16 +: 8]),
        .ps_in(p_c[0 +: 32]),
        .psum_out(c_out)
    );

    // ---------------- pe_fp_s2 ----------------
    wire [71:0]  w_f  = kapi72(s_fp2, w_flat);
    wire [23:0]  c_f  = kapi24(s_fp2, akis1);
    wire [23:0]  t_f  = kapi24(s_fp2, akis2);
    wire [127:0] p_f  = kapi128(s_fp2, ps_flat);
    wire signed [31:0] f_out;
    pe_fp_s2 u_fp_s2 (
        .clk(clk),
        .w00(w_f[0*8 +: 8]), .w01(w_f[1*8 +: 8]), .w02(w_f[2*8 +: 8]),
        .w10(w_f[3*8 +: 8]), .w11(w_f[4*8 +: 8]), .w12(w_f[5*8 +: 8]),
        .w20(w_f[6*8 +: 8]), .w21(w_f[7*8 +: 8]), .w22(w_f[8*8 +: 8]),
        .cift_r0(c_f[0 +: 8]),  .tek_r0(t_f[0 +: 8]),
        .cift_r1(c_f[8 +: 8]),  .tek_r1(t_f[8 +: 8]),
        .cift_r2(c_f[16 +: 8]), .tek_r2(t_f[16 +: 8]),
        .ps_in(p_f[0 +: 32]),
        .psum_out(f_out)
    );

    // ---------------- pe_bp_s2 ----------------
    wire [71:0]  w_b  = kapi72(s_bp2, w_flat);
    wire [23:0]  e_b  = kapi24(s_bp2, akis1);
    wire [127:0] p_b  = kapi128(s_bp2, ps_flat);
    wire signed [31:0] b_o0, b_o1, b_o2, b_o3;
    pe_bp_s2 u_bp_s2 (
        .clk(clk),
        .w00(w_b[0*8 +: 8]), .w01(w_b[1*8 +: 8]), .w02(w_b[2*8 +: 8]),
        .w10(w_b[3*8 +: 8]), .w11(w_b[4*8 +: 8]), .w12(w_b[5*8 +: 8]),
        .w20(w_b[6*8 +: 8]), .w21(w_b[7*8 +: 8]), .w22(w_b[8*8 +: 8]),
        .e_row0(e_b[0 +: 8]), .e_row1(e_b[8 +: 8]), .e_row2(e_b[16 +: 8]),
        .psA0(p_b[0 +: 32]), .psB0(p_b[32 +: 32]), .psA1(p_b[64 +: 32]), .psB1(p_b[96 +: 32]),
        .out0(b_o0), .out1(b_o1), .out2(b_o2), .out3(b_o3)
    );

    // ---------------- pe_wg_s1 ----------------
    wire [23:0]  a_w1 = kapi24(s_wg1, akis1);
    wire [23:0]  e_w1 = kapi24(s_wg1, akis2);
    wire [287:0] g1;
    pe_wg_s1 u_wg_s1 (
        .clk(clk), .rst(rst & s_wg1),
        .a_row0(a_w1[0 +: 8]),  .e_row0(e_w1[0 +: 8]),
        .a_row1(a_w1[8 +: 8]),  .e_row1(e_w1[8 +: 8]),
        .a_row2(a_w1[16 +: 8]), .e_row2(e_w1[16 +: 8]),
        .g00(g1[0*32 +: 32]), .g01(g1[1*32 +: 32]), .g02(g1[2*32 +: 32]),
        .g10(g1[3*32 +: 32]), .g11(g1[4*32 +: 32]), .g12(g1[5*32 +: 32]),
        .g20(g1[6*32 +: 32]), .g21(g1[7*32 +: 32]), .g22(g1[8*32 +: 32])
    );

    // ---------------- pe_wg_s2 ----------------
    wire [23:0]  c_w2 = kapi24(s_wg2, akis1);
    wire [23:0]  t_w2 = kapi24(s_wg2, akis2);
    wire [23:0]  e_w2 = kapi24(s_wg2, akis3);
    wire [287:0] g2;
    pe_wg_s2 u_wg_s2 (
        .clk(clk), .rst(rst & s_wg2),
        .cift_r0(c_w2[0 +: 8]),  .tek_r0(t_w2[0 +: 8]),  .e_row0(e_w2[0 +: 8]),
        .cift_r1(c_w2[8 +: 8]),  .tek_r1(t_w2[8 +: 8]),  .e_row1(e_w2[8 +: 8]),
        .cift_r2(c_w2[16 +: 8]), .tek_r2(t_w2[16 +: 8]), .e_row2(e_w2[16 +: 8]),
        .g00(g2[0*32 +: 32]), .g01(g2[1*32 +: 32]), .g02(g2[2*32 +: 32]),
        .g10(g2[3*32 +: 32]), .g11(g2[4*32 +: 32]), .g12(g2[5*32 +: 32]),
        .g20(g2[6*32 +: 32]), .g21(g2[7*32 +: 32]), .g22(g2[8*32 +: 32])
    );

    // ---------------- çıkış seçimi ----------------
    assign cikis_flat = s_chain ? {96'd0, c_out} :
                        s_fp2   ? {96'd0, f_out} :
                        s_bp2   ? {b_o3, b_o2, b_o1, b_o0} :
                                  128'd0;
    assign g_flat     = s_wg1 ? g1 :
                        s_wg2 ? g2 :
                                288'd0;

endmodule
