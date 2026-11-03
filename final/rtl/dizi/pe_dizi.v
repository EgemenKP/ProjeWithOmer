// =============================================================================
//  pe_dizi.v — Shao Fig. 8'in 16x16 PE dizisi (Adım 5a)
// -----------------------------------------------------------------------------
//  Kaynak: Shao ISVLSI 2021, III-D (s. 258): "The PEs are arranged in a two-dimensional
//  array manner with a size of 16x16, where each row shares the same input and each
//  column shares the same weight." Fig. 8: giriş (mavi) satır boyunca yatay, ağırlık
//  (kırmızı) sütun boyunca dikey yayılıyor; her satırın çıkışları (yeşil) satır sonundaki
//  SRU'ya gidiyor (D30).
//
//  - Her hücre bir pe_birlesik (D69, 9 MAC; MAC'ler DSP'de, D75).
//  - Satır r'deki 16 PE aynı akis1/2/3'ü, sütun c'deki 16 PE aynı 9 ağırlığı alır. WG'de
//    port 1 hata taşıdığı için (Fig. 2: "Weights/Errors") hata akışı da satır girişinden
//    gelir (pe_birlesik'in akis2/akis3'ü); sütuna ne açılacağı ön-getirmenin işi (D72, D73).
//  - Psum FIFO her PE'nin içinde (III-A, Fig. 2; D74). Kayıt = PE'nin 128 bitlik çıkışı
//    (4 şerit; FP/BP s1'de yalnızca şerit 0 dolu). Okumada BP s2'nin B şeritleri (1, 3) bir
//    çevrim gecikmeli verilir: pe_motoru'nda psB(t) = psum[t-1], psA(t) = psum[t] (D66).
//  - Bütün PE'ler aynı kontrolle, aynı çevrimde çalışır (kontrol sinyalleri dizi geneli).
//  - Grubun SRU'ya kurulması (moda göre hangi şerit/akümülatör) ve dizi kontrolü 5b'nin işi;
//    bu modül çıkışları ham verir.
//
//  Portlar:
//    clk, rst       : saat; rst yalnızca WG'de PE akümülatörlerini sıfırlar (pe_birlesik)
//    mod [2:0]      : pe_birlesik'teki gibi (0 FP s1 .. 5 WG s2, 6/7 boşta)
//    satir_akis1/2/3_flat [R*24] : satır r'nin akisN'i [24r +: 24]
//    sutun_w_flat   [C*72] : sütun c'nin 9 ağırlığı [72c +: 72]
//    ps_temizle     : bütün Psum FIFO'larını boşaltır (İŞ_BAŞLA'da)
//    ps_yaz         : her PE kendi cikis_flat'ını kendi FIFO'suna yazar
//    ps_oku         : her PE kendi FIFO'sunun baştaki kaydını çıkarır
//    ps_sec         : 1 ise A şeritlerine (0, 2) baştaki kayıt, 0 ise 0 verilir
//    cikis_flat [R*C*128], g_flat [R*C*288] : PE (r,c)'nin çıkışları, indis r*C + c
//    ps_tasma, ps_eksik : bütün FIFO'ların bayraklarının VEYA'sı (testte 0 kalmalı)
//  Yazan: Claude, 04.11.2026 (final/, Adım 5a)
// =============================================================================
`timescale 1ns/1ps

module pe_dizi #(
    parameter R           = 16,
    parameter C           = 16,
    parameter PS_DERINLIK = 64,      // D74: açık (D12), test ağı için yeterli
    parameter PS_AW       = 6
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire [2:0]           mod,
    input  wire [R*24-1:0]      satir_akis1_flat,
    input  wire [R*24-1:0]      satir_akis2_flat,
    input  wire [R*24-1:0]      satir_akis3_flat,
    input  wire [C*72-1:0]      sutun_w_flat,
    input  wire                 ps_temizle,
    input  wire                 ps_yaz,
    input  wire                 ps_oku,
    input  wire                 ps_sec,
    output wire [R*C*128-1:0]   cikis_flat,
    output wire [R*C*288-1:0]   g_flat,
    output wire                 ps_tasma,
    output wire                 ps_eksik
);

    localparam BP_S2 = 3'd3;

    wire [R*C-1:0] tasma_v, eksik_v;
    assign ps_tasma = |tasma_v;
    assign ps_eksik = |eksik_v;

    genvar r, c;
    generate
        for (r = 0; r < R; r = r + 1) begin : satir
            for (c = 0; c < C; c = c + 1) begin : sutun
                localparam I = r*C + c;

                wire [127:0] cikis;
                wire [127:0] bas;
                wire         bos, dolu;
                wire [PS_AW:0] doluluk;

                // ---- PE içi Psum FIFO (D74) ----
                psum_fifo #(.GENISLIK(128), .DERINLIK(PS_DERINLIK), .AW(PS_AW)) u_ps (
                    .clk(clk), .rst(ps_temizle), .yaz(ps_yaz), .yaz_veri(cikis), .oku(ps_oku),
                    .bas_veri(bas), .bos(bos), .dolu(dolu), .doluluk(doluluk),
                    .tasma(tasma_v[I]), .eksik(eksik_v[I])
                );

                // BP s2'nin B şeritleri: bir önceki çevrimde çıkarılan kayıt
                reg [127:0] b_gec;
                initial b_gec = 128'd0;
                always @(posedge clk)
                    b_gec <= (ps_oku && !bos && !ps_temizle) ? bas : 128'd0;

                wire [127:0] a_ps = ps_sec ? bas : 128'd0;
                wire [127:0] ps   = (mod == BP_S2) ? {b_gec[96 +: 32], a_ps[64 +: 32], b_gec[32 +: 32], a_ps[0 +: 32]}
                                                   : {96'd0, a_ps[0 +: 32]};

                pe_birlesik u_pe (
                    .clk(clk), .rst(rst), .mod(mod),
                    .w_flat(sutun_w_flat[72*c +: 72]),
                    .akis1(satir_akis1_flat[24*r +: 24]),
                    .akis2(satir_akis2_flat[24*r +: 24]),
                    .akis3(satir_akis3_flat[24*r +: 24]),
                    .ps_flat(ps),
                    .cikis_flat(cikis),
                    .g_flat(g_flat[288*I +: 288])
                );

                assign cikis_flat[128*I +: 128] = cikis;
            end
        end
    endgenerate

endmodule
