// =============================================================================
//  sistem_veriyolu.v — Komut yürütücüsü + bellek (Adım 4, Paket 2)
// -----------------------------------------------------------------------------
//  FSM'siz veri yolu: FSM'in komut arayüzünü (kom, kom_gecerli, kom_bitti, maks_G) dışarı
//  verir. Paket 2'de testbench komutlar.txt'i FSM gibi verir; Paket 3'te üst modül bu bloğu
//  master_controller'a bağlayacak (ARAYUZ_SOZLESMESI.md Bölüm 1).
//  Yazan: Claude, 03.11.2026
//
//  Portlar:
//    clk, rst                 : saat; eşzamanlı aktif-yüksek reset
//    kom [159:0], kom_gecerli : FSM'in komutu (10 × 16 bit) ve geçerli seviyesi
//    kom_bitti                : 1 çevrimlik darbe
//    maks_G [5:0]             : SRU'nun G'si (FSM'in maks_G girişine)
//    cfg_*                    : komut_yurutucu.v'deki yapılandırma portları
//    hata [5:0]               : komut_yurutucu.v'deki yapışkan hata bayrakları
//  Bellek: bellek.v, BOYUT bayt; testbench u_bellek.mem'e hiyerarşik erişir.
// =============================================================================
`timescale 1ns/1ps

module sistem_veriyolu #(
    parameter AW    = 13,
    parameter BOYUT = 8192,
    parameter LMAX  = 8
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire [159:0]            kom,
    input  wire                    kom_gecerli,
    output wire                    kom_bitti,
    output wire [5:0]              maks_G,
    input  wire [LMAX*8-1:0]       cfg_cin, cfg_cout, cfg_h, cfg_w, cfg_s, cfg_p,
    input  wire [(LMAX+1)*AW-1:0]  cfg_taban_akt, cfg_taban_hata, cfg_taban_agr,
    input  wire [AW-1:0]           cfg_taban_etiket,
    output wire [5:0]              hata
);

    wire [AW-1:0]  oku_a_adr, oku_b_adr, yaz_adr;
    wire [127:0]   oku_a_veri, oku_b_veri, yaz_veri;
    wire           yaz;
    wire [4:0]     yaz_n;

    komut_yurutucu #(.AW(AW), .LMAX(LMAX)) u_yur (
        .clk(clk), .rst(rst),
        .kom(kom), .kom_gecerli(kom_gecerli), .kom_bitti(kom_bitti), .maks_G(maks_G),
        .cfg_cin(cfg_cin), .cfg_cout(cfg_cout), .cfg_h(cfg_h), .cfg_w(cfg_w),
        .cfg_s(cfg_s), .cfg_p(cfg_p),
        .cfg_taban_akt(cfg_taban_akt), .cfg_taban_hata(cfg_taban_hata),
        .cfg_taban_agr(cfg_taban_agr), .cfg_taban_etiket(cfg_taban_etiket),
        .oku_a_adr(oku_a_adr), .oku_a_veri(oku_a_veri),
        .oku_b_adr(oku_b_adr), .oku_b_veri(oku_b_veri),
        .yaz(yaz), .yaz_adr(yaz_adr), .yaz_n(yaz_n), .yaz_veri(yaz_veri),
        .hata(hata)
    );

    bellek #(.AW(AW), .BOYUT(BOYUT)) u_bellek (
        .clk(clk),
        .oku_a_adr(oku_a_adr), .oku_a_veri(oku_a_veri),
        .oku_b_adr(oku_b_adr), .oku_b_veri(oku_b_veri),
        .yaz(yaz), .yaz_adr(yaz_adr), .yaz_n(yaz_n), .yaz_veri(yaz_veri)
    );

endmodule
