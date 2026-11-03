// =============================================================================
//  grup_kurucu.v — Dizinin çıkışlarından satır başına SRU grubu kurar (Adım 5b, D76)
// -----------------------------------------------------------------------------
//  Shao Fig. 8: her PE satırının çıkışları satırın sonundaki SRU'ya gider. III-B: PE'ler "a group
//  of int32 output data" üretir. D76: satır i'nin grubu, sütunlardan birer değer (en çok 16):
//    FP / BP : PE'nin şeridi `sec` (0..3; FP/BP s1'de 0, BP s2'de dX konumuna göre)
//    WG      : PE'nin akümülatörü `sec` (0..8 = 3ki + kj)
//  n_sutun'dan sonraki sütunlar 0 verilir (LMS'in yerel maksimumu yalnızca dolu sütunlardan).
//
//  Son grup bekletme (D64 A4'ün dizi hâli): sru_channel son grubu last_group = 1 ile ister ve
//  sru_array bütün kanalların last_group'unu aynı çevrimde varsayar (paylaşılan G). Satırların grup
//  sayıları farklı olabildiği için (BP s2'de dolgu, D52; boş satırlar) her satırın en son grubu bir
//  kayıtta bekletilir: yeni grup gelince bekleyen SRU'ya itilir (last_group = 0), `son_it`'te
//  bekleyenlerin hepsi aynı çevrimde last_group = 1 ile itilir. Hiç grubu olmayan satır itilmez.
//  kur ve son_it aynı çevrimde verilmemeli.
//
//  Portlar:
//    clk, rst        : saat; rst bekleyen grupları siler (İŞ_BAŞLA'da)
//    cikis_flat, g_flat : pe_dizi'nin çıkışları (PE (i, j): indis i*C + j)
//    kur             : bu çevrimde satir_maske'deki satırların grubu kurulur
//    akum_mi         : 1 ise grup g_flat'tan (WG), 0 ise cikis_flat'tan
//    sec [3:0]       : şerit (0..3) ya da akümülatör (0..8)
//    satir_maske [R] : grubu olan satırlar
//    n_sutun [4:0]   : grubun boyu (1..16)
//    son_it          : bekleyen bütün grupları last_group ile it
//    push_group_all, group_in_flat_all, group_n_all, last_group_all : sru_array'in girişleri
//  Yazan: Claude, 04.11.2026 (final/, Adım 5b)
// =============================================================================
`timescale 1ns/1ps

module grup_kurucu #(
    parameter R = 16,
    parameter C = 16                 // SRU grubu en çok 16 değer (lms_group16): C = 16
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire [R*C*128-1:0]   cikis_flat,
    input  wire [R*C*288-1:0]   g_flat,
    input  wire                 kur,
    input  wire                 akum_mi,
    input  wire [3:0]           sec,
    input  wire [R-1:0]         satir_maske,
    input  wire [4:0]           n_sutun,
    input  wire                 son_it,
    output wire [R-1:0]         push_group_all,
    output wire [R*16*32-1:0]   group_in_flat_all,
    output wire [R*5-1:0]       group_n_all,
    output wire [R-1:0]         last_group_all
);

    genvar i, j;
    generate
        for (i = 0; i < R; i = i + 1) begin : satir
            // ---- Bu çevrimde kurulan grup ----
            wire [16*32-1:0] yeni;
            for (j = 0; j < 16; j = j + 1) begin : sutun
                localparam I = i*C + j;
                wire [31:0] serit = cikis_flat[128*I + 32*sec[1:0] +: 32];
                wire [31:0] akum  = g_flat[288*I + 32*sec +: 32];
                assign yeni[32*j +: 32] = (j < n_sutun) ? (akum_mi ? akum : serit) : 32'd0;
            end

            // ---- Bekleyen (son) grup ----
            reg [16*32-1:0] bek_veri;
            reg [4:0]       bek_n;
            reg             bek_var;
            initial begin bek_veri = 0; bek_n = 0; bek_var = 1'b0; end

            wire gelen = kur && satir_maske[i];
            always @(posedge clk) begin
                if (rst) begin
                    bek_var <= 1'b0;
                end else if (gelen) begin
                    bek_veri <= yeni;
                    bek_n    <= n_sutun;
                    bek_var  <= 1'b1;
                end else if (son_it) begin
                    bek_var  <= 1'b0;
                end
            end

            assign push_group_all[i]               = bek_var && (gelen || son_it) && !rst;
            assign last_group_all[i]               = son_it;
            assign group_in_flat_all[512*i +: 512] = bek_veri;
            assign group_n_all[5*i +: 5]           = bek_n;
        end
    endgenerate

endmodule
